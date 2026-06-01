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

  /// Weakness score in roughly [0, 1+]; higher = weaker / more in need of
  /// review. Combines wrong-rate (primary), recency of mistakes, and — for this
  /// listening-strong learner whose accuracy saturates fast — a SLOWNESS term so
  /// "correct but slow" kana resurface: speed, not just correctness, is the
  /// reading-fluency goal.
  static double score(KanaStat stat, {required DateTime now}) {
    if (stat.seenCount == 0) return unseenBaseline;

    final double wrongRate = stat.wrongCount / stat.seenCount;

    // Recency only amplifies weakness when there are actual mistakes.
    double recency = 0;
    if (stat.wrongCount > 0 && stat.lastReviewedAt != null) {
      final int days = now
          .difference(stat.lastReviewedAt!)
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
