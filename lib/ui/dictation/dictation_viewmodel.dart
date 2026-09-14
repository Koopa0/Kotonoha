// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

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
import 'package:kotonoha/ui/core/item_reaction_clock.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns one 文字を起こす session: the cursor, the tile board (the word's own
/// units plus same-script distractors), the assembly, the auto-check, what a
/// reported play counts as, the assemble clock, and every progress or
/// analytics write. The screen plays audio, reports completed plays and
/// interrupts, renders, scrolls, and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - Every check is logged as a dictation [Attempt]; only a play that
///   started *and* completed before the check is unprompted evidence
///   ([blindHeard]) and may move SRS. A reveal replay cannot backfill it.
/// - A heard miss always resets. Heard correct climbs only the first time
///   this 「もう一回」 grind covers the id ([alreadyTransferredIds]).
/// - Valid [Attempt.rtMs] is foreground assemble time from the board's
///   show. An interrupt ([noteInterrupted]) freezes the clock — resume or
///   a same-word replay must not restart it. 0 is untimed.
///
/// This type never interprets playback: the view decides what a completed
/// play is and drops cancelled or stale generations before calling
/// [notePlayback]. Pure of timers, scrolling and navigation.
class DictationViewModel extends ChangeNotifier {
  DictationViewModel({
    required this.items,
    required this.words,
    required this.kana,
    required this.persistence,
    required this.analytics,
    this.sessionId = '',
    this.alreadyTransferredIds = const {},
    DateTime Function()? clock,
    int Function()? monotonicMs,
    Random? rng,
    this._kotenPool = kKoten,
  }) : _clock = clock ?? DateTime.now,
       _reaction = ItemReactionClock(clock: clock, monotonicMs: monotonicMs),
       _rng = rng ?? Random() {
    _setup();
  }

  /// How many same-script distractor tiles join the word's own units.
  static const int distractorCount = 3;

  final List<Word> items;

  /// Owner of the 詞と句 schedule this session grades into.
  final WordProgressRepository words;

  /// Read only at the close: the met-kana count gates the classical 余韻.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future; checking never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// word may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  final DateTime Function() _clock;
  final ItemReactionClock _reaction;
  final Random _rng;
  final List<KotenLine> _kotenPool;

  int _index = 0;
  List<String> _targetUnits = const [];
  List<String> _tiles = const [];
  List<bool> _used = const [];
  final List<int> _picked = [];
  bool _checked = false;
  bool _wasCorrect = false;
  int _correct = 0;
  bool _finished = false;
  bool _blindHeard = false;
  SpeechPlaybackResult? _lastPlay;
  KotenLine? _share;

  int get index => _index;
  int get total => items.length;
  Word get current => items[_index];
  bool get isLastItem => _index + 1 >= total;

  /// The word split into learning-unit tiles (きゃ stays one tile, っ/ー are
  /// their own tiles) — assembly works in the units the learner reads in.
  List<String> get targetUnits => _targetUnits;

  /// The shuffled board: the target's units plus [distractorCount] tiles
  /// from the word's own script.
  List<String> get tiles => _tiles;

  /// Whether tile [i] already sits in a slot.
  bool isTileUsed(int i) => _used[i];

  /// Tile indices in the order they were placed.
  List<int> get picked => List.unmodifiable(_picked);

  /// The current slot contents, `null` for a slot still to fill.
  String? slotUnit(int slot) =>
      slot < _picked.length ? _tiles[_picked[slot]] : null;

  bool get isChecked => _checked;
  bool get wasCorrect => _wasCorrect;
  int get correctCount => _correct;
  bool get isFinished => _finished;

  /// A play completed before the check — the current word is scored.
  bool get blindHeard => _blindHeard;

  /// The last playback outcome the view reported for this word, or `null`
  /// before any (a fresh word forgets the previous one).
  SpeechPlaybackResult? get lastPlay => _lastPlay;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? get share => _share;

