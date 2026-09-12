// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// 文字を起こす — dictation. Hear a word, then ASSEMBLE it from kana tiles (its
/// own kana plus a few distractors). This is the production / encoding rep the
/// learner is otherwise missing — recognition tells you nothing about whether he
/// can call the written shape up himself. Records a [Attempt] (mode=dictation),
/// rtMs = time to assemble.
class DictationScreen extends StatefulWidget {
  const DictationScreen({
    required this.words,
    required this.title,
    this.clock,
    this.onMore,
    this.alreadyTransferredIds = const {},
    super.key,
  });

  final List<Word> words;
  final String title;

  /// Injectable clock so the assembled-word reaction time is testable.
  final DateTime Function()? clock;

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
    Set<String> alreadyTransferredIds = const {},
  }) => MaterialPageRoute<void>(
    builder: (_) => DictationScreen(
      words: words,
      title: title,
      onMore: onMore,
      clock: clock,
      alreadyTransferredIds: alreadyTransferredIds,
    ),
  );

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();
  final ScrollController _scrollController = ScrollController();

  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? _share;
  int _index = 0;
  List<String> _tiles = const [];
  List<bool> _used = const [];
  final List<int> _picked = [];
  bool _checked = false;
  bool _wasCorrect = false;
  int _correct = 0;
  bool _done = false;
  int _shownAtMs = 0;
  int _playGen = 0;
  int? _ownedPlay;
  bool _blindHeard = false;
  String? _heardItemId;
  SpeechPlaybackResult? _lastPlay;

  Word get _current => widget.words[_index];

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  /// The word split into learning-unit tiles (きゃ stays one tile, っ/ー are
  /// their own tiles) — assembly works in the units the learner reads in.
  List<String> get _targetChars => KanaTokenizer.tokenize(_current.kana);

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _onUnanswerable,
      onHide: _onUnanswerable,
      onPause: _onUnanswerable,
      onDetach: _onUnanswerable,
    );
    _setup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_play());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonPlayback();
    _scrollController.dispose();
    super.dispose();
  }

  void _onUnanswerable() {
    if (_done) return;
    // Stopping audio is independent of whether the item is already
    // assembled — a reveal replay must cancel in the background too.
    _abandonPlayback();
    if (mounted) {
      setState(() => _lastPlay = SpeechPlaybackResult.interrupted);
    }
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

  void _resetHearing() {
    _blindHeard = false;
    _heardItemId = null;
    _lastPlay = null;
  }

  /// A new listening item must open on its prompt. Same-word assemble / clear
  /// / reveal keep the user's place — only the target change jumps back.
  void _scrollToPrompt() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  void _setup() {
    final chars = _targetChars;
    // Distractor tiles come from the word's own script — cross-script tiles
    // would give the answer away by shape alone.
    final distractorPool = _current.script == KanaScript.katakana
        ? kKatakanaGojuon
        : kHiraganaGojuon;
    final distractors =
        (distractorPool
                .map((k) => k.character)
                .where((c) => !chars.contains(c))
                .toList()
              ..shuffle(_rng))
            .take(3);
    _tiles = [...chars, ...distractors]..shuffle(_rng);
    _used = List<bool>.filled(_tiles.length, false);
    _picked.clear();
    _checked = false;
    _shownAtMs = _clock().millisecondsSinceEpoch;
  }

  Future<void> _play() async {
    if (!mounted || _done) return;
    final itemId = _current.progressId;
    final startedBlind = !_checked;
    final gen = ++_playGen;
    final pending = _speech.play(_current.kana);
    _ownedPlay = _speech.generation;
    final result = await pending;
    if (!mounted || _done || gen != _playGen || _current.progressId != itemId) {
      return;
    }
    setState(() {
      _lastPlay = result;
      if (result != SpeechPlaybackResult.played) return;
      if (startedBlind && !_checked) {
        _blindHeard = true;
        _heardItemId = itemId;
      }
    });
  }

  void _tapTile(int i) {
    if (_used[i] || _checked) return;
    setState(() {
      _used[i] = true;
      _picked.add(i);
    });
    if (_picked.length == _targetChars.length) _check();
  }

  void _clear() {
    setState(() {
      for (final i in _picked) {
        _used[i] = false;
      }
      _picked.clear();
    });
  }

  void _check() {
    final built = _picked.map((i) => _tiles[i]).join();
    final correct = built == _current.kana;
    final now = _clock();
    final heard = _blindHeard && _heardItemId == _current.progressId;
    final playback = heard
        ? SpeechPlaybackResult.played
        : (_lastPlay ?? SpeechPlaybackResult.interrupted);
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.kana,
        itemType: ItemType.word,
        mode: PracticeMode.dictation.name,
        correct: correct,
        rtMs: now.millisecondsSinceEpoch - _shownAtMs,
        sessionId: _sessionId,
        meta: {
          'romaji': _current.romaji,
          AttemptMeta.playback: playback.name,
          AttemptMeta.heard: heard,
          AttemptMeta.prompted: false,
          AttemptMeta.scored: heard,
        },
      ),
    );
    // Only a completed play *before* assembly is unprompted dictation
    // evidence. A later success cannot backfill SRS for this item.
    // A miss always resets. Unprompted correct climbs only the first
    // time this grind covers the id — wrap-around practice may repeat
    // the word but must not farm the schedule.
    if (heard) {
      final words = context.read<WordProgressRepository>();
      final persist = context.read<ProgressPersistenceController>();
      final id = _current.progressId;
      if (!correct) {
        persist.trackWord(words.recordAnswer(id, correct: false, at: now));
      } else if (DailyBridge.shouldRenew(id, widget.alreadyTransferredIds)) {
        persist.trackWord(words.recordAnswer(id, correct: true, at: now));
      }
    }
    if (correct) _correct++;
    setState(() {
      _checked = true;
      _wasCorrect = correct;
    });
    unawaited(_play());
  }

  void _next() {
    _abandonPlayback();
    if (_index + 1 >= widget.words.length) {
      final store = context.read<KanaProgressRepository>();
      _share = KotenShare.pick(
        pool: kKoten,
        seenKanaCount: store.seenCount,
        rng: _rng,
        season: Season.forMonth(_clock().month),
      );
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _resetHearing();
        _setup();
      });
      _scrollToPrompt();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _done) return;
        unawaited(_play());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: _done ? _summary() : _question()),
    );
  }

  String? get _playbackStatus {
    if (_blindHeard) return null;
    return switch (_lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.dictationUnavailable,
      SpeechPlaybackResult.failed => AppStrings.dictationFailed,
      SpeechPlaybackResult.interrupted => AppStrings.dictationInterrupted,
      SpeechPlaybackResult.played || null => null,
    };
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    return SessionSummary(
      headline: AppStrings.readingSummary(_correct, widget.words.length),
      // The classical 余韻 (when picked) replaces the close note.
      note: _share == null
          ? AppStrings.closing(widget.words.last.kana, band: band)
          : null,
      share: _share,
      onDone: () => Navigator.of(context).pop(),
      // Night close grants permission to stop — suppress もう一回 at render time.
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    final target = _targetChars;
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
                    AppStrings.itemProgress(_index + 1, widget.words.length),
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SpeakButton(
                    key: const ValueKey<String>('dictation-replay'),
                    text: _current.kana,
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
                            char: i < _picked.length
                                ? _tiles[_picked[i]]
                                : null,
                            state: !_checked
                                ? _SlotState.building
                                : (_wasCorrect
                                      ? _SlotState.right
                                      : _SlotState.wrong),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!_checked)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < _tiles.length; i++)
                            if (!_used[i])
                              _Tile(label: _tiles[i], onTap: () => _tapTile(i)),
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
                          if (!_wasCorrect) ...[
                            Text(
                              _current.kana,
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
                          Text(
                            _current.romaji,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _current.meaning,
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
                    child: _checked
                        ? SizedBox(
                            height: 54,
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _next,
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
                              onPressed: _picked.isEmpty ? null : _clear,
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
