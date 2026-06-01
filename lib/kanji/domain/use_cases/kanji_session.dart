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
/// and later ones reinforce. Deterministic under an injected [Random].
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

    all.sort((a, b) => rank(a).compareTo(rank(b)));
    return all.take(length).toList();
  }
}
