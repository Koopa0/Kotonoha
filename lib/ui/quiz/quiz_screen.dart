// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_grid.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:provider/provider.dart';

/// A thin View over [QuizViewModel]: renders the current question, forwards
/// taps, applies a calm auto-advance delay, and navigates on completion.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    required this.items,
    required this.title,
    super.key,
    this.lesson,
    this.onAgain,
    this.onFinished,
    this.transferItems,
    this.quiet = false,
    this.alreadyTransferredIds = const {},
    this.clock,
    this.monotonicMs,
  });

  final List<SessionItem> items;
  final String title;

  /// Word / sentence transfer after the kana run (今日の稽古 only).
  /// Empty keeps the existing result screen. Not a new home entry.
  final List<ReadingItem>? transferItems;

  /// Silent 今日の稽古: no listening prompts, and transfer must not speak.
  final bool quiet;

  /// Progress ids already shown in this 「もう一回」 grind. Transfer may wrap
  /// over them after coverage, but must not renew their schedule.
  final Set<String> alreadyTransferredIds;

  /// Set when this is a lesson test — drives pass/learned handling on results.
  final Lesson? lesson;

  /// Forwarded to the result screen as the "再来一回" action (repeatable drills
  /// only). Null for lessons / one-shot pools.
  final VoidCallback? onAgain;

  /// Official close (result or word transfer) — not a mere open or pop.
  final VoidCallback? onFinished;

  /// Optional clock / monotonic elapsed for tests. Production leaves both
  /// null so the view-model uses [DateTime.now] and [Stopwatch].
  final DateTime Function()? clock;
  final int Function()? monotonicMs;

  /// Single-mode session: wrap each question with the given [mode].
  static Route<void> route({
    required List<QuizQuestion> questions,
    required String title,
    required PracticeMode mode,
    Lesson? lesson,
    VoidCallback? onAgain,
    VoidCallback? onFinished,
    List<ReadingItem>? transferItems,
    bool quiet = false,
    Set<String> alreadyTransferredIds = const {},
  }) {
    return routeItems(
      items: [for (final q in questions) SessionItem(question: q, mode: mode)],
      title: title,
      lesson: lesson,
      onAgain: onAgain,
      onFinished: onFinished,
      transferItems: transferItems,
      quiet: quiet,
      alreadyTransferredIds: alreadyTransferredIds,
    );
  }

  /// Mixed-mode session (adaptive "today's session").
  static Route<void> routeItems({
    required List<SessionItem> items,
    required String title,
    Lesson? lesson,
    VoidCallback? onAgain,
    VoidCallback? onFinished,
    List<ReadingItem>? transferItems,
    bool quiet = false,
    Set<String> alreadyTransferredIds = const {},
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => QuizScreen(
        items: items,
        title: title,
        lesson: lesson,
        onAgain: onAgain,
        onFinished: onFinished,
        transferItems: transferItems,
        quiet: quiet,
        alreadyTransferredIds: alreadyTransferredIds,
      ),
    );
  }

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuizViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  Timer? _advanceTimer;
  bool _navigated = false;
  bool _answerable = true;
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  bool _recallRevealed = false;
  bool _recallUnpromptedCommit = false;
  int _playGen = 0;
  bool _blindHeard = false;
  String? _heardItemId;
  SpeechPlaybackResult? _lastPlay;

  /// True when the CURRENT question is listening (sound → kana). Per-item, so an
  /// adaptive session can have listening questions mixed in.
  bool get _isListening =>
      _vm.items.isNotEmpty &&
      !_vm.isFinished &&
      _vm.current.direction == QuizDirection.soundToKana;

  @override
  void initState() {
    super.initState();
    _vm = QuizViewModel(
      items: widget.items,
      repository: context.read<KanaProgressRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      clock: widget.clock,
      monotonicMs: widget.monotonicMs,
    )..addListener(_onChanged);
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reportPresentation();
      if (_isListening) {
        unawaited(_playCurrent());
      }
    });
  }

  bool get _isVisible =>
      _lifecycleState == AppLifecycleState.resumed ||
      _lifecycleState == AppLifecycleState.inactive;

  void _onLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _answerable = state == AppLifecycleState.resumed;
    if (!_answerable) {
      // Invalidate an already-shown clock now. Whether this question
      // is newly exposed is decided by a later painted frame, not by
      // which state we came from — inactive after hidden can stay
      // visible and draw.
      _vm.noteUnanswerable();
      _schedulePresentationReport();
      if (!_isListening) return;
      // Stop in-flight play even after the item is graded — a reveal
      // replay must not keep speaking in the background.
      _abandonPlayback();
      if (mounted) {
        setState(() => _lastPlay = SpeechPlaybackResult.interrupted);
      }
      return;
    }
    _schedulePresentationReport();
  }

  /// A painted frame while `resumed` can start RT. The same frame while
  /// still `inactive` is exposure and must not restart later. A frame
  /// that only lands after we are already `resumed` is a pure restore
  /// transition, not a lingering visible inactive.
  void _reportPresentation() {
    if (!mounted || _vm.isAnswered || _vm.isFinished) return;
    if (!_isVisible) return;
    if (_answerable) {
      _vm.noteAnswerablePresentation();
    } else {
      _vm.noteUnanswerable(stillVisible: true);
    }
  }

  void _schedulePresentationReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportPresentation();
    });
  }

  void _abandonPlayback() {
    _playGen++;
    unawaited(_speech.stop());
  }

  void _resetHearing() {
    _blindHeard = false;
    _heardItemId = null;
    _lastPlay = null;
  }

  Future<void> _playCurrent() async {
    if (!mounted || !_isListening || _vm.isFinished) return;
    final itemId = _vm.current.target.id;
    final questionIndex = _vm.index;
    final alreadyAnswered = _vm.isAnswered;
    final startedAnswerable = _answerable;
    // Background must not start a new unanswered play. Graded rehear is
    // started only from an explicit tap while the route is still up.
    if (!alreadyAnswered && !startedAnswerable) return;
    final gen = ++_playGen;
    final result = await _speech.play(_vm.current.target.character);
    if (!mounted ||
        _vm.isFinished ||
        gen != _playGen ||
        _vm.index != questionIndex ||
        _vm.current.target.id != itemId) {
      return;
    }
    setState(() {
      _lastPlay = result;
      if (result != SpeechPlaybackResult.played) return;
      if (alreadyAnswered || _vm.isAnswered) return;
      if (!startedAnswerable || !_answerable) return;
      _blindHeard = true;
      _heardItemId = itemId;
      _vm.noteListeningHeard();
    });
  }

  void _selectListening(int optionIndex) {
    final heard = _blindHeard && _heardItemId == _vm.current.target.id;
    final playback = heard
        ? SpeechPlaybackResult.played
        : (_lastPlay ?? SpeechPlaybackResult.interrupted);
    _vm.selectAnswer(
      optionIndex,
      persistProgress: heard,
      extraMeta: {
        AttemptMeta.playback: playback.name,
        AttemptMeta.heard: heard,
        AttemptMeta.scored: heard,
        AttemptMeta.prompted: false,
      },
    );
  }

  void _onChanged() {
    // Birth while hidden/paused stays unpresented until a visible
    // frame. A painted inactive frame is exposure.
    if (!_answerable) {
      _vm.noteUnanswerable();
    }
    _schedulePresentationReport();
    if (!_vm.isAnswered) {
      _recallRevealed = false;
      _recallUnpromptedCommit = false;
    }
    if (_vm.isFinished) {
      _abandonPlayback();
      _goToResults();
      return;
    }
    // Auto-play each new sound only while the item is answerable.
    // A background auto-advance must not start or credit a new hear.
    if (_isListening && !_vm.isAnswered && _answerable) {
      unawaited(_playCurrent());
    }
    // Calm auto-advance: linger a touch longer on a wrong answer.
    if (_vm.isAnswered && _advanceTimer == null) {
      final correct = _vm.lastWasCorrect ?? true;
      _advanceTimer = Timer(Duration(milliseconds: correct ? 750 : 1150), () {
        _advanceTimer = null;
        _abandonPlayback();
        _resetHearing();
        _vm.advance();
      });
    }
  }

  void _advanceNow() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _abandonPlayback();
    _resetHearing();
    _vm.advance();
  }

  Widget _recallActions() {
    if (_recallRevealed) {
      final unprompted = _recallUnpromptedCommit;
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                side: const BorderSide(color: AppColors.error),
                foregroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () =>
                  _vm.gradeRecall(correct: false, unprompted: unprompted),
              child: const Text(AppStrings.iCouldnt),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: () =>
                  _vm.gradeRecall(correct: true, unprompted: unprompted),
              child: Text(
                unprompted ? AppStrings.iReadIt : AppStrings.iReadAfterHint,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => setState(() {
              _recallUnpromptedCommit = false;
              _recallRevealed = true;
            }),
            child: const Text(AppStrings.recallHint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: () {
              _vm.captureUnpromptedRecall();
              setState(() {
                _recallUnpromptedCommit = true;
                _recallRevealed = true;
              });
            },
            child: const Text(AppStrings.iReadUnprompted),
          ),
        ),
      ],
    );
  }

  void _goToResults() {
    if (_navigated) return;
    _navigated = true;
    widget.onFinished?.call();
    final transfer = widget.transferItems;
    if (transfer != null && transfer.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        ReadingScreen.route(
          transfer,
          widget.title,
          onMore: widget.onAgain,
          quiet: widget.quiet,
          alreadyTransferredIds: widget.alreadyTransferredIds,
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      QuizResultScreen.route(
        _vm.result,
        lesson: widget.lesson,
        onAgain: widget.onAgain,
      ),
    );
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _lifecycle.dispose();
    _abandonPlayback();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            if (_vm.items.isEmpty || _vm.isFinished) {
              return const SizedBox.shrink();
            }
            final q = _vm.current;
            final dir = q.direction;
            final isRecall = dir == QuizDirection.kanaRecall;
            final isKanaPrompt = dir == QuizDirection.kanaToRomaji || isRecall;
            final isListening = dir == QuizDirection.soundToKana;
            // Options are big kana except when the answer is romaji.
            final optionFontSize = isKanaPrompt ? 22.0 : 34.0;
            final instruction = switch (dir) {
              QuizDirection.kanaToRomaji => AppStrings.chooseRomaji,
              QuizDirection.romajiToKana => AppStrings.chooseKana,
              QuizDirection.soundToKana => AppStrings.chooseBySound,
              QuizDirection.kanaRecall => AppStrings.readPrompt,
            };

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        '${_vm.index + 1} / ${_vm.total}',
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _vm.progress,
                            minHeight: 6,
                            backgroundColor: AppColors.hairline,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: Column(
                      children: [
                        Text(
                          instruction,
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (isListening)
                          _SoundPrompt(
                            onReplay: () => unawaited(_playCurrent()),
                            status: _soundStatus,
                          )
                        else
                          _PromptCard(
                            text: q.prompt,
                            big: isKanaPrompt,
                            // Sound is the hidden reading on recall — never
                            // play it before the learner grades unprompted.
                            speakText: widget.quiet
                                ? null
                                : (isKanaPrompt && !isRecall
                                      ? q.target.character
                                      : (isRecall && _recallRevealed
                                            ? q.target.character
                                            : null)),
                          ),
                        if (isRecall && _recallRevealed) ...[
                          const SizedBox(height: 16),
                          Text(
                            q.correctAnswer,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                        if (!isRecall) ...[
                          const SizedBox(height: 28),
                          AnswerOptionGrid(
                            children: [
                              for (int i = 0; i < q.options.length; i++)
                                AnswerOptionButton(
                                  label: q.options[i],
                                  state: _vm.optionState(i),
                                  fontSize: optionFontSize,
                                  onTap: _vm.isAnswered
                                      ? null
                                      : () => isListening
                                            ? _selectListening(i)
                                            : _vm.selectAnswer(i),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: isRecall && !_vm.isAnswered
                      ? _recallActions()
                      : SizedBox(
                          height: 52,
                          child: _vm.isAnswered
                              ? FilledButton(
                                  onPressed: _advanceNow,
                                  child: Text(
                                    _vm.isLastQuestion
                                        ? AppStrings.seeResults
                                        : AppStrings.continueLabel,
                                  ),
                                )
                              : null,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? get _soundStatus {
    if (_blindHeard) return null;
    return switch (_lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.quizSoundUnavailable,
      SpeechPlaybackResult.failed => AppStrings.quizSoundFailed,
      SpeechPlaybackResult.interrupted => AppStrings.quizSoundInterrupted,
      SpeechPlaybackResult.played || null => null,
    };
  }
}

class _SoundPrompt extends StatelessWidget {
  const _SoundPrompt({required this.onReplay, this.status});

  final VoidCallback onReplay;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            key: const ValueKey<String>('quiz-replay'),
            onPressed: onReplay,
            iconSize: 56,
            tooltip: AppStrings.replaySound,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accentSoft,
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.all(20),
            ),
            icon: const Icon(Icons.volume_up_rounded),
          ),
          const SizedBox(height: 12),
          const Text(
            AppStrings.replaySound,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              status!,
              key: const ValueKey<String>('quiz-sound-status'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.text, required this.big, this.speakText});

  final String text;
  final bool big;

  /// When set, a speaker button reads this aloud (kana prompts only).
  final String? speakText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: big ? 96 : 52,
              height: 1.0,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
          if (speakText != null) ...[
            const SizedBox(height: 8),
            SpeakButton(text: speakText!, size: 30),
          ],
        ],
      ),
    );
  }
}