  /// The view reports the outcome of one foreground play of [itemIndex].
  /// Only a [SpeechPlaybackResult.played] that began ([startedBlind]) and
  /// finished before the check is unprompted dictation evidence; a reveal
  /// replay only refreshes [lastPlay]. A completion for another word is
  /// stale and ignored — the view already drops cancelled generations.
  void notePlayback({
    required int itemIndex,
    required SpeechPlaybackResult result,
    required bool startedBlind,
  }) {
    if (_finished || itemIndex != _index) return;
    _lastPlay = result;
    if (result == SpeechPlaybackResult.played && startedBlind && !_checked) {
      _blindHeard = true;
    }
    notifyListeners();
  }

  /// Pause / hide / inactive. Invalidates the current word's RT only —
  /// hearing evidence already recorded stays, and only the next word
  /// re-arms timing. [lastPlay] becomes [SpeechPlaybackResult.interrupted]
  /// so the view can say why the sound stopped.
  void noteInterrupted() {
    if (_finished) return;
    // An already-shown assemble clock stays dead. Resume / replay
    // must not mint a fresh RT for this word.
    _reaction.invalidate();
    _lastPlay = SpeechPlaybackResult.interrupted;
    notifyListeners();
  }

  /// Places tile [i] in the next slot; a full board checks itself.
  void tapTile(int i) {
    if (_finished || _checked || _used[i]) return;
    _used[i] = true;
    _picked.add(i);
    if (_picked.length == _targetUnits.length) {
      _check();
      return;
    }
    notifyListeners();
  }

  /// Returns every placed tile to the board.
  void clear() {
    if (_finished || _checked || _picked.isEmpty) return;
    for (final i in _picked) {
      _used[i] = false;
    }
    _picked.clear();
    notifyListeners();
  }

  /// Leaves a checked word: the next board, or the close after the last.
  void next() {
    if (_finished || !_checked) return;
    if (isLastItem) {
      _share = KotenShare.pick(
        pool: _kotenPool,
        seenKanaCount: kana.seenCount,
        rng: _rng,
        season: Season.forMonth(_clock().month),
      );
      _finished = true;
    } else {
      _index++;
      _blindHeard = false;
      _lastPlay = null;
      _setup();
    }
    notifyListeners();
  }

  void _setup() {
    final chars = KanaTokenizer.tokenize(current.kana);
    // Distractor tiles come from the word's own script — cross-script tiles
    // would give the answer away by shape alone.
    final distractorPool = current.script == KanaScript.katakana
        ? kKatakanaGojuon
        : kHiraganaGojuon;
    final distractors =
        (distractorPool
                .map((k) => k.character)
                .where((c) => !chars.contains(c))
                .toList()
              ..shuffle(_rng))
            .take(distractorCount);
    _targetUnits = chars;
    _tiles = [...chars, ...distractors]..shuffle(_rng);
    _used = List<bool>.filled(_tiles.length, false);
    _picked.clear();
    _checked = false;
    _wasCorrect = false;
    _reaction.arm(startImmediately: true);
  }

  void _check() {
    final built = _picked.map((i) => _tiles[i]).join();
    final item = current;
    final correct = built == item.kana;
    final now = _clock();
    final heard = _blindHeard;
    final playback = heard
        ? SpeechPlaybackResult.played
        : (_lastPlay ?? SpeechPlaybackResult.interrupted);
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: item.kana,
        itemType: ItemType.word,
        mode: PracticeMode.dictation.name,
        correct: correct,
        rtMs: _reaction.elapsedMs(),
        sessionId: sessionId,
        meta: {
          'romaji': item.romaji,
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
      final id = item.progressId;
      if (!correct) {
        persistence.trackWord(words.recordAnswer(id, correct: false, at: now));
      } else if (DailyBridge.shouldRenew(id, alreadyTransferredIds)) {
        persistence.trackWord(words.recordAnswer(id, correct: true, at: now));
      }
    }
    if (correct) _correct++;
    _checked = true;
    _wasCorrect = correct;
    notifyListeners();
  }
}
