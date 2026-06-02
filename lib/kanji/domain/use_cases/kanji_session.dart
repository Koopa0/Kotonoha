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

  /// A reading's weakness for in-tier ordering: wrong-rate (primary) plus, for
  /// the timed recall beat, slowness and erratic timing (high CV) — so a reading
  /// you produce slowly or unevenly comes back before a crisp one. New/unseen
  /// readings score 0 here (their priority comes from the rank tier).
  ///
  /// CURRENTLY the slowness + CV terms are DORMANT: the kanji UI is untimed
  /// (latencyMs null), so avgLatencyMs stays 0 and only the wrong-rate term has
  /// any effect — this degrades gracefully to pure wrong-rate ordering. They
  /// activate the moment a timed kanji beat feeds real latency (mirrors KanaStat).
  static double _readingWeakness(ReadingStat s) {
    if (s.seenCount == 0) return 0;
    final double wrongRate = s.wrongCount / s.seenCount;
    double slowness = 0;
    if (s.avgLatencyMs > ReadingStat.kFastThresholdMs) {
      slowness =
          ((s.avgLatencyMs - ReadingStat.kFastThresholdMs) /
                  (2000 - ReadingStat.kFastThresholdMs))
              .clamp(0.0, 1.0);
    }
    double erratic = 0;
    if (s.avgLatencyMs > 0 && s.cvLatency.isFinite) {
      erratic = (s.cvLatency / 0.6).clamp(0.0, 1.0);
    }
    return 0.7 * wrongRate + 0.2 * slowness + 0.2 * erratic;
  }
}
