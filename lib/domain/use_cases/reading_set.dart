// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';

/// Selects the readable items (words or phrases) — every kana must be one the
/// learner has unlocked — and composes a short reading session. Generic over
/// [ReadingItem], so the same gating serves the word and the sentence track.
///
/// Pure logic, deterministic under an injected [Random].
abstract final class ReadingSet {
  /// Items whose every kana is in [learnedChars].
  static List<T> readable<T extends ReadingItem>(
    List<T> items,
    Set<String> learnedChars,
  ) => items.where((i) => i.characters.every(learnedChars.contains)).toList();

  /// A session of up to [length] readable items, ordered (highest priority first):
  /// in-season / season-neutral over off-season ([season]; off-season is never
  /// excluded — it just sinks, so a falling cherry can still surface in winter),
  /// then least-recently-seen over recently-seen ([lastSeen]: displayText → last
  /// attempt ms; absent = never seen = surfaces first, so the deeper corpus keeps
  /// feeling fresh), with a soft shuffle within each tier. Both biases are felt,
  /// never shown. With no [season]/[lastSeen] it is a plain deterministic shuffle.
  static List<T> session<T extends ReadingItem>({
    required List<T> items,
    required Set<String> learnedChars,
    required Random rng,
    int length = 10,
    Season? season,
    Map<String, int> lastSeen = const {},
  }) {
    final pool = readable(items, learnedChars);
    // A deterministic per-item key — Dart's List.sort is NOT stable, so we order
    // fully; this key is the soft shuffle within a tier.
    final shuffleKey = [for (final _ in pool) rng.nextDouble()];
    // Season-neutral (null) and current-season items share the top band; with no
    // current season given, every item is top-band (no lift).
    int band(T it) =>
        (season == null || it.season == null || it.season == season) ? 0 : 1;
    // Never-seen (absent → 0) sorts before seen; among seen, oldest-seen first.
    int lastTs(T it) => lastSeen[it.displayText] ?? 0;
    final order = List<int>.generate(pool.length, (i) => i)
      ..sort((a, b) {
        final byBand = band(pool[a]).compareTo(band(pool[b]));
        if (byBand != 0) return byBand;
        final byTs = lastTs(pool[a]).compareTo(lastTs(pool[b]));
        if (byTs != 0) return byTs;
        return shuffleKey[a].compareTo(shuffleKey[b]);
      });
    return [for (final i in order.take(length)) pool[i]];
  }
}
