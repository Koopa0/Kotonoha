// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/japanese_written_form.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/dictation/dictation_viewmodel.dart';
import 'package:provider/provider.dart';

/// 文字を起こす — dictation. Hear a word, then ASSEMBLE it from kana tiles (its
/// own kana plus a few distractors). This is the production / encoding rep the
/// learner is otherwise missing — recognition tells you nothing about whether he
/// can call the written shape up himself.
///
/// A thin View over [DictationViewModel]: it owns playback (generations, the
/// owned utterance and in-flight state), the lifecycle listener, the scroll
/// position, rendering and navigation. The board, what a completed play
/// *means*, the assemble clock and every schedule or analytics write are the
/// ViewModel's; the view only reports play outcomes and interrupts to it.
class DictationScreen extends StatefulWidget {
  const DictationScreen({
    required this.words,
    required this.title,
    this.clock,
    this.monotonicMs,
    this.onMore,
    this.alreadyTransferredIds = const {},
    super.key,
  });

  final List<Word> words;
  final String title;

  /// Optional clock / monotonic elapsed for tests. Production leaves both
  /// null so the view-model uses [DateTime.now] and [Stopwatch].
  final DateTime Function()? clock;
  final int Function()? monotonicMs;

  /// Opt-in "one more" — a fresh session (home builds it, night-suppressed).
  final VoidCallback? onMore;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// word may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  static Route<void> route(
    List<Word> words,
    String title, {
    VoidCallback? onMore,
    DateTime Function()? clock,
    int Function()? monotonicMs,
    Set<String> alreadyTransferredIds = const {},
  }) => MaterialPageRoute<void>(
    builder: (_) => DictationScreen(
      words: words,
      title: title,
      onMore: onMore,
      clock: clock,
      monotonicMs: monotonicMs,
      alreadyTransferredIds: alreadyTransferredIds,
    ),
  );

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final ScrollController _scrollController = ScrollController();

  late final DictationViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;

  int _playGen = 0;
  int? _ownedPlay;
  int _shownIndex = 0;
  bool _shownChecked = false;
  bool _closed = false;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  @override
  void initState() {
    super.initState();
    _vm = DictationViewModel(
      items: widget.words,
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
    _lifecycle = AppLifecycleListener(
      onInactive: _onUnanswerable,
      onHide: _onUnanswerable,
      onPause: _onUnanswerable,
      onDetach: _onUnanswerable,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_play());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonPlayback();
    _scrollController.dispose();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  void _onUnanswerable() {
    if (_vm.isFinished) return;
    // Stopping audio is independent of whether the item is already
    // assembled — a reveal replay must cancel in the background too.
    _abandonPlayback();
    _vm.noteInterrupted();
  }

  /// Cancels this screen's in-flight playback and drops its local generation.
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

  /// A new listening item must open on its prompt. Same-word assemble / clear
  /// / reveal keep the user's place — only the target change jumps back.
  void _scrollToPrompt() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  /// Session transitions are the ViewModel's; what they mean for the
  /// utterance is the view's. A check replays the word over its reveal; a
  /// new word drops the old play, returns to the prompt and auto-plays once
  /// it has a frame; the close leaves the last utterance behind.
  void _onChanged() {
    if (_vm.isFinished) {
      if (_closed) return;
      _closed = true;
      _abandonPlayback();
      return;
    }
    if (_vm.index != _shownIndex) {
      _shownIndex = _vm.index;
      _shownChecked = false;
      _abandonPlayback();
      _scrollToPrompt();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _vm.isFinished) return;
        unawaited(_play());
      });
      return;
    }
    if (_vm.isChecked && !_shownChecked) {
      _shownChecked = true;
      unawaited(_play());
    }
  }

  Future<void> _play() async {
    if (!mounted || _vm.isFinished) return;
    final itemIndex = _vm.index;
    final startedBlind = !_vm.isChecked;
    final gen = ++_playGen;
    final pending = _speech.play(_vm.current.kana);
    _ownedPlay = _speech.generation;
    final result = await pending;
    if (!mounted ||
        _vm.isFinished ||
        gen != _playGen ||
        _vm.index != itemIndex) {
      return;
    }
    _vm.notePlayback(
      itemIndex: itemIndex,
      result: result,
      startedBlind: startedBlind,
    );
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

  String? get _playbackStatus {
    if (_vm.blindHeard) return null;
    return switch (_vm.lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.dictationUnavailable,
      SpeechPlaybackResult.failed => AppStrings.dictationFailed,
      SpeechPlaybackResult.interrupted => AppStrings.dictationInterrupted,
      SpeechPlaybackResult.played || null => null,
    };
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    return SessionSummary(
      headline: AppStrings.readingSummary(_vm.correctCount, _vm.total),
      // The classical 余韻 (when picked) replaces the close note.
      note: _vm.share == null
          ? AppStrings.closing(widget.words.last.kana, band: band)
          : null,
      share: _vm.share,
      onDone: () => Navigator.of(context).pop(),
      // Night close grants permission to stop — suppress もう一回 at render time.
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    final current = _vm.current;
    final target = _vm.targetUnits;
    final tiles = _vm.tiles;
    final checked = _vm.isChecked;
    // Slots wrap when a word's units exceed the width; the page scrolls when
    // the column exceeds a short or large-text viewport. Slot boxes are sized
    // for a two-kana unit without reading the glyph, so layout cannot leak
    // the answer before reveal.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.itemProgress(_vm.index + 1, _vm.total),
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SpeakButton(
                    key: const ValueKey<String>('dictation-replay'),
                    text: current.kana,
                    prominent: true,
                    size: 40,
                    onPlay: () => unawaited(_play()),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    AppStrings.dictationPrompt,
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
                  ),
                  if (_playbackStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _playbackStatus!,
                      key: const ValueKey<String>('dictation-sound-status'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < target.length; i++)
                          _Slot(
                            key: ValueKey<String>('dictation-slot-$i'),
                            char: _vm.slotUnit(i),
                            state: !checked
                                ? _SlotState.building
                                : (_vm.wasCorrect
                                      ? _SlotState.right
                                      : _SlotState.wrong),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!checked)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < tiles.length; i++)
                            if (!_vm.isTileUsed(i))
                              _Tile(
                                label: tiles[i],
                                onTap: () => _vm.tapTile(i),
                              ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The same identity block the reading & ferry
                          // reveals show. On a miss, lead with the answer's
                          // kana; romaji + meaning follow.
                          if (!_vm.wasCorrect) ...[
                            Text(
                              current.kana,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 34,
                                height: 1.1,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
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
                      ),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: checked
                        ? SizedBox(
                            height: 54,
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _vm.next,
                              child: const Text(AppStrings.dictationNext),
                            ),
                          )
                        : SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                side: const BorderSide(
                                  color: AppColors.hairline,
                                ),
                                foregroundColor: AppColors.inkMuted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _vm.picked.isEmpty ? null : _vm.clear,
                              child: const Text(AppStrings.dictationClear),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _SlotState { building, right, wrong }

class _Slot extends StatelessWidget {
  const _Slot({required this.char, required this.state, super.key});

  /// Tokenizer units are at most two kana (yōon / small-vowel). Every slot
  /// uses this box so layout never inspects [char] — empty and filled sizes
  /// match, and the answer is not leaked before reveal.
  static const int _maxUnitGlyphs = 2;
  static const double _glyphSize = 30;
  static const double _minSide = 48;

  final String? char;
  final _SlotState state;

  @override
  Widget build(BuildContext context) {
    final border = switch (state) {
      _SlotState.building => AppColors.hairline,
      _SlotState.right => AppColors.success,
      _SlotState.wrong => AppColors.error,
    };
    final scaler = MediaQuery.textScalerOf(context);
    final glyph = scaler.scale(_glyphSize);
    final width = max(_minSide, glyph * _maxUnitGlyphs + scaler.scale(16));
    final height = max(_minSide, scaler.scale(64));
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Center(
          child: Text(
            char ?? '',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: _glyphSize,
              color: AppColors.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap});

  static const double _labelSize = 28;
  static const double _minSide = 48;

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final side = max(_minSide, MediaQuery.textScalerOf(context).scale(56));
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: side,
          height: side,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: _labelSize,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
