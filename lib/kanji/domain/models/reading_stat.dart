// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

/// Per-reading practice stats — a deliberate copy of `KanaStat`'s RT+CVRT-gated
/// Leitner schedule (the ADR forbids generalizing the kana type, so the kanji
/// module owns its own well-understood ~copy). One [ReadingStat] per
/// `reading:漢字#ヨミ`.
///
/// Pure data: no `package:flutter/*` imports.
class ReadingStat {
  const ReadingStat({
    this.seenCount = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.lastReviewedAt,
    this.srsLevel = 0,
    this.dueAt,
    this.avgLatencyMs = 0,
    this.varLatencyMs2 = 0,
  });

  factory ReadingStat.fromJson(Map<String, dynamic> json) {
    final int? millis = (json['l'] as num?)?.toInt();
    final int? dueMillis = (json['d'] as num?)?.toInt();
    return ReadingStat(
      seenCount: (json['s'] as num?)?.toInt() ?? 0,
      correctCount: (json['c'] as num?)?.toInt() ?? 0,
      wrongCount: (json['w'] as num?)?.toInt() ?? 0,
      lastReviewedAt: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis),
      srsLevel: (json['sl'] as num?)?.toInt() ?? 0,
      dueAt: dueMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dueMillis),
      avgLatencyMs: (json['al'] as num?)?.toInt() ?? 0,
      varLatencyMs2: (json['vl'] as num?)?.toInt() ?? 0,
    );
  }

  final int seenCount;
  final int correctCount;
  final int wrongCount;
  final DateTime? lastReviewedAt;
  final int srsLevel;
  final DateTime? dueAt;

  /// EMA of *timed* reaction time (ms); 0 = no timed recall yet. Only the timed
  /// recall beats (choose/assemble the reading) feed it — self-graded reveals
  /// leave it untouched, so it stays a clean reading-speed signal.
  final int avgLatencyMs;

  /// Exponentially-weighted moving variance of *timed* RT (ms²). With
  /// [avgLatencyMs] it gives CVRT (stddev/mean), the automaticity index.
  final int varLatencyMs2;

  bool get isSeen => seenCount > 0;
  double get accuracy => seenCount == 0 ? 0 : correctCount / seenCount;

  /// Coefficient of variation of timed RT (stddev/mean); infinity until timed.
  /// Lower = steadier = more automatic — the consistent-fast graduation gate.
  double get cvLatency => avgLatencyMs <= 0
      ? double.infinity
      : math.sqrt(varLatencyMs2) / avgLatencyMs;

  static const List<int> _intervalsMinutes = [
    10,
    60 * 24,
    60 * 24 * 3,
    60 * 24 * 7,
    60 * 24 * 14,
    60 * 24 * 30,
    60 * 24 * 60,
  ];

  /// Below this reaction time (ms) a correct answer is "fast" and graduates the
  /// level. The timed recall beats (choose/assemble the reading) feed it; the
  /// self-graded reveal stays untimed (latencyMs null) and only climbs to the cap.
  static const int kFastThresholdMs = 800;

  /// Untimed/slow correct answers climb only to this level, then hold.
  static const int kUntimedCapLevel = 3;

  /// Past [kUntimedCapLevel], a fast answer graduates to the longer intervals
  /// only when reaction time is also CONSISTENT — CVRT (stddev/mean) at or below
  /// this. A fast-once-slow-next reader holds at the cap (never demotes).
  static const double kMaxGraduationCv = 0.30;

  ReadingStat recordAnswer({
    required bool correct,
    required DateTime at,
    int? latencyMs,
    double intervalScale = 1.0,
  }) {
    // EWMA the reaction time AND its variance, but only on real timed recall —
    // untimed self-grades (the reveal) leave both signals untouched (mirrors
    // KanaStat: same 0.7/0.3 weights, deviation from the pre-update mean).
    final int nextAvgLatency;
    final int nextVarLatency2;
    if (latencyMs != null && latencyMs > 0) {
      if (avgLatencyMs == 0) {
        nextAvgLatency = latencyMs; // first timed recall: seed the mean
        nextVarLatency2 = 0; // a single point has no observed spread
      } else {
        final int dev = latencyMs - avgLatencyMs; // vs the pre-update mean
        nextVarLatency2 = (0.7 * varLatencyMs2 + 0.3 * (dev * dev)).round();
        nextAvgLatency = (0.7 * avgLatencyMs + 0.3 * latencyMs).round();
      }
    } else {
      nextAvgLatency = avgLatencyMs;
      nextVarLatency2 = varLatencyMs2;
    }

    final int nextLevel;
    if (!correct) {
      nextLevel = 0;
    } else {
      final fast =
          latencyMs != null && latencyMs > 0 && latencyMs < kFastThresholdMs;
      if (fast) {
        // Below the cap, CV is statistically meaningless (too few samples);
        // graduate on speed alone. At/above the cap, only graduate to the long
        // intervals when reaction time is also consistent (never demotes).
        final double cv = nextAvgLatency <= 0
            ? double.infinity
            : math.sqrt(nextVarLatency2) / nextAvgLatency;
        final consistentEnough =
            srsLevel < kUntimedCapLevel || cv <= kMaxGraduationCv;
        nextLevel = consistentEnough
            ? (srsLevel + 1).clamp(0, _intervalsMinutes.length - 1)
            : srsLevel;
      } else {
        nextLevel = srsLevel < kUntimedCapLevel ? srsLevel + 1 : srsLevel;
      }
    }
    final mins = (_intervalsMinutes[nextLevel] * intervalScale).round().clamp(
      1,
      1 << 30,
    );
    return ReadingStat(
      seenCount: seenCount + 1,
      correctCount: correctCount + (correct ? 1 : 0),
      wrongCount: wrongCount + (correct ? 0 : 1),
      lastReviewedAt: at,
      srsLevel: nextLevel,
      dueAt: at.add(Duration(minutes: mins)),
      avgLatencyMs: nextAvgLatency,
      varLatencyMs2: nextVarLatency2,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    's': seenCount,
    'c': correctCount,
    'w': wrongCount,
    if (lastReviewedAt != null) 'l': lastReviewedAt!.millisecondsSinceEpoch,
    if (srsLevel != 0) 'sl': srsLevel,
    if (dueAt != null) 'd': dueAt!.millisecondsSinceEpoch,
    // Omitted at defaults so old kanji_stats_v1 stays valid.
    if (avgLatencyMs != 0) 'al': avgLatencyMs,
    if (varLatencyMs2 != 0) 'vl': varLatencyMs2,
  };
}
