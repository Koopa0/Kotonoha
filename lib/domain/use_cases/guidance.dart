// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';

/// Where the ambient "next step" line takes the learner when tapped.
enum GuidanceTarget {
  lessons,
  daily,

  /// Meet new words ear-first (渡し舟).
  ferry,

  /// Review due words cold (文字起こし).
  dictation,

  /// Read kana sentences — due ones first (黙読).
  sentences,

  /// Read mixed-script sentences, the grammar-pattern spine (名残の仮名).
  kanjiSentences,

  /// Kanji readings — due reviews or new teach beats (漢字の声).
  kanji,
  rest,
}

/// A track's standing in the schedule, as plain data — the caller (the View,
/// which holds the repositories) summarises each track into one of these so
/// this use_case never has to import the kanji module or walk stat maps.
class TrackDue {
  const TrackDue({
    this.dueCount = 0,
    this.oldestDue,
    this.unmet = 0,
    this.lastMet,
  });

  static const TrackDue none = TrackDue();

  /// Items due for review now.
  final int dueCount;

  /// The earliest due instant among them (null when [dueCount] is 0).
  final DateTime? oldestDue;

  /// Readable items never met yet.
  final int unmet;

  /// When this track was last touched at all — the most recent review instant
  /// across its met items, or null if nothing in it has ever been met. It is
  /// how long a track has gone NEGLECTED, which is what decides who gets the
  /// next introduction (never a count, never shown).
  final DateTime? lastMet;

  /// Summarises one reading track from the items the learner can actually read
  /// and the stats its sessions schedule by. Lives here, not in the View, so
  /// the guidance rules and the thing that feeds them are tested together.
  static TrackDue fromItems(
    List<ReadingItem> readable,
    Map<String, WordStat> stats,
    DateTime now,
  ) {
    var dueCount = 0;
    var unmet = 0;
    DateTime? oldestDue;
    DateTime? lastMet;
    for (final item in readable) {
      final s = stats[item.progressId] ?? const WordStat();
      if (!s.isSeen) {
        unmet++;
        continue;
      }
      final seenAt = s.lastReviewedAt;
      if (seenAt != null && (lastMet == null || seenAt.isAfter(lastMet))) {
        lastMet = seenAt;
      }
      final d = s.dueAt;
      if (d != null && !d.isAfter(now)) {
        dueCount++;
        if (oldestDue == null || d.isBefore(oldestDue)) oldestDue = d;
      }
    }
    return TrackDue(
      dueCount: dueCount,
      oldestDue: oldestDue,
      unmet: unmet,
      lastMet: lastMet,
    );
  }
}

/// One calm "do this next" decision, derived from learning state.
///
/// A pure value object: it carries only the navigation [target] and — for the
/// review states — the [dueCount] the View needs to fill in its sentence. The
/// 繁中 copy itself lives in `AppStrings` (the UI layer), so this stays
/// Flutter-free.
class GuidanceStep {
  const GuidanceStep(this.target, {this.dueCount = 0});

  final GuidanceTarget target;

  /// Items due for review; only meaningful for the review targets ([daily] /
  /// [dictation] / [sentences] / [kanji]-review — 0 otherwise).
  final int dueCount;

  @override
  bool operator ==(Object other) =>
      other is GuidanceStep &&
      other.target == target &&
      other.dueCount == dueCount;

  @override
  int get hashCode => Object.hash(target, dueCount);
}

/// Reads learning state and answers one question: what should the learner do
/// next? One quiet step at a time — never a map or a checklist. Pure logic,
/// deterministic under an injected [now].
abstract final class Guidance {
  /// One session's worth of reviews. At or above it the day is spent revising;
  /// below it there is room for new material. The same intake valve the
  /// session composers apply inside a room, applied one level up — between
  /// rooms — because the words track meets and reviews in two different ones.
  static const int kReviewFirstBacklog = 8;

