// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns one 黙読 session: the cursor, the reveal and its unprompted commit,
/// the self-grade, and every progress or analytics write that follows from
/// it. The screen renders this state, forwards taps, speaks, and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - Unprompted confirmed-correct is the only climb, and only the first time
///   this 「もう一回」 grind covers the id ([alreadyTransferredIds]).
/// - Prompted correct on a new item keeps intake
///   ([WordProgressRepository.markIntroduced]) without mastering; on a seen
///   item it writes nothing.
/// - A miss always resets.
/// - Every grade is logged as a word-level reading [Attempt]; per-kana SRS is
///   never touched — reading fluency is a different signal from single-kana
///   recognition.
///
/// Playback is not interpreted here: hearing the line after reveal is a
/// comfort, not evidence, so the view owns the speaker and its lifecycle.
/// Pure of timers and navigation.
class ReadingViewModel extends ChangeNotifier {
  ReadingViewModel({
    required this.items,
    required this.words,
    required this.kana,
    required this.persistence,
    required this.analytics,
    this.sessionId = '',
    this.alreadyTransferredIds = const {},
    DateTime Function()? clock,
    Random? rng,
    this._kotenPool = kKoten,
  }) : _clock = clock ?? DateTime.now,
       _rng = rng ?? Random();

  final List<ReadingItem> items;

  /// Owner of the 詞と句 schedule this session grades into.
  final WordProgressRepository words;

  /// Read only at the close: the met-kana count gates the classical 余韻.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future; answering never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// item may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  final DateTime Function() _clock;
  final Random _rng;
  final List<KotenLine> _kotenPool;

  int _index = 0;
  bool _revealed = false;
  bool _unpromptedCommit = false;
  int _correct = 0;
  bool _finished = false;
  KotenLine? _share;

  int get index => _index;
  int get total => items.length;
  ReadingItem get current => items[_index];
  bool get isRevealed => _revealed;

  /// Whether the learner committed to a reading before seeing it. Decides
  /// which confirm label the view shows and whether a correct can climb.
  bool get unpromptedCommit => _unpromptedCommit;
  int get correctCount => _correct;
  bool get isFinished => _finished;
  bool get isLastItem => _index + 1 >= total;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? get share => _share;

  /// Shows the reading and meaning. [unpromptedCommit] is true only when the
  /// learner claimed to have read the line before it was revealed.
  void reveal({required bool unpromptedCommit}) {
    if (_finished || _revealed) return;
    _revealed = true;
    _unpromptedCommit = unpromptedCommit;
    notifyListeners();
  }

  /// Self-grades the revealed item, writes the evidence, and moves on (or
  /// closes the session on the last item). Ignored before reveal.
  void grade({required bool correct}) {
    if (_finished || !_revealed) return;
    final now = _clock();
    final unprompted = _unpromptedCommit;
    final item = current;
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: item.displayText,
        itemType: ItemType.word,
        mode: PracticeMode.reading.name,
        correct: correct,
        sessionId: sessionId,
        meta: {'romaji': item.romaji, AttemptMeta.prompted: !unprompted},
      ),
    );
    final id = item.progressId;
    final canRenew = DailyBridge.shouldRenew(id, alreadyTransferredIds);
    // Unprompted confirmed-correct is the only climb, and only the first
    // time this grind covers the id. Prompted correct on a new item keeps
    // intake (seen) without mastering. A miss always resets.
    if (!correct) {
      persistence.trackWord(words.recordAnswer(id, correct: false, at: now));
    } else if (unprompted && canRenew) {
      persistence.trackWord(words.recordAnswer(id, correct: true, at: now));
    } else if (!unprompted && !words.statForItem(id).isSeen) {
      persistence.trackWord(words.markIntroduced(id, at: now));
    }
    if (correct) _correct++;
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
      _unpromptedCommit = false;
    }
    notifyListeners();
  }
}
