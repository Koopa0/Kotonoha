// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/japanese_written_form.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/listening/listening_viewmodel.dart';
import 'package:provider/provider.dart';

/// 聞き取り — listen first, recall unaided, reveal, then rehear.
///
/// A thin View over [ListeningViewModel]: it owns playback (generations, the
/// owned utterance, in-flight state and the last result), the lifecycle
/// observer, rendering and navigation. What a completed play *means* — blind
/// evidence, prompted practice, or nothing — and every schedule or analytics
/// write is the ViewModel's; the view only reports completed foreground
/// plays and interrupts to it.
class ListeningScreen extends StatefulWidget {
  const ListeningScreen({
    required this.items,
    required this.title,
    this.clock,
    this.monotonicMs,
    this.onMore,
    this.onFinished,
    this.alreadyTransferredIds = const {},
    super.key,
  });

  final List<ReadingItem> items;
  final String title;

  /// Optional clock / monotonic elapsed for tests. Production leaves both
  /// null so the view-model uses [DateTime.now] and [Stopwatch].
  final DateTime Function()? clock;
  final int Function()? monotonicMs;

  /// Opt-in "one more" — a fresh session (home builds it, night-suppressed).
  final VoidCallback? onMore;

  /// Official close (session summary) — not a mere open or pop.
  final VoidCallback? onFinished;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// item may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  static Route<void> route(
    List<ReadingItem> items,
    String title, {
    VoidCallback? onMore,
    VoidCallback? onFinished,
    DateTime Function()? clock,
    int Function()? monotonicMs,
    Set<String> alreadyTransferredIds = const {},
  }) => MaterialPageRoute<void>(
    builder: (_) => ListeningScreen(
      items: items,
      title: title,
      onMore: onMore,
      onFinished: onFinished,
      clock: clock,
      monotonicMs: monotonicMs,
      alreadyTransferredIds: alreadyTransferredIds,
    ),
  );

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen>
    with WidgetsBindingObserver {
  late final ListeningViewModel _vm;
  late final SpeechService _speech;
  int? _ownedPlay;
  int _playGen = 0;
  int _shownIndex = 0;
  bool _playing = false;
  bool _closed = false;
  SpeechPlaybackResult? _lastPlay;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  /// Speakable form — layout spaces removed.
  String get _say => _vm.current.displayText.replaceAll(' ', '');

  @override
  void initState() {
    super.initState();
    _vm = ListeningViewModel(
      items: widget.items,
      words: context.read<WordProgressRepository>(),
      kana: context.read<KanaProgressRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      alreadyTransferredIds: widget.alreadyTransferredIds,
      clock: widget.clock,
      monotonicMs: widget.monotonicMs,
    )..addListener(_onChanged);
    _speech = context.read<SpeechService>();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_play());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _abandonPlayback();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _interrupt();
  }

  /// Cancels this screen's in-flight playback and drops its local generation.
  ///
  /// Item switches must not wait for the next frame's [_play]: a late
  /// completion in that gap would still match [_playGen] and read the
  /// next item's unrevealed state.
  ///
  /// [SpeechService.stop] is scoped to [_ownedPlay] so a leaving
  /// `pushReplacement` cannot cancel the new route's utterance.
  void _abandonPlayback() {
    _playGen++;
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _interrupt() {
    _abandonPlayback();
    // An already-opened hear clock stays dead. Resume / replay must
    // not mint a fresh RT for this item.
    _vm.noteInterrupted();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _lastPlay = SpeechPlaybackResult.interrupted;
    });
  }

  /// Session transitions are the ViewModel's; what they mean for the
  /// utterance is the view's. A new item drops the old play and auto-plays
  /// once it has a frame; the close leaves the last utterance behind and
  /// reports the official finish.
  void _onChanged() {
    if (_vm.isFinished) {
      if (_closed) return;
      _closed = true;
      _abandonPlayback();
      widget.onFinished?.call();
      return;
    }
    if (_vm.index == _shownIndex) return;
    _shownIndex = _vm.index;
    _abandonPlayback();
    setState(() {
      _playing = false;
      _lastPlay = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _vm.isFinished) return;
      unawaited(_play());
    });
  }

  Future<void> _play() async {
    if (!mounted || _vm.isFinished) return;
    final itemIndex = _vm.index;
    final startedBlind = !_vm.isRevealed;
    final gen = ++_playGen;
    setState(() => _playing = true);
    final pending = _speech.play(_say);
    _ownedPlay = _speech.generation;
    final result = await pending;
    if (!mounted ||
        _vm.isFinished ||
        gen != _playGen ||
        _vm.index != itemIndex) {
      return;
    }
    setState(() {
      _playing = false;
      _lastPlay = result;
    });
    if (result == SpeechPlaybackResult.played) {
      _vm.noteHeard(itemIndex: itemIndex, startedBlind: startedBlind);
    }
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
      headline: AppStrings.listeningClose,
      note: _vm.share == null
          ? AppStrings.closing(widget.items.last.displayText, band: band)
          : null,
      share: _vm.share,
      onDone: () => Navigator.of(context).pop(),
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    final current = _vm.current;
    final revealed = _vm.isRevealed;
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                            IconButton.filled(
                              key: const ValueKey<String>('listening-replay'),
                              onPressed: () => unawaited(_play()),
                              iconSize: revealed ? 34 : 56,
                              tooltip: AppStrings.replaySound,
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.accentSoft,
                                foregroundColor: AppColors.accent,
                                padding: EdgeInsets.all(revealed ? 14 : 22),
                              ),
                              icon: Icon(
                                _playing
                                    ? Icons.graphic_eq_rounded
                                    : Icons.volume_up_rounded,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              revealed
                                  ? AppStrings.listeningRehear
                                  : AppStrings.listeningPrompt,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 15,
                              ),
                            ),
                            if (!revealed) ...[
                              const SizedBox(height: 8),
                              const Text(
                                AppStrings.listeningRecall,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.inkMuted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (revealed) ...[
                              const SizedBox(height: 20),
                              Text(
                                current.displayText,
                                key: const ValueKey<String>('listening-answer'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 34,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              JapaneseWrittenForm(item: current),
                              Text(
                                current.romaji,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                current.meaning,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                            if (_blockMessage != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _blockMessage!,
                                key: const ValueKey<String>('listening-block'),
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
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _controls(),
        ),
      ],
    );
  }

  /// Why the current item cannot be graded, if it cannot. Hearing state is
  /// the ViewModel's; the last playback result is this view's.
  String? get _blockMessage {
    if (_vm.blindHeard) return null;
    if (_vm.promptedHeard) return AppStrings.listeningPrompted;
    return switch (_lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.listeningUnavailable,
      SpeechPlaybackResult.failed => AppStrings.listeningFailed,
      SpeechPlaybackResult.interrupted => AppStrings.listeningInterrupted,
      SpeechPlaybackResult.played => null,
      null => _vm.isRevealed ? AppStrings.listeningInterrupted : null,
    };
  }

  Widget _controls() {
    if (!_vm.isRevealed) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey<String>('listening-reveal'),
          onPressed: _vm.reveal,
          child: const Text(AppStrings.listeningReveal),
        ),
      );
    }
    if (_vm.blindHeard) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () => _vm.gradeBlind(correct: true),
              child: const Text(AppStrings.listeningHeard),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                foregroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => _vm.gradeBlind(correct: false),
              child: const Text(AppStrings.listeningMissed),
            ),
          ),
        ],
      );
    }
    if (_vm.promptedHeard) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey<String>('listening-next'),
          onPressed: _vm.continuePrompted,
          child: const Text(AppStrings.listeningNext),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: const ValueKey<String>('listening-skip'),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.hairline),
          foregroundColor: AppColors.inkMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _vm.skipUnheard,
        child: const Text(AppStrings.listeningSkip),
      ),
    );
  }
}
