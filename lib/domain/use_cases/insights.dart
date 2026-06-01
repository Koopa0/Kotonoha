// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/attempt.dart';

/// A quiet read of the analytics event stream — totals, accuracy, automaticity
/// (reaction time), and where the practice has gone. Pure: it summarises a list
/// of [Attempt]s and computes nothing about the UI.
class InsightsSummary {
  const InsightsSummary({
    required this.total,
    required this.correct,
    required this.avgRtMs,
    required this.perMode,
    required this.distinctItems,
  });

  final int total;
  final int correct;

  /// Average reaction time over genuine RECOGNITION attempts (the MC quiz
  /// modes), or null if none. Self-paced modes (ferry read-back, dictation
  /// assembly) and untimed ones (reading, writing) are excluded, so this stays a
  /// clean automaticity signal rather than a mix of incomparable durations.
  final int? avgRtMs;

  /// Count of attempts per [PracticeMode] name.
  final Map<String, int> perMode;

  /// Distinct items (kana/words) the learner has practised.
  final int distinctItems;

  double get accuracy => total == 0 ? 0 : correct / total;
}

abstract final class Insights {
  /// The forced-choice quiz modes whose rtMs is a true recognition reaction —
  /// comparable across attempts. Other modes are self-paced or untimed.
  static const Set<String> _reactionModes = {
    'quickReview',
    'lessonTest',
    'missed',
    'confusable',
    'daily',
  };

  static InsightsSummary summarize(List<Attempt> attempts) {
    var correct = 0;
    var rtSum = 0;
    var rtCount = 0;
    final perMode = <String, int>{};
    final items = <String>{};
    for (final a in attempts) {
      if (a.correct) correct++;
      if (a.rtMs > 0 && _reactionModes.contains(a.mode)) {
        rtSum += a.rtMs;
        rtCount++;
      }
      perMode[a.mode] = (perMode[a.mode] ?? 0) + 1;
      items.add(a.itemId);
    }
    return InsightsSummary(
      total: attempts.length,
      correct: correct,
      avgRtMs: rtCount == 0 ? null : (rtSum / rtCount).round(),
      perMode: perMode,
      distinctItems: items.length,
    );
  }
}