  /// First-match-wins over three eras:
  ///
  /// **The kana era** (unchanged — the foundation always speaks first):
  /// - **A** nothing learned yet → start the lessons (手解き).
  /// - **B** kana reviews are due → today's session (今日の稽古), with count.
  /// - **C** caught up but rows remain → keep learning (手解き).
  ///
  /// **The reading era** (the kana are quiet — route into the corpus). Its
  /// branches all answer the same question, "who has waited longest?", so no
  /// track can be starved by another's bigger pool:
  /// - **D0** a track never opened at all → open it. Once each, ahead of
  ///   reviews: an unopened room is not novelty competing with revision, it is
  ///   a whole part of the app the learner cannot see exists.
  /// - **D** something is due somewhere → the track whose oldest due item has
  ///   waited longest. Words review in 文字起こし, kana sentences in 黙読,
  ///   mixed-script sentences in 名残の仮名, readings in 漢字の声.
  /// - **E** nothing due but unmet material remains → the track NEGLECTED
  ///   longest gets the introduction (oldest [TrackDue.lastMet]; a track never
  ///   touched at all wins outright). A fixed curriculum order here would have
  ///   pointed at 渡し舟 for months — the word pool is the largest, so a
  ///   first-match chain silently hides every other track until it empties.
  ///
  /// - **F** everything met and nothing due → rest; the day is theirs.
  ///
  /// Ties in either branch fall back to declaration order (words → kana
  /// sentences → mixed sentences → kanji), which only matters on a cold start
  /// where every track is equally untouched.
  ///
  /// "Due" for kana reuses [StudySet.reviewPool] + [Scheduler] so it never
  /// diverges from what 今日の稽古 itself draws on; each reading track's
  /// standing arrives as a [TrackDue] summary computed by the caller from the
  /// same repositories its sessions draw on.
  static GuidanceStep nextStep(
    KanaProgressRepository store, {
    required DateTime now,
    TrackDue words = TrackDue.none,
    TrackDue sentences = TrackDue.none,
    TrackDue kanjiSentences = TrackDue.none,
    TrackDue kanji = TrackDue.none,
  }) {
    // A — a brand-new learner: send them to be taught, before anything is due.
    if (store.learnedUnitCount == 0) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // B — kana reviews take priority over everything else.
    final due = Scheduler.dueCount(
      StudySet.reviewPool(store),
      store.stats,
      now: now,
    );
    if (due > 0) {
      return GuidanceStep(GuidanceTarget.daily, dueCount: due);
    }
    // C — caught up, but there is still a row left to learn.
    final hasUnlearned = Lessons.fromKana(store.allKana)
        .any((l) => !store.isUnitLearned(l.id));
    if (hasUnlearned) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // The reading era. Declaration order is the tie-break for both branches.
    final tracks = [
      (review: GuidanceTarget.dictation, meet: GuidanceTarget.ferry, t: words),
      (
        review: GuidanceTarget.sentences,
        meet: GuidanceTarget.sentences,
        t: sentences,
      ),
      (
        review: GuidanceTarget.kanjiSentences,
        meet: GuidanceTarget.kanjiSentences,
        t: kanjiSentences,
      ),
      (review: GuidanceTarget.kanji, meet: GuidanceTarget.kanji, t: kanji),
    ];

    // D0 — a track the learner has NEVER opened gets opened first, ahead of
    // any review. Opening a room is a one-off event per track, not recurring
    // novelty, so it cannot crowd reviews out; leaving it behind them can and
    // did — reviews of an already-started track regenerate every day, so a
    // review-first rule alone hid the newest track for ~86 simulated days
    // (see guidance_fairness_simulation_test).
    final unopened = tracks.where((c) => c.t.unmet > 0 && c.t.lastMet == null);
    if (unopened.isNotEmpty) {
      return GuidanceStep(unopened.first.meet);
    }

    final overdue =
        tracks.where((c) => c.t.dueCount > 0 && c.t.oldestDue != null).toList()
          ..sort((a, b) => a.t.oldestDue!.compareTo(b.t.oldestDue!));
    final backlog = tracks.fold<int>(0, (n, c) => n + c.t.dueCount);

    GuidanceStep review() =>
        GuidanceStep(overdue.first.review, dueCount: overdue.first.t.dueCount);

    // D — the review backlog already fills a whole session: revise, longest
    // overdue first. Below that threshold the day has slack, and spending it
    // on new material costs nothing (what stays due is picked up tomorrow).
    if (backlog >= kReviewFirstBacklog) return review();

    // E — there is slack: the track neglected longest gets new material. This
    // has to outrank a small backlog, because for words the meeting beat and
    // the reviewing beat are different rooms (渡し舟 / 文字起こし) — a strict
    // review-first rule pointed at 文字起こし almost every day and the learner
    // met three new words in half a year (guidance_fairness_simulation_test).
    final unmet = tracks.where((c) => c.t.unmet > 0).toList();
    if (unmet.isNotEmpty) {
      unmet.sort((a, b) {
        final x = a.t.lastMet;
        final y = b.t.lastMet;
        if (x == null && y == null) return 0;
        if (x == null) return -1;
        if (y == null) return 1;
        return x.compareTo(y);
      });
      return GuidanceStep(unmet.first.meet);
    }

    // Nothing new anywhere, but a few items are still due.
    if (overdue.isNotEmpty) return review();

    // F — everything met, nothing pending: the day is theirs.
    return const GuidanceStep(GuidanceTarget.rest);
  }
}
