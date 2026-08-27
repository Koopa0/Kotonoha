// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';

/// Composes a 渡し舟 (Ferry) session — the track's INTRODUCTION mode. It meets
/// new words ear-first and re-hears familiar ones; it never owns the review
/// schedule (the colder modes — 文字起こし, 黙読 — do, see
/// `WordProgressRepository`).
///
/// Up to [maxNew] never-seen words board first — interest-themed ones ahead
/// (the binding lands hardest on a sound his ear already owns), then dataset
/// order (the introduction order). The rest of the boat fills with seen words,
/// longest-unheard first, so familiar sound keeps circulating without touching
/// anyone's due date.
///
/// The introducer carries the track's ONLY intake valve: while the review
/// backlog (due words) already fills a whole review session, no new word
/// boards at all — introduction throttles itself so the due queue can never
/// diverge. (The schedule-simulation property test is the executable proof:
/// without this gate a 400-word corpus drowns its daily review capacity.)
///
/// Pure logic, deterministic under an injected [Random].
abstract final class FerrySession {
  static List<Word> compose({
    required List<Word> words,
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    int length = 8,
    int maxNew = 3,
  }) {
    final readable = words
        .where((w) => KanaTokenizer.isReadable(w.kana, learnedChars))
        .toList();
    WordStat statOf(Word w) => stats[w.progressId] ?? const WordStat();

    final backlog = readable.where((w) {
      final s = statOf(w);
      return s.isSeen && s.dueAt != null && !s.dueAt!.isAfter(now);
    }).length;
    final allowNew = backlog >= length ? 0 : maxNew;

    final fresh = readable.where((w) => !statOf(w).isSeen).toList();
    // Themed first; otherwise keep dataset order (List.sort is not stable, so
    // sort by (theme, original index) to preserve it within a tier).
    final freshIndex = {
      for (var i = 0; i < fresh.length; i++) fresh[i].progressId: i,
    };
    fresh.sort((a, b) {
      final byTheme = (a.theme != null ? 0 : 1).compareTo(
        b.theme != null ? 0 : 1,
      );
      if (byTheme != 0) return byTheme;
      return freshIndex[a.progressId]!.compareTo(freshIndex[b.progressId]!);
    });

    final taken = <Word>[...fresh.take(min(allowNew, length))];

    if (taken.length < length) {
      final seen = readable.where((w) => statOf(w).isSeen).toList();
      final shuffleKey = {for (final w in seen) w.progressId: rng.nextDouble()};
      int lastMs(Word w) =>
          statOf(w).lastReviewedAt?.millisecondsSinceEpoch ?? 0;
      seen.sort((a, b) {
        final byLast = lastMs(a).compareTo(lastMs(b)); // longest-unheard first
        if (byLast != 0) return byLast;
        return shuffleKey[a.progressId]!.compareTo(shuffleKey[b.progressId]!);
      });
      taken.addAll(seen.take(length - taken.length));
    }

    return taken..shuffle(rng);
  }
}
