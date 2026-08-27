// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// Composes a 漢字の声 session over the units harvested from the corpus.
/// Light guidance: surface never-met units first, then ones due for review,
/// then the rest — so early sessions teach and later ones reinforce. WITHIN a
/// tier the weaker unit (more often missed) resurfaces first. Deterministic
/// under an injected [Random].
abstract final class KanjiSession {
  static List<KanjiUnit> compose({
    required List<KanjiUnit> units,
    required Map<String, ReadingStat> stats,
    required DateTime now,
    required Random rng,
    int length = 12,
  }) {
    final all = List<KanjiUnit>.of(units)..shuffle(rng);

    int rank(KanjiUnit u) {
      final s = stats[u.id];
      if (s == null || !s.isSeen) return 0; // new
      if (s.dueAt != null && !s.dueAt!.isAfter(now)) return 1; // due
      return 2; // not yet due
    }

    double weakness(KanjiUnit u) {
      final s = stats[u.id];
      return s == null ? 0 : _weakness(s);
    }

    all.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      // Within a tier, weaker first; the shuffle breaks any remaining tie.
      return weakness(b).compareTo(weakness(a));
    });
    return all.take(length).toList();
  }

  /// A unit's weakness for in-tier ordering: its wrong-rate. One you miss more
  /// often comes back before a crisp one. New units score 0 here (their
  /// priority comes from the rank tier). The kanji track is untimed — reading
  /// is a near-binary retrieval, not a reaction-time reflex, so the timed
  /// slowness/CV terms `KanaStat` carries were retired (2026-06-03).
  static double _weakness(ReadingStat s) {
    if (s.seenCount == 0) return 0;
    return s.wrongCount / s.seenCount;
  }
}
