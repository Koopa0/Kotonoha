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
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
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
  });

  final List<SessionItem> items;
  final String title;

  /// Set when this is a lesson test — drives pass/learned handling on results.
  final Lesson? lesson;

  /// Single-mode session: wrap each question with the given [mode].
  static Route<void> route({
    required List<QuizQuestion> questions,
    required String title,
    required PracticeMode mode,
    Lesson? lesson,
  }) {
    return routeItems(
      items: [for (final q in questions) SessionItem(question: q, mode: mode)],
      title: title,
      lesson: lesson,
    );
  }

  /// Mixed-mode session (adaptive "today's session").
  static Route<void> routeItems({
    required List<SessionItem> items,
    required String title,
    Lesson? lesson,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => QuizScreen(items: items, title: title, lesson: lesson),
    );
  }

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuizViewModel _vm;
  Timer? _advanceTimer;
  bool _navigated = false;
  int _spokenIndex = -1;

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
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
    )..addListener(_onChanged);
    if (_isListening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _spokenIndex = _vm.index;
        _speakCurrent();
      });
    }
  }

  void _speakCurrent() {
    if (!mounted) return;
    context.read<SpeechService>().speak(_vm.current.target.character);
  }

  void _onChanged() {
    if (_vm.isFinished) {
      _goToResults();
      return;
    }
    // Auto-play each new sound in listening mode (before it's answered).
    if (_isListening && !_vm.isAnswered && _spokenIndex != _vm.index) {
      _spokenIndex = _vm.index;
      _speakCurrent();
    }
    // Calm auto-advance: linger a touch longer on a wrong answer.
    if (_vm.isAnswered && _advanceTimer == null) {
      final correct = _vm.lastWasCorrect ?? true;
      _advanceTimer = Timer(Duration(milliseconds: correct ? 750 : 1150), () {
        _advanceTimer = null;
        _vm.advance();
      });
    }
  }

  void _advanceNow() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _vm.advance();
  }

  void _goToResults() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      QuizResultScreen.route(_vm.result, lesson: widget.lesson),
    );
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
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
            final isKanaPrompt = dir == QuizDirection.kanaToRomaji;
            final isListening = dir == QuizDirection.soundToKana;
            // Options are big kana except when the answer is romaji.
            final optionFontSize = isKanaPrompt ? 22.0 : 34.0;
            final instruction = switch (dir) {
              QuizDirection.kanaToRomaji => AppStrings.chooseRomaji,
              QuizDirection.romajiToKana => AppStrings.chooseKana,
              QuizDirection.soundToKana => AppStrings.chooseBySound,
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
                            color: AppColors.skyBlue,
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
                          _SoundPrompt(onReplay: _speakCurrent)
                        else
                          _PromptCard(
                            text: q.prompt,
                            big: isKanaPrompt,
                            speakText: isKanaPrompt ? q.target.character : null,
                          ),
                        const SizedBox(height: 28),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 2.6,
                          children: [
                            for (int i = 0; i < q.options.length; i++)
                              AnswerOptionButton(
                                label: q.options[i],
                                state: _vm.optionState(i),
                                fontSize: optionFontSize,
                                onTap: _vm.isAnswered
                                    ? null
                                    : () => _vm.selectAnswer(i),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
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
}

class _SoundPrompt extends StatelessWidget {
  const _SoundPrompt({required this.onReplay});

  final VoidCallback onReplay;

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
            onPressed: onReplay,
            iconSize: 56,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.skyBlueSoft,
              foregroundColor: AppColors.skyBlue,
              padding: const EdgeInsets.all(20),
            ),
            icon: const Icon(Icons.volume_up_rounded),
          ),
          const SizedBox(height: 12),
          const Text(
            AppStrings.replaySound,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
          ),
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
