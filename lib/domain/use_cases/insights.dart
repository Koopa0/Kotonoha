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

  /// Average reaction time over *timed* attempts (rtMs > 0), or null if none —
  /// untimed modes (writing, reading) don't contribute.
  final int? avgRtMs;

  /// Count of attempts per [PracticeMode] name.
  final Map<String, int> perMode;

  /// Distinct items (kana/words) the learner has practised.
  final int distinctItems;

  double get accuracy => total == 0 ? 0 : correct / total;
}

abstract final class Insights {
  static InsightsSummary summarize(List<Attempt> attempts) {
    var correct = 0;
    var rtSum = 0;
    var rtCount = 0;
    final perMode = <String, int>{};
    final items = <String>{};
    for (final a in attempts) {
      if (a.correct) correct++;
      if (a.rtMs > 0) {
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
