// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/use_cases/furigana_support.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns one kanji sentence-reading session: the cursor, the reveal and its
/// unprompted commit, whether that commit was an independent recall, the
/// self-grade, and every progress or analytics write. The screen speaks,
/// renders the ruby, and navigates.
///
/// TWO schedules meet here and stay separate: the per-READING kanji SRS is
/// driven by 漢字の声 — this type only *reads* it ([srsLevelOf]) to fade
/// furigana and to judge reading support — while the per-SENTENCE schedule
/// is its own, a cold self-graded read recorded against
/// [WordProgressRepository]. So re-reading a sentence never inflates a kanji
/// reading's mastery, and mastering a reading never marks a sentence
/// reviewed.
///
/// Evidence contract (the same one the widget state used to hold):
/// - The commit button is only half the evidence: furigana still visible on
///   the card is reading support, even if the learner pressed 「讀得出來」.
///   Only an unprompted commit with every reading faded is independent.
/// - Independent confirmed-correct is the only climb, and only the first
///   time this 「もう一回」 grind covers the id ([alreadyTransferredIds]).
///   Supported correct on a new sentence keeps intake (seen) without
///   mastering; on a seen one it writes nothing. A miss always resets.
/// - Every grade is logged as a kanji-typed reading [Attempt] whose
///   `prompted` flag is the inverse of independence.
///
/// Playback is not interpreted here: hearing the sentence after reveal is a
/// comfort, not evidence, so the view owns the speaker. Pure of timers and
/// navigation.
class KanjiSentenceViewModel extends ChangeNotifier {
  KanjiSentenceViewModel({
    required this.phrases,
    required this.words,
    required this.kanji,
    required this.persistence,
    required this.analytics,
    this.sessionId = '',
    this.alreadyTransferredIds = const {},
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<KanjiPhrase> phrases;

  /// Owner of the per-sentence schedule this session grades into.
  final WordProgressRepository words;

  /// Read only: the per-reading maturity that fades furigana. Never written
  /// here — that schedule belongs to 漢字の声.
  final KanjiReadingRepository kanji;

  /// App-scoped owner of every write's future; grading never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// sentence may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  final DateTime Function() _clock;

  int _index = 0;
  bool _revealed = false;
  bool _unpromptedCommit = false;
  int _correct = 0;
  bool _finished = false;

  int get index => _index;
  int get total => phrases.length;
  KanjiPhrase get current => phrases[_index];
  bool get isLastItem => _index + 1 >= total;
  bool get isRevealed => _revealed;

  /// Whether the reveal was committed as 「讀得出來」 rather than after a hint.
  bool get unpromptedCommit => _unpromptedCommit;
  int get correctCount => _correct;
  bool get isFinished => _finished;

  /// The per-reading maturity of [unitId] — what the ruby fades on.
  int srsLevelOf(String unitId) => kanji.statForUnit(unitId).srsLevel;

  /// Whether the current sentence still shows furigana on any kanji run.
  bool get hasVisibleReadingSupport =>
      FuriganaSupport.hasVisibleReadingSupport(current, srsLevelOf);

  /// Shows the full reading, meaning and sound. [unpromptedCommit] is the
  /// learner's claim; independence is judged at grade time against the ruby.
  void reveal({required bool unpromptedCommit}) {
    if (_finished || _revealed) return;
    _revealed = true;
    _unpromptedCommit = unpromptedCommit;
    notifyListeners();
  }

  /// Self-grades the revealed sentence and moves on. Ignored before reveal.
  void grade({required bool correct}) {
    if (_finished || !_revealed) return;
    final now = _clock();
    final item = current;
    final independent = _unpromptedCommit && !hasVisibleReadingSupport;
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: item.written,
        itemType: ItemType.kanji,
        mode: PracticeMode.reading.name,
        correct: correct,
        sessionId: sessionId,
        meta: {'reading': item.reading, AttemptMeta.prompted: !independent},
      ),
    );
    // The sentence's own schedule — a cold self-graded read. (The per-reading
    // kanji SRS belongs to 漢字の声 and is deliberately untouched here.)
    // Independent confirmed-correct is the only climb, and only the first
    // time this grind covers the id. Supported correct on a new item keeps
    // intake (seen) without mastering. A miss always resets.
    final id = item.progressId;
    final canRenew = DailyBridge.shouldRenew(id, alreadyTransferredIds);
    if (!correct) {
      persistence.trackWord(words.recordAnswer(id, correct: false, at: now));
    } else if (independent && canRenew) {
      persistence.trackWord(words.recordAnswer(id, correct: true, at: now));
    } else if (!independent && !words.statForItem(id).isSeen) {
      persistence.trackWord(words.markIntroduced(id, at: now));
    }
    if (correct) _correct++;
    if (isLastItem) {
      _finished = true;
    } else {
      _index++;
      _revealed = false;
      _unpromptedCommit = false;
    }
    notifyListeners();
  }
}
