// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/word.dart';

/// Selects the words a learner can actually read — every kana in the word must
/// be one they've unlocked — and composes a short reading session from them.
///
/// Pure logic, deterministic under an injected [Random].
abstract final class ReadingSet {
  /// Words whose every kana is in [learnedChars].
  static List<Word> readable(List<Word> words, Set<String> learnedChars) =>
      words.where((w) => w.characters.every(learnedChars.contains)).toList();

  /// A shuffled session of up to [length] readable words.
  static List<Word> session({
    required List<Word> words,
    required Set<String> learnedChars,
    required Random rng,
    int length = 10,
  }) {
    final pool = readable(words, learnedChars)..shuffle(rng);
    return pool.take(length).toList();
  }
}
