// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// An immutable, portable capture of the app's canonical progress: per-kana
/// stats, learned unit ids, seen unlock ids, and per-reading kanji stats.
///
/// This is the ONLY body a portable snapshot carries — never analytics, the
/// last-good / quarantine copies, store health, session state, or device info
/// (see `ProgressSnapshotCodec`). It aggregates the two tracks' progress without
/// generalising their stat types: `KanaStat` and `ReadingStat` stay distinct
/// (the kanji module deliberately copies rather than shares the kana types).
///
/// Pure data: no `package:flutter/*` imports. Every collection is
/// defensively copied at construction and exposed only as an unmodifiable
/// view, so a snapshot is a frozen instant — mutating the source repositories
/// afterwards can never change an already-built snapshot.
class ProgressSnapshot {
  ProgressSnapshot({
    required DateTime createdAt,
    required Map<String, KanaStat> kanaStats,
    required Set<String> learnedUnits,
    required Set<String> seenUnlocks,
    required Map<String, ReadingStat> kanjiReadingStats,
  }) : createdAtUtc = createdAt.toUtc(),
       kanaStats = Map.unmodifiable(kanaStats),
       learnedUnits = Set.unmodifiable(learnedUnits),
       seenUnlocks = Set.unmodifiable(seenUnlocks),
       kanjiReadingStats = Map.unmodifiable(kanjiReadingStats);

  /// The capture instant, normalised to UTC.
  final DateTime createdAtUtc;

  /// Per-kana stats keyed by kana id. Unmodifiable; unknown/retired ids are
  /// kept verbatim.
  final Map<String, KanaStat> kanaStats;

  /// Ids of learned lessons/units. Unmodifiable.
  final Set<String> learnedUnits;

  /// Ids of one-time unlock lines already seen. Unmodifiable.
  final Set<String> seenUnlocks;

  /// Per-reading kanji stats keyed by reading id. Unmodifiable.
  final Map<String, ReadingStat> kanjiReadingStats;
}
