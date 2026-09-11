// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

/// Coarse learning status for a single kana, used for the calm status dot.
///
/// This is a *display* classification. Weakness ranking for review uses the
/// continuous score in `services/weakness.dart`, not this enum.
enum KanaStatus { unseen, learning, weak, strong }

/// Per-kana practice statistics, persisted via shared_preferences.
///
/// Visual / shared counts ([seenCount], [correctCount], [avgLatencyMs]) are
/// recognition evidence. Listening is a separate optional contract used by
/// daily direction selection (#50) and by any later diagnostic (#49):
///
/// * Absent listen fields decode as unknown and stay unknown.
/// * Visual totals are never migrated into listening mastery.
/// * Only a scored sound-to-kana trial with valid audio may write listen
///   fields (`recordAnswer(listening: true)`). A glyph-only diagnostic
///   must keep the default `listening: false`.
/// * Unknown is not a miss and must not reset SRS by itself.
/// * A listening miss stays unrecovered until a later scored hear.
///   Calendar time and visual answers never mint [hasReliableListening].
///
/// Pure data: no `package:flutter/*` imports.
class KanaStat {
  const KanaStat({
    this.seenCount = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.lastReviewedAt,
    this.lastMistakeAt,
    this.srsLevel = 0,
    this.dueAt,
    this.avgLatencyMs = 0,
    this.varLatencyMs2 = 0,
    this.listenSeenCount = 0,
    this.listenCorrectCount = 0,
    this.listenWrongCount = 0,
    this.lastListenAt,
    this.lastListenMistakeAt,
  });

  factory KanaStat.fromJson(Map<String, dynamic> json) {
    final int? millis = (json['l'] as num?)?.toInt();
    final int? mistakeMillis = (json['lm'] as num?)?.toInt();
    final int? dueMillis = (json['d'] as num?)?.toInt();
    final int? listenMillis = (json['ll'] as num?)?.toInt();
    final int? listenMistakeMillis = (json['llm'] as num?)?.toInt();
    // Counts, level and latency moments are clamped, not trusted: one corrupt
    // persisted entry must never crash the interval lookup or the CV math.
    int clampCount(Object? v) => ((v as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
    return KanaStat(
      seenCount: clampCount(json['s']),
      correctCount: clampCount(json['c']),
      wrongCount: clampCount(json['w']),
      lastReviewedAt: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis),
      // Absent [lm] is left null on purpose: old saves have wrongCount without
      // a mistake clock, and inventing one from lastReviewedAt would treat a
      // later correct as a fresh error. Weakness recency stays 0 until a new
      // wrong answer writes a real timestamp.
      lastMistakeAt: mistakeMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(mistakeMillis),
      srsLevel: ((json['sl'] as num?)?.toInt() ?? 0).clamp(
        0,
        _intervalsMinutes.length - 1,
      ),
      dueAt: dueMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dueMillis),
      avgLatencyMs: clampCount(json['al']),
      varLatencyMs2: clampCount(json['vl']),
      // Absent listen keys stay zero/null: old visual-only saves are unknown
      // listening, never inferred from [seenCount] / [correctCount].
      listenSeenCount: clampCount(json['ls']),
      listenCorrectCount: clampCount(json['lc']),
      listenWrongCount: clampCount(json['lw']),
      lastListenAt: listenMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(listenMillis),
      lastListenMistakeAt: listenMistakeMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(listenMistakeMillis),
    );
  }

  final int seenCount;
  final int correctCount;
  final int wrongCount;
  final DateTime? lastReviewedAt;

  /// When this kana was last answered *wrong*. Independent of
  /// [lastReviewedAt], which also moves on a correct answer. Null on legacy
  /// data that predates the field — never backfilled from review time.
  final DateTime? lastMistakeAt;

  /// Lightweight spaced-repetition level (0 = new/just-missed). Drives [dueAt].
  final int srsLevel;

  /// When this kana is next due for review (null until first answered).
  final DateTime? dueAt;

