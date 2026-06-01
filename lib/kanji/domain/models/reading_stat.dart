// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Per-reading practice stats — a deliberate copy of `KanaStat`'s RT-gated
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
    );
  }

  final int seenCount;
  final int correctCount;
  final int wrongCount;
  final DateTime? lastReviewedAt;
  final int srsLevel;
  final DateTime? dueAt;

  bool get isSeen => seenCount > 0;
  double get accuracy => seenCount == 0 ? 0 : correctCount / seenCount;

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
  /// level without limit. Kanji reading is self-graded (untimed), so this rarely
  /// fires — kept for parity and a possible future timed mode.
  static const int kFastThresholdMs = 800;

  /// Untimed/slow correct answers climb only to this level, then hold.
  static const int kUntimedCapLevel = 3;

  ReadingStat recordAnswer({
    required bool correct,
    required DateTime at,
    int? latencyMs,
    double intervalScale = 1.0,
  }) {
    final int nextLevel;
    if (!correct) {
      nextLevel = 0;
    } else {
      final fast =
          latencyMs != null && latencyMs > 0 && latencyMs < kFastThresholdMs;
      if (fast) {
        nextLevel = (srsLevel + 1).clamp(0, _intervalsMinutes.length - 1);
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
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    's': seenCount,
    'c': correctCount,
    'w': wrongCount,
    if (lastReviewedAt != null) 'l': lastReviewedAt!.millisecondsSinceEpoch,
    if (srsLevel != 0) 'sl': srsLevel,
    if (dueAt != null) 'd': dueAt!.millisecondsSinceEpoch,
  };
}
