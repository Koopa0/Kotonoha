// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// Composes a 漢字の声 session over the units harvested from the corpus.
///
/// Three tiers, the same intake valve the sentence rooms use:
///
/// 1. **Due** — seen and due now; weaker (higher wrong-rate) first. The
///    review backlog always outranks novelty.
/// 2. **New** — up to [maxNew] never-seen units. Skipped entirely while due
///    reviews alone fill the session, so a Home "review" day cannot be
///    quietly replaced by a first meeting.
/// 3. **Fill** — seen, not-yet-due; weaker first.
///
/// [maxNew] is how the home says what the day is *for*: a meet step passes
/// [kDefaultMaxNew], a review step passes 0. The feature tile uses the
/// default and still honours the backlog gate. Teach vs cold-recall is
/// decided later by `ReadingStat.isSeen`, not by this composer.
///
/// Deterministic under an injected [Random].
abstract final class KanjiSession {
  /// One session's paced trickle of first meetings — matches 黙読 / 名残の仮名.
  static const int kDefaultMaxNew = 3;

  static const int kDefaultLength = 12;

  static List<KanjiUnit> compose({
    required List<KanjiUnit> units,
    required Map<String, ReadingStat> stats,
    required DateTime now,
    required Random rng,
    int length = kDefaultLength,
    int maxNew = kDefaultMaxNew,
  }) {
    ReadingStat statOf(KanjiUnit u) => stats[u.id] ?? const ReadingStat();

    final due = <KanjiUnit>[];
    final fresh = <KanjiUnit>[];
    final rest = <KanjiUnit>[];
    for (final u in units) {
      final s = stats[u.id];
      if (s == null || !s.isSeen) {
        fresh.add(u);
      } else if (s.dueAt != null && !s.dueAt!.isAfter(now)) {
        due.add(u);
      } else {
        rest.add(u);
      }
    }

    due.shuffle(rng);
    fresh.shuffle(rng);
    rest.shuffle(rng);
    due.sort((a, b) => _weakness(statOf(b)).compareTo(_weakness(statOf(a))));
    rest.sort((a, b) => _weakness(statOf(b)).compareTo(_weakness(statOf(a))));

    final taken = <KanjiUnit>[...due.take(length)];
    // Backlog gate: introduce nothing while due reviews alone fill the session.
    final newAllowance = taken.length >= length
        ? 0
        : min(maxNew, length - taken.length);
    taken.addAll(fresh.take(newAllowance));
    if (taken.length < length) {
      taken.addAll(rest.take(length - taken.length));
    }
    return taken;
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
