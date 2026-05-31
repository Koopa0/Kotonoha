// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// Lightweight spaced-repetition scheduling: turns each kana's [KanaStat.dueAt]
/// into a "due now" list. NOT a full SRS — the interval logic lives in
/// [KanaStat.recordAnswer]; this just queries it. Pure logic, no Flutter.
abstract final class Scheduler {
  /// Kana whose review time has arrived (dueAt ≤ now), earliest-due first.
  static List<Kana> due(
    List<Kana> kana,
    Map<String, KanaStat> stats, {
    required DateTime now,
  }) {
    final result = kana.where((k) {
      final s = stats[k.id];
      return s != null && s.dueAt != null && !s.dueAt!.isAfter(now);
    }).toList();
    result.sort((a, b) => stats[a.id]!.dueAt!.compareTo(stats[b.id]!.dueAt!));
    return result;
  }

  static int dueCount(
    List<Kana> kana,
    Map<String, KanaStat> stats, {
    required DateTime now,
  }) => due(kana, stats, now: now).length;
}
