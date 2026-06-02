// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/season.dart';

/// Picks — *occasionally* — a classical PD line to deepen a session's 凪 close into
/// a quiet 余韻 (see [KotenLine]). The design constraints are the whole point:
///
/// - **Occasional, never every close.** It appears with [appearChance], so it can
///   never be farmed and never trains "open the app for today's" (no daily hook).
/// - **No memory, repeats allowed.** A weighted-random draw with no seen-set — a
///   notebook re-reads a loved line. Nothing is tracked, counted, or collectible.
/// - **Earned, not for absolute beginners.** Returns null until the learner has met
///   at least [minSeen] kana, so a first-lesson learner isn't shown a Bashō haiku.
/// - **The year quietly turns.** An in-[season] line is weighted up, but off-season
///   lines are never excluded (物の哀れ / 名残) — same spirit as reading sampling.
///
/// Pure logic, deterministic under the injected [rng]: no `package:flutter/*`.
abstract final class KotenShare {
  /// Returns a line to show at the close, or null to leave the close plain.
  ///
  /// [seenKanaCount] is the learner's met-kana count (the earned gate); [season]
  /// is the current season (null disables the seasonal lift). [appearChance] is
  /// the per-close probability the share surfaces at all.
  static KotenLine? pick({
    required List<KotenLine> pool,
    required int seenKanaCount,
    required Random rng,
    Season? season,
    double appearChance = 0.28,
    int minSeen = 16,
  }) {
    if (pool.isEmpty || seenKanaCount < minSeen) return null;
    if (rng.nextDouble() >= appearChance) return null;

    // In-season lines float (weight 3); season-neutral lines stay present
    // (weight 2); off-season lines sink but are never excluded (weight 1).
    double weightOf(KotenLine l) {
      if (l.season == null) return 2;
      if (season != null && l.season == season) return 3;
      return 1;
    }

    final total = pool.fold<double>(0, (sum, l) => sum + weightOf(l));
    var r = rng.nextDouble() * total;
    for (final l in pool) {
      r -= weightOf(l);
      if (r < 0) return l;
    }
    return pool.last; // float-rounding fallback; total > 0 guaranteed above
  }
}
