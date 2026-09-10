// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// Lightweight kana weakness scoring + ranking. **Not** a spaced-repetition
/// system — just a transparent score so review can bias toward weak kana.
///
/// Pure logic: no `package:flutter/*` imports.
class Weakness {
  const Weakness._();

  /// Baseline score for kana that have never been seen, so a cold-start weak
  /// review still has something to show (least-seen first). Kept below a kana
  /// that has been clearly answered wrong, but above a well-known kana.
  static const double unseenBaseline = 0.45;

  /// Reaction time (ms) above which a *correct* answer still counts as slow —
  /// not yet automatic. Mirrors [KanaStat.kFastThresholdMs].
  static const int slowThresholdMs = 800;

  /// Reaction time (ms) at which slowness saturates the term.
  static const int slowCeilingMs = 2000;

  /// A dated miss this old or newer still claims a weak review slot.
  /// Older misses are history, not a current fluency problem.
  static const int recentMistakeDays = 14;

  /// With enough samples, accuracy at or above this plus a fast (or untimed)
  /// reading is treated as recovered — a vanishing 1/N historical miss must
  /// not lock the daily weak quota. Still overridden by a recent dated miss
  /// or a slow average.
  static const double recoveredAccuracy = 0.95;

  /// Samples needed before [recoveredAccuracy] can retire a historical miss.
  /// Fewer observations stay in the learning band even at a high fraction.
  static const int recoveredMinSeen = 10;

  /// Weakness score in roughly [0, 1+]; higher = weaker / more in need of
  /// review. Combines wrong-rate (primary), recency of mistakes, and — for this
  /// listening-strong learner whose accuracy saturates fast — a SLOWNESS term so
  /// "correct but slow" kana resurface: speed, not just correctness, is the
  /// reading-fluency goal.
  static double score(KanaStat stat, {required DateTime now}) {
    if (stat.seenCount == 0) return unseenBaseline;

    final double wrongRate = stat.wrongCount / stat.seenCount;

    // Recency only amplifies weakness when a real mistake timestamp exists.
    // lastReviewedAt also moves on a correct answer, so it must not stand in
    // for "when did they last get this wrong". Legacy saves with wrongCount
    // but no lastMistakeAt keep recency at 0 — we do not invent that history.
    double recency = 0;
    if (stat.wrongCount > 0 && stat.lastMistakeAt != null) {
      final int days = now
          .difference(stat.lastMistakeAt!)
          .inDays
          .clamp(0, 1000);
      recency = 1 / (1 + days); // 1.0 today, 0.5 yesterday, → 0 over time.
    }

    // 0 at/below the fast threshold, ramping to 1 at the ceiling. Only timed
    // readings contribute (avgLatencyMs stays 0 for untimed practice).
    double slowness = 0;
    if (stat.avgLatencyMs > slowThresholdMs) {
      slowness =
          ((stat.avgLatencyMs - slowThresholdMs) /
                  (slowCeilingMs - slowThresholdMs))
              .clamp(0.0, 1.0);
    }

    return 0.7 * wrongRate + 0.3 * recency + 0.2 * slowness;
  }

  /// Whether [stat] should occupy a daily *weak* slot — not merely
  /// `score > 0`. A recovered, recently-correct, not-due kana with a
  /// vanishing historical miss (legacy `wrongCount` or a year-old
  /// [KanaStat.lastMistakeAt]) would otherwise lock the quota forever,
  /// because `wrongCount / seenCount` never returns to zero.
  ///
  /// Keeps: slow readings, dated recent misses, and a still-material
  /// error rate while the item is still learning. Score itself is
  /// unchanged so ranking among real weaks stays the same.
  static bool isActionable(KanaStat stat, {required DateTime now}) {
    if (!stat.isSeen) return false;
    if (stat.avgLatencyMs > slowThresholdMs) return true;
    if (_hasRecentMistake(stat, now)) return true;
    if (stat.seenCount >= recoveredMinSeen &&
        stat.accuracy >= recoveredAccuracy) {
      return false;
    }
    return score(stat, now: now) > 0;
  }

  static bool _hasRecentMistake(KanaStat stat, DateTime now) {
    if (stat.wrongCount <= 0 || stat.lastMistakeAt == null) return false;
    final int days = now.difference(stat.lastMistakeAt!).inDays;
    return !days.isNegative && days <= recentMistakeDays;
  }

  /// Ranks [kana] from weakest to strongest. Ties break by wrong count, then
  /// by the original (gojūon) order, so the result is deterministic.
  static List<Kana> rankByWeakness(
    List<Kana> kana,
    Map<String, KanaStat> stats, {
    required DateTime now,
  }) {
    const empty = KanaStat();
    final indexed = List<MapEntry<int, Kana>>.generate(
      kana.length,
      (i) => MapEntry(i, kana[i]),
    );
    indexed.sort((a, b) {
      final sa = stats[a.value.id] ?? empty;
      final sb = stats[b.value.id] ?? empty;
      final cmp = score(sb, now: now).compareTo(score(sa, now: now));
      if (cmp != 0) return cmp;
      final wrongCmp = sb.wrongCount.compareTo(sa.wrongCount);
      if (wrongCmp != 0) return wrongCmp;
      return a.key.compareTo(b.key); // stable: original order
    });
    return indexed.map((e) => e.value).toList();
  }

  /// The top [count] weakest kana (default 10), weakest first.
  static List<Kana> weakest(
    List<Kana> kana,
    Map<String, KanaStat> stats, {
    required DateTime now,
    int count = 10,
  }) {
    final ranked = rankByWeakness(kana, stats, now: now);
    return ranked.take(count.clamp(0, ranked.length)).toList();
  }
}
