// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/word.dart';

/// Composes a 渡し舟 (Ferry) session: words whose kana are all unlocked, with
/// interest-themed words (the ones his ear is most likely to already know)
/// ferried first — the binding lands hardest on a sound he already owns — and,
/// within each tier, least-recently-seen first so the pool keeps feeling fresh.
///
/// Pure logic, deterministic under an injected [Random].
abstract final class FerrySession {
  static List<Word> compose({
    required List<Word> words,
    required Set<String> learnedChars,
    required Random rng,
    int length = 8,
    Map<String, int> lastSeen = const {},
  }) {
    final readable = words
        .where((w) => w.characters.every(learnedChars.contains))
        .toList();
    final shuffleKey = [for (final _ in readable) rng.nextDouble()];
    int themedRank(Word w) => w.theme != null ? 0 : 1; // themed first
    int lastTs(Word w) => lastSeen[w.displayText] ?? 0; // never-seen first
    final order = List<int>.generate(readable.length, (i) => i)
      ..sort((a, b) {
        final byTheme = themedRank(
          readable[a],
        ).compareTo(themedRank(readable[b]));
        if (byTheme != 0) return byTheme;
        final byTs = lastTs(readable[a]).compareTo(lastTs(readable[b]));
        if (byTs != 0) return byTs;
        return shuffleKey[a].compareTo(shuffleKey[b]);
      });
    return [for (final i in order.take(length)) readable[i]];
  }
}
