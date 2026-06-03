// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// One practice item: a single reading of a kanji (the scheduling/analytics
/// unit). The kanji is the star; the on/kun kind is the recall cue.
class KanjiPrompt {
  const KanjiPrompt({required this.entry, required this.reading});

  final KanjiEntry entry;
  final Reading reading;

  String get readingId => KanjiEntry.readingId(entry.char, reading.text);
}

/// Composes a kanji reading session. Light guidance: surface new readings first,
/// then ones that are due for review, then the rest — so early sessions teach
/// and later ones reinforce. WITHIN a tier, the weaker reading (recently missed,
/// or slow/erratic on the timed recall beat) resurfaces first, so the latency/CV
/// signal has somewhere to land. Deterministic under an injected [Random].
abstract final class KanjiSession {
  static List<KanjiPrompt> compose({
    required List<KanjiEntry> entries,
    required Map<String, ReadingStat> stats,
    required DateTime now,
    required Random rng,
    int length = 12,
  }) {
    final all = <KanjiPrompt>[
      for (final e in entries)
        for (final r in e.readings) KanjiPrompt(entry: e, reading: r),
    ]..shuffle(rng);

    int rank(KanjiPrompt p) {
      final s = stats[p.readingId];
      if (s == null || !s.isSeen) return 0; // new
      if (s.dueAt != null && !s.dueAt!.isAfter(now)) return 1; // due
      return 2; // not yet due
    }

    double weakness(KanjiPrompt p) {
      final s = stats[p.readingId];
      return s == null ? 0 : _readingWeakness(s);
    }

    all.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      // Within a tier, weaker first; the shuffle breaks any remaining tie.
      return weakness(b).compareTo(weakness(a));
    });
    return all.take(length).toList();
  }

  /// A reading's weakness for in-tier ordering: its wrong-rate. A reading you
  /// miss more often comes back before a crisp one. New/unseen readings score 0
  /// here (their priority comes from the rank tier). The kanji track is untimed —
  /// reading mastery is a near-binary retrieval, not a reaction-time reflex, so
  /// the timed slowness/CV terms `KanaStat` carries were retired (2026-06-03);
  /// wrong-rate is the whole signal.
  static double _readingWeakness(ReadingStat s) {
    if (s.seenCount == 0) return 0;
    return s.wrongCount / s.seenCount;
  }
}
