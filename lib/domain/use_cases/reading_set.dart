// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/reading_item.dart';

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

  /// A shuffled session of up to [length] readable items.
  static List<T> session<T extends ReadingItem>({
    required List<T> items,
    required Set<String> learnedChars,
    required Random rng,
    int length = 10,
  }) {
    final pool = readable(items, learnedChars)..shuffle(rng);
    return pool.take(length).toList();
  }
}
