// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Coarse learning status for a single kana, used for the calm status dot.
///
/// This is a *display* classification. Weakness ranking for review uses the
/// continuous score in `services/weakness.dart`, not this enum.
enum KanaStatus { unseen, learning, weak, strong }

/// Per-kana practice statistics, persisted via shared_preferences.
///
/// Pure data: no `package:flutter/*` imports.
class KanaStat {
  const KanaStat({
    this.seenCount = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.lastReviewedAt,
    this.srsLevel = 0,
    this.dueAt,
  });

  factory KanaStat.fromJson(Map<String, dynamic> json) {
    final int? millis = (json['l'] as num?)?.toInt();
    final int? dueMillis = (json['d'] as num?)?.toInt();
    return KanaStat(
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

  /// Lightweight spaced-repetition level (0 = new/just-missed). Drives [dueAt].
  final int srsLevel;

  /// When this kana is next due for review (null until first answered).
  final DateTime? dueAt;

  bool get isSeen => seenCount > 0;

  /// Accuracy in [0, 1]; 0 when never seen.
  double get accuracy => seenCount == 0 ? 0 : correctCount / seenCount;

  /// Minutes until next review per SRS level (Leitner-ish). A wrong answer
  /// resets to level 0 (≈10 min); each correct answer steps up.
  static const List<int> _intervalsMinutes = [
    10, // 0
    60 * 24, // 1 day
    60 * 24 * 3, // 3 days
    60 * 24 * 7, // 1 week
    60 * 24 * 14, // 2 weeks
    60 * 24 * 30, // 1 month
    60 * 24 * 60, // 2 months
  ];

  /// Below this reaction time (ms), a correct answer is "fast" and graduates
  /// the SRS level without limit.
  static const int kFastThresholdMs = 800;

  /// Untimed or slow correct answers (handwriting/paper) can climb the SRS up
  /// to this level but no further — they earn a few days of spacing without
  /// graduating an item to long intervals on unproven reflex speed.
  static const int kUntimedCapLevel = 3;

  /// Returns a copy with one answer recorded, advancing the SRS schedule.
  /// [latencyMs] gates graduation (null/0/≥threshold = not fast); [intervalScale]
  /// shrinks the next interval (e.g. 0.5 for confusable kana).
  KanaStat recordAnswer({
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
        // Untimed/slow: climb toward the cap, then hold (never demote).
        nextLevel = srsLevel < kUntimedCapLevel ? srsLevel + 1 : srsLevel;
      }
    }
    final mins = (_intervalsMinutes[nextLevel] * intervalScale).round().clamp(
      1,
      1 << 30,
    );
    return KanaStat(
      seenCount: seenCount + 1,
      correctCount: correctCount + (correct ? 1 : 0),
      wrongCount: wrongCount + (correct ? 0 : 1),
      lastReviewedAt: at,
      srsLevel: nextLevel,
      dueAt: at.add(Duration(minutes: mins)),
    );
  }

  /// Display classification used for the status dot in the UI.
  KanaStatus get status {
    if (seenCount == 0) return KanaStatus.unseen;
    if (seenCount < 3) return KanaStatus.learning;
    if (accuracy >= 0.8) return KanaStatus.strong;
    if (accuracy < 0.6 || wrongCount >= 3) return KanaStatus.weak;
    return KanaStatus.learning;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    's': seenCount,
    'c': correctCount,
    'w': wrongCount,
    if (lastReviewedAt != null) 'l': lastReviewedAt!.millisecondsSinceEpoch,
    // New fields are omitted at defaults so old kana_stats_v1 stays valid.
    if (srsLevel != 0) 'sl': srsLevel,
    if (dueAt != null) 'd': dueAt!.millisecondsSinceEpoch,
  };

  @override
  String toString() =>
      'KanaStat(seen:$seenCount correct:$correctCount wrong:$wrongCount)';
}
