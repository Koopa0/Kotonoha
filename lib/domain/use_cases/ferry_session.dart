// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/word.dart';

/// Composes a 渡し舟 (Ferry) session: words whose kana are all unlocked, with
/// interest-themed words (the ones his ear is most likely to already know)
/// ferried first — the binding lands hardest on a sound he already owns.
///
/// Pure logic, deterministic under an injected [Random].
abstract final class FerrySession {
  static List<Word> compose({
    required List<Word> words,
    required Set<String> learnedChars,
    required Random rng,
    int length = 8,
  }) {
    final readable = words
        .where((w) => w.characters.every(learnedChars.contains))
        .toList();
    final themed = readable.where((w) => w.theme != null).toList()
      ..shuffle(rng);
    final plain = readable.where((w) => w.theme == null).toList()..shuffle(rng);
    return [...themed, ...plain].take(length).toList();
  }
}