  /// Exponential moving average of *timed* reaction time (ms); 0 = no timed
  /// reading yet. Untimed answers (paper writing, reading) don't change it, so
  /// it stays a clean signal of recognition speed — the reading-fluency
  /// bottleneck, not just correctness.
  final int avgLatencyMs;

  /// Exponentially-weighted moving variance of *timed* RT (ms²); 0 = no/too
  /// little timed spread yet. With [avgLatencyMs] it gives CVRT (stddev/mean),
  /// the research-backed index of recognition automaticity — see [cvLatency].
  final int varLatencyMs2;

  /// Scored sound→kana trials with valid audio. 0 = listening still unknown,
  /// including every pre-field save. Visual [seenCount] is a different tally.
  final int listenSeenCount;

  final int listenCorrectCount;
  final int listenWrongCount;

  /// When a scored listening trial last landed. Independent of
  /// [lastReviewedAt], which also moves on visual answers.
  final DateTime? lastListenAt;

  /// When a scored listening trial was last wrong. Null until a real miss;
  /// never invented from visual [lastMistakeAt].
  final DateTime? lastListenMistakeAt;

  bool get isSeen => seenCount > 0;

  /// True until a scored listening trial with valid audio has been stored.
  /// Unknown is not a miss and does not lower fluency by itself.
  bool get listeningUnknown => listenSeenCount == 0;

  /// Accuracy in [0, 1]; 0 when never seen.
  double get accuracy => seenCount == 0 ? 0 : correctCount / seenCount;

  /// Coefficient of variation of timed RT (stddev/mean) — the automaticity
  /// index; infinity until there is timed data. Lower = steadier = more
  /// automatic recognition.
  double get cvLatency => avgLatencyMs <= 0
      ? double.infinity
      : math.sqrt(varLatencyMs2) / avgLatencyMs;

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

  /// Past [kUntimedCapLevel], a fast answer graduates to the longer intervals
  /// only when reaction time is also CONSISTENT — CVRT (stddev/mean) at or
  /// below this. Automaticity is consistent-fast, not fast-once; a fast-or-slow
  /// guesser holds at the cap until their reading steadies. Below the cap,
  /// early learning still graduates on speed alone (CV needs a few samples).
  static const double kMaxGraduationCv = 0.30;

  /// Two scored correct hears, with the latest listen not a miss, are
  /// enough to stop probing. One lucky pick is not treated as mastery.
  static const int kListeningVerifiedCorrect = 2;

  /// True when the latest scored listen was a miss. Unknown (no listen
  /// miss clock) is never unrecovered. Visual answers and elapsed days
  /// do not clear this — only a later scored hear moves [lastListenAt].
  bool get listeningUnrecovered {
    final missed = lastListenMistakeAt;
    if (missed == null) return false;
    final last = lastListenAt;
    if (last == null) return true;
    return !last.isAfter(missed);
  }

  /// Enough scored sound→kana evidence to leave the listening probe.
  /// Visual strength and calendar time alone never satisfy this.
  /// [now] is kept so #49 can share the predicate without a second clock.
  bool hasReliableListening({required DateTime now}) {
    if (listenCorrectCount < kListeningVerifiedCorrect) return false;
    if (listeningUnrecovered) return false;
    return true;
  }

  /// Daily should still sample sound when listening is unknown, thin, or
  /// unrecovered. Not a quota — a per-item evidence gap.
  bool needsListeningProbe({required DateTime now}) =>
      !hasReliableListening(now: now);

