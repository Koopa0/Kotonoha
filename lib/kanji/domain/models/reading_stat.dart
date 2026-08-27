// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Per-reading practice stats — an UNTIMED Leitner schedule for the kanji track.
/// A deliberate separate type from `KanaStat` (the ADR forbids generalizing the
/// kana type), with one principled divergence decided 2026-06-03: the 漢字の声 UI
/// is untimed by design (retention-ruler — no clock), and kanji-reading mastery is
/// a near-binary RETRIEVAL signal, not a reaction-time reflex. So the timed RT/CVRT
/// graduation `KanaStat` carries is NOT mirrored here — it was retired rather than
/// kept dormant, because a dormant timed gate was the ONLY path to the furigana
/// fully fading, which silently froze 名残の仮名 at half-opacity.
///
/// Two thresholds, deliberately decoupled (2026-08-27): furigana fully fades at
/// [kFuriganaFadeLevel] (the 名残 promise — the support comes off on untimed
/// mastery alone), while the SCHEDULE keeps climbing to [kMaxLevel] (60 days) so
/// a mature reading drifts out to a bimonthly hello instead of returning every
/// week forever — with a growing kanji corpus, a 7-day ceiling would drown the
/// due queue. One [ReadingStat] per `reading:漢字#ヨミ`.
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
    // Legacy 'al'/'vl' (the retired timed RT/CVRT signal) are simply ignored if
    // present in an old kanji_stats_v1 blob — forward-compatible, no key bump.
    // Counts and level are clamped, not trusted: one corrupt entry must never
    // be able to crash the interval lookup on the next answer.
    int clampCount(Object? v) => ((v as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
    return ReadingStat(
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

  /// The level at which furigana fully fades ([RubyText.furiganaOpacity]) —
  /// reaching it by correct untimed recall means "the reading is known, the
  /// support comes off": the 名残 promise, completable without any timed beat.
  /// The schedule itself keeps climbing past it (see [kMaxLevel]).
  static const int kFuriganaFadeLevel = 3;

  /// The top of the interval table (60 days). Correct recalls climb one level
  /// each and hold here — maturity nearly retires a reading, it never locks it
  /// into a permanent weekly loop.
  static const int kMaxLevel = 6;

  ReadingStat recordAnswer({
    required bool correct,
    required DateTime at,
    double intervalScale = 1.0,
  }) {
    final int nextLevel = !correct
        ? 0
        : (srsLevel < kMaxLevel ? srsLevel + 1 : srsLevel);
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
