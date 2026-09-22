// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/use_cases/particles.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/japanese_written_form.dart';
import 'package:kotonoha/ui/core/widgets/pull_note.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/reading/reading_viewmodel.dart';
import 'package:provider/provider.dart';

/// Contextual reading practice over [ReadingItem]s (the 黙読 sentence track): read
/// the kana, reveal the reading + meaning, hear it (the ear is the real grader),
/// and self-grade. A thin View over [ReadingViewModel]: it renders the session
/// state, forwards taps, owns the speaker and its lifecycle, and navigates.
/// Grading, schedule writes and the reading [Attempt] live on the ViewModel.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({
    required this.items,
    required this.title,
    this.clock,
    this.onMore,
    this.onFinished,
    this.quiet = false,
    this.alreadyTransferredIds = const {},
    super.key,
  });

  final List<ReadingItem> items;
  final String title;

  /// Injectable clock so 凪「もう一回」 and due dates stay testable by day.
  final DateTime Function()? clock;

  /// Opt-in "one more" — a fresh session in place of this one (home builds it,
  /// night-suppressed). Null = hidden.
  final VoidCallback? onMore;

  /// Official close (session summary) — not a mere open or pop.
  final VoidCallback? onFinished;

  /// Silent run: reveal must not speak, and the speaker stays hidden.
  final bool quiet;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// item may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  static Route<void> route(
    List<ReadingItem> items,
    String title, {
    VoidCallback? onMore,
    VoidCallback? onFinished,
    DateTime Function()? clock,
    bool quiet = false,
    Set<String> alreadyTransferredIds = const {},
  }) => MaterialPageRoute<void>(
    builder: (_) => ReadingScreen(
      items: items,
      title: title,
      onMore: onMore,
      onFinished: onFinished,
      clock: clock,
      quiet: quiet,
      alreadyTransferredIds: alreadyTransferredIds,
    ),
  );

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  late final ReadingViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;
  bool _closed = false;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  /// Speakable form — layout spaces removed.
  String get _say => _vm.current.displayText.replaceAll(' ', '');

  @override
  void initState() {
    super.initState();
    _vm = ReadingViewModel(
      items: widget.items,
      words: context.read<WordProgressRepository>(),
      kana: context.read<KanaProgressRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      alreadyTransferredIds: widget.alreadyTransferredIds,
      clock: widget.clock,
    )..addListener(_onChanged);
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
      onResume: _onResumed,
    );
    _playable = _foreground;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _onResumed() {
    _playable = true;
  }

  void _abandonOwnedPlayback() {
    _playable = false;
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  /// The close is the ViewModel's decision; leaving the last utterance
  /// behind and reporting the official finish are the view's.
  void _onChanged() {
    if (!_vm.isFinished || _closed) return;
    _closed = true;
    _abandonOwnedPlayback();
    widget.onFinished?.call();
  }

  void _speak() {
    if (!mounted || !_playable || !_foreground || widget.quiet) return;
    unawaited(_speech.speak(_say));
    _ownedPlay = _speech.generation;
  }

  void _reveal({required bool unpromptedCommit}) {
    _speak();
    _vm.reveal(unpromptedCommit: unpromptedCommit);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _vm.isFinished ? _summary() : _question(),
        ),
      ),
    );
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    return SessionSummary(
      headline: AppStrings.readingSummary(_vm.correctCount, _vm.total),
      // The classical 余韻 (when picked) replaces the close note — so only
      // compute the note when no share will lead.
      note: _vm.share == null
          ? AppStrings.closing(widget.items.last.displayText, band: band)
          : null,
      share: _vm.share,
      onDone: () => Navigator.of(context).pop(),
      // At night the close grants permission to stop — suppress もう一回 here, at
      // render time, so a session that began in daylight still hides it at dusk.
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    final current = _vm.current;
    // Phrases wrap at the same learner scale; only the starting size differs.
    final big = _say.length <= 4;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_vm.index + 1, _vm.total),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                key: const ValueKey<String>('reading-scroll'),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: AppColors.hairline),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 20,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      current.displayText,
                                      textAlign: TextAlign.center,
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: big ? 64 : 44,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (!_vm.isRevealed)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        AppStrings.readPrompt,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.inkMuted,
                                          fontSize: 15,
                                        ),
                                      ),
                                    )
                                  else ...[
                                    const Divider(
                                      height: 36,
                                      indent: 24,
                                      endIndent: 24,
                                    ),
                                    JapaneseWrittenForm(item: current),
                                    Text(
                                      current.romaji,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      current.meaning,
                                      key: const ValueKey<String>(
                                        'reading-meaning',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    if (!widget.quiet)
                                      SpeakButton(
                                        text: _say,
                                        size: 30,
                                        onPlay: _speak,
                                      ),
                                    for (final p in Particles.particlesIn(
                                      current.displayText,
                                    ))
                                      if (AppStrings.particleGloss(p)
                                          case final gloss?)
                                        PullNote(
                                          trigger:
                                              AppStrings.particleGlossTrigger,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Text(
                                              gloss,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: AppColors.inkMuted,
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        _vm.isRevealed ? _gradeControls() : _revealControls(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _revealControls() {
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
            onPressed: () => _reveal(unpromptedCommit: false),
            child: const Text(AppStrings.recallHint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: () => _reveal(unpromptedCommit: true),
            child: const Text(AppStrings.iReadUnprompted),
          ),
        ),
      ],
    );
  }

  Widget _gradeControls() {
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
            onPressed: () => _vm.grade(correct: false),
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
            onPressed: () => _vm.grade(correct: true),
            child: Text(
              _vm.unpromptedCommit
                  ? AppStrings.iReadIt
                  : AppStrings.iReadAfterHint,
            ),
          ),
        ),
      ],
    );
  }
}
