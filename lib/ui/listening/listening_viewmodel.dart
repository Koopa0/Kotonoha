// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/item_reaction_clock.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns one 聞き取り session: the cursor, reveal, what counts as heard, the
/// reaction clock, and every progress or analytics write. The screen plays
/// audio, reports completed plays and interrupts, renders, and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - Only a play that started *and* completed before reveal is unprompted
///   listening evidence ([blindHeard]); it alone can be graded and move SRS.
/// - A first completed play after reveal is prompted practice
///   ([promptedHeard]): logged as an unscored attempt, never a schedule write.
/// - An item with no completed play is skipped without any record.
/// - Unprompted correct climbs only the first time this 「もう一回」 grind
///   covers the id ([alreadyTransferredIds]); a miss always resets.
/// - Valid [Attempt.rtMs] starts on the first completed blind hear. An
///   interrupt ([noteInterrupted]) freezes the clock — resume or a same-item
///   replay must not restart it. 0 is untimed, not a fast reflex.
///
/// This type never interprets playback: the view decides what a completed
/// [SpeechPlaybackResult.played] is and whether it was cancelled, stale,
/// or backgrounded before calling [noteHeard]. Pure of timers and navigation.
class ListeningViewModel extends ChangeNotifier {
  ListeningViewModel({
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
       _rng = rng ?? Random();

  final List<ReadingItem> items;

  /// Owner of the 詞と句 schedule this session grades into.
  final WordProgressRepository words;

  /// Read only at the close: the met-kana count gates the classical 余韻.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future; grading never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// item may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  final DateTime Function() _clock;
  final ItemReactionClock _reaction;
  final Random _rng;
  final List<KotenLine> _kotenPool;

  int _index = 0;
  bool _revealed = false;
  bool _blindHeard = false;
  bool _promptedHeard = false;
  bool _finished = false;
  KotenLine? _share;

  int get index => _index;
  int get total => items.length;
  ReadingItem get current => items[_index];
  bool get isRevealed => _revealed;

  /// A play completed before reveal — the current item can be graded.
  bool get blindHeard => _blindHeard;

  /// The first completed play came after reveal — prompted, unscored.
  bool get promptedHeard => _promptedHeard;
  bool get isFinished => _finished;
  bool get isLastItem => _index + 1 >= total;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? get share => _share;

  /// The view reports one completed foreground play of [itemIndex].
  /// [startedBlind] is whether that play began before reveal; only a play
  /// that also finished before reveal is blind evidence, anything else is
  /// prompted. A completion for another item is stale and ignored — the
  /// view already drops cancelled generations before reporting.
  ///
  /// A blind hear is recorded even when the reaction clock is already
  /// invalid (background interrupt, then a successful replay); the clock
  /// itself only starts while still valid, so an interrupted item stays
  /// untimed rather than gaining a fabricated RT.
  void noteHeard({required int itemIndex, required bool startedBlind}) {
    if (_finished || itemIndex != _index) return;
    if (startedBlind && !_revealed) {
      _blindHeard = true;
      // First completed foreground hear. Already-invalid clocks stay
      // null — a later replay does not move the start.
      _reaction.start();
    } else {
      _promptedHeard = true;
    }
    notifyListeners();
  }

  /// Pause / hide / inactive. Invalidates the current item's RT only —
  /// hearing evidence already recorded stays, and only the next item
  /// re-arms timing.
  void noteInterrupted() {
    _reaction.invalidate();
  }

  void reveal() {
    if (_finished || _revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// Self-grades a blind hear after reveal. Ignored unless [blindHeard].
  void gradeBlind({required bool correct}) {
    if (_finished || !_revealed || !_blindHeard) return;
    _advance(recordMastery: true, correct: correct);
  }

  /// Moves past an item that was never heard. Nothing is recorded.
  void skipUnheard() {
    if (_finished || !_revealed || _blindHeard || _promptedHeard) return;
    _advance(recordMastery: false, correct: false);
  }

  /// Moves past a prompted item: logged as unscored practice, no SRS.
  void continuePrompted() {
    if (_finished || !_revealed || _blindHeard || !_promptedHeard) return;
    _advance(recordMastery: false, correct: false, prompted: true);
  }

  void _advance({
    required bool recordMastery,
    required bool correct,
    bool prompted = false,
  }) {
    final now = _clock();
    final item = current;
    if (recordMastery || prompted) {
      analytics.recordObserved(
        Attempt(
          ts: now.millisecondsSinceEpoch,
          itemId: item.displayText,
          itemType: ItemType.word,
          mode: PracticeMode.listening.name,
          correct: recordMastery && correct,
          rtMs: recordMastery ? _reaction.elapsedMs() : 0,
          sessionId: sessionId,
          meta: {
            'romaji': item.romaji,
            AttemptMeta.playback: SpeechPlaybackResult.played.name,
            AttemptMeta.heard: true,
            AttemptMeta.prompted: prompted,
            AttemptMeta.scored: recordMastery,
          },
        ),
      );
    }
    if (recordMastery) {
      final id = item.progressId;
      // A miss always resets. Unprompted correct climbs only the first
      // time this grind covers the id — wrap-around practice may repeat
      // the item but must not farm the schedule.
      if (!correct) {
        persistence.trackWord(words.recordAnswer(id, correct: false, at: now));
      } else if (DailyBridge.shouldRenew(id, alreadyTransferredIds)) {
        persistence.trackWord(words.recordAnswer(id, correct: true, at: now));
      }
    }
    if (isLastItem) {
      _share = KotenShare.pick(
        pool: _kotenPool,
        seenKanaCount: kana.seenCount,
        rng: _rng,
        season: Season.forMonth(now.month),
      );
      _finished = true;
    } else {
      _index++;
      _revealed = false;
      _blindHeard = false;
      _promptedHeard = false;
      _reaction.arm();
    }
    notifyListeners();
  }
}
