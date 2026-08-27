// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Per-item practice stats for the 詞と句 track — an UNTIMED Leitner schedule,
/// one [WordStat] per reading item (a `word:…` or `phrase:…` progress id).
///
/// A deliberate separate type (the ADR forbids generalizing `KanaStat` /
/// `ReadingStat`; this is the third copy, not an abstraction), with two
/// principled divergences from the kanji `ReadingStat`:
///  - reading a word or sentence is a RETRIEVAL signal like a kanji reading,
///    so the schedule is untimed and binary — but nothing here is tied to a
///    furigana-fade promise, so correct recalls climb the FULL interval table
///    to [kMaxLevel] (60 days). A mature item drifts out to a bimonthly hello
///    instead of returning every week forever — with hundreds of items, a
///    7-day ceiling would drown the due queue and starve new material.
///  - `fromJson` clamps instead of trusting: a corrupt level or negative count
///    normalises to a sane value, so one bad persisted entry can never crash
///    the interval lookup later.
///
/// Pure data: no `package:flutter/*` imports.
class WordStat {
  const WordStat({
    this.seenCount = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.lastReviewedAt,
    this.srsLevel = 0,
    this.dueAt,
  });

  factory WordStat.fromJson(Map<String, dynamic> json) {
    final int? millis = (json['l'] as num?)?.toInt();
    final int? dueMillis = (json['d'] as num?)?.toInt();
    int clampCount(Object? v) => ((v as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
    return WordStat(
      seenCount: clampCount(json['s']),
      correctCount: clampCount(json['c']),
      wrongCount: clampCount(json['w']),
      lastReviewedAt: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis),
      srsLevel: ((json['sl'] as num?)?.toInt() ?? 0).clamp(0, kMaxLevel),
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

  /// Test-only convenience (mirrors the other stat types). Accuracy is NEVER
  /// shown in the UI — no visible score is a product non-negotiable.
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

  /// The top of the interval table (60 days). Correct answers climb one level
  /// each and hold here — maturity means the item nearly retires, it never
  /// means a permanent weekly loop.
  static const int kMaxLevel = 6;

  WordStat recordAnswer({required bool correct, required DateTime at}) {
    final int nextLevel = !correct
        ? 0
        : (srsLevel < kMaxLevel ? srsLevel + 1 : srsLevel);
    return WordStat(
      seenCount: seenCount + 1,
      correctCount: correctCount + (correct ? 1 : 0),
      wrongCount: wrongCount + (correct ? 0 : 1),
      lastReviewedAt: at,
      srsLevel: nextLevel,
      dueAt: at.add(Duration(minutes: _intervalsMinutes[nextLevel])),
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