  /// Returns a copy with one answer recorded, advancing the SRS schedule.
  /// [latencyMs] gates graduation (null/0/≥threshold = not fast); past the
  /// untimed cap a fast answer also needs a low [cvLatency] (consistent-fast).
  /// [intervalScale] shrinks the next interval (e.g. 0.5 for confusable kana).
  ///
  /// [listening] is true only for a scored sound→kana trial with valid audio.
  /// Visual answers and failed/cancelled playback keep it false so listen
  /// fields stay honestly unknown.
  KanaStat recordAnswer({
    required bool correct,
    required DateTime at,
    int? latencyMs,
    double intervalScale = 1.0,
    bool listening = false,
  }) {
    // EMA the reaction time AND its variance, but only on real timed readings —
    // untimed answers (paper writing, reading-back) leave both signals untouched.
    // The mean update is unchanged; variance uses the same 0.7/0.3 weights and
    // the deviation from the pre-update mean (incremental EWMVar).
    final int nextAvgLatency;
    final int nextVarLatency2;
    if (latencyMs != null && latencyMs > 0) {
      if (avgLatencyMs == 0) {
        nextAvgLatency = latencyMs; // first timed reading: seed the mean
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
        // Below the cap, CV is statistically meaningless (too few samples), so
        // graduate on speed alone — early learning is unchanged. At/above the
        // cap, only graduate to the long intervals when reaction time is also
        // consistent; an erratic fast-or-slow responder holds (never demotes).
        final double cv = nextAvgLatency <= 0
            ? double.infinity
            : math.sqrt(nextVarLatency2) / nextAvgLatency;
        final consistentEnough =
            srsLevel < kUntimedCapLevel || cv <= kMaxGraduationCv;
        nextLevel = consistentEnough
            ? (srsLevel + 1).clamp(0, _intervalsMinutes.length - 1)
            : srsLevel;
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
      lastMistakeAt: correct ? lastMistakeAt : at,
      srsLevel: nextLevel,
      dueAt: at.add(Duration(minutes: mins)),
      avgLatencyMs: nextAvgLatency,
      varLatencyMs2: nextVarLatency2,
      listenSeenCount: listening ? listenSeenCount + 1 : listenSeenCount,
      listenCorrectCount: listening
          ? listenCorrectCount + (correct ? 1 : 0)
          : listenCorrectCount,
      listenWrongCount: listening
          ? listenWrongCount + (correct ? 0 : 1)
          : listenWrongCount,
      lastListenAt: listening ? at : lastListenAt,
      lastListenMistakeAt: listening && !correct ? at : lastListenMistakeAt,
    );
  }

  /// Hinted / prompted practice: the learner saw the reading before grading.
  /// Counts as exposure so a persisted attempt exists, but must not increment
  /// successful-recall [correctCount] or renew [dueAt] / [srsLevel].
  /// Listening evidence is left untouched — a hinted glyph is not a hear.
  KanaStat recordPromptedPractice({required DateTime at}) {
    return KanaStat(
      seenCount: seenCount + 1,
      correctCount: correctCount,
      wrongCount: wrongCount,
      lastReviewedAt: lastReviewedAt,
      lastMistakeAt: lastMistakeAt,
      srsLevel: srsLevel,
      dueAt: dueAt,
      avgLatencyMs: avgLatencyMs,
      varLatencyMs2: varLatencyMs2,
      listenSeenCount: listenSeenCount,
      listenCorrectCount: listenCorrectCount,
      listenWrongCount: listenWrongCount,
      lastListenAt: lastListenAt,
      lastListenMistakeAt: lastListenMistakeAt,
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
    if (lastMistakeAt != null) 'lm': lastMistakeAt!.millisecondsSinceEpoch,
    // New fields are omitted at defaults so old kana_stats_v1 stays valid.
    if (srsLevel != 0) 'sl': srsLevel,
    if (dueAt != null) 'd': dueAt!.millisecondsSinceEpoch,
    if (avgLatencyMs != 0) 'al': avgLatencyMs,
    if (varLatencyMs2 != 0) 'vl': varLatencyMs2,
    if (listenSeenCount != 0) 'ls': listenSeenCount,
    if (listenCorrectCount != 0) 'lc': listenCorrectCount,
    if (listenWrongCount != 0) 'lw': listenWrongCount,
    if (lastListenAt != null) 'll': lastListenAt!.millisecondsSinceEpoch,
    if (lastListenMistakeAt != null)
      'llm': lastListenMistakeAt!.millisecondsSinceEpoch,
  };

  @override
  String toString() =>
      'KanaStat(seen:$seenCount correct:$correctCount wrong:$wrongCount)';
}
