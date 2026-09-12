// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';

/// Selects the readable items (words or phrases) — every learning unit must be
/// one the learner can read (see [KanaTokenizer]) — and composes a short
/// reading session scheduled by the 詞と句 stats. Generic over [ReadingItem],
/// so the same gating serves the word and the sentence track.
///
/// Pure logic, deterministic under an injected [Random].
abstract final class ReadingSet {
  /// Short-round cap shared by travel 先教 and Info／Reply first-teach.
  static const int introLength = 8;

  /// First [length] items in catalog order. Does not reshuffle or rewrite
  /// stats — leftover unseen items stay for もう一回 or a later entry.
  static List<T> takeIntro<T>(Iterable<T> items, {int length = introLength}) {
    final list = items is List<T> ? items : List<T>.of(items);
    if (list.length <= length) return list;
    return list.sublist(0, length);
  }

  /// Items every gating stretch of which is readable given [learnedChars] —
  /// the whole kana for a word or phrase, the plain-kana runs for a
  /// mixed-script sentence (see [ReadingItem.gatingText]).
  static List<T> readable<T extends ReadingItem>(
    List<T> items,
    Set<String> learnedChars,
  ) => items
      .where(
        (i) =>
            i.gatingText.isNotEmpty &&
            i.gatingText.every(
              (t) => KanaTokenizer.isReadable(t, learnedChars),
            ),
      )
      .toList();

  /// A session of up to [length] readable items, composed in three tiers and
  /// then shuffled together (so the learner never sees the seams):
  ///
  /// 1. **Due** — items whose `dueAt` has passed, oldest due first. The review
  ///    backlog always outranks novelty.
  /// 2. **New** — up to [maxNew] never-seen items, taken in the order they
  ///    appear in [items] (the dataset's order IS the introduction order).
  ///    Skipped entirely while the due backlog alone fills the session — new
  ///    material never buries overdue material.
  /// 3. **Fill** — seen, not-yet-due items: in-season / season-neutral over
  ///    off-season ([season]; off-season only sinks, never excluded), then
  ///    soonest-due first (closest to fading gets the early review), with a
  ///    soft shuffle within a tier.
  ///
  /// [stats] is keyed by [ReadingItem.progressId]; an absent entry means
  /// never seen. With no stats at all a session is just the paced trickle of
  /// new items — deliberately small: the corpus arrives a few leaves at a
  /// time, and a learner who wants more taps もう一回.
  static List<T> session<T extends ReadingItem>({
    required List<T> items,
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    int length = introLength,
    int maxNew = 3,
    Season? season,
  }) {
    final pool = readable(items, learnedChars);
    WordStat statOf(T it) => stats[it.progressId] ?? const WordStat();

    final due = <T>[];
    final fresh = <T>[]; // never seen, in dataset order
    final rest = <T>[]; // seen, not yet due
    for (final it in pool) {
      final s = statOf(it);
      if (!s.isSeen) {
        fresh.add(it);
      } else if (s.dueAt != null && !s.dueAt!.isAfter(now)) {
        due.add(it);
      } else {
        rest.add(it);
      }
    }

    due.sort(
      (a, b) => (statOf(a).dueAt ?? now).compareTo(statOf(b).dueAt ?? now),
    );
    final taken = <T>[...due.take(length)];

    // Backlog gate: introduce nothing while due reviews alone fill the session.
    final newAllowance = taken.length >= length
        ? 0
        : min(maxNew, length - taken.length);
    taken.addAll(fresh.take(newAllowance));

    if (taken.length < length && rest.isNotEmpty) {
      final shuffleKey = {
        for (final it in rest) it.progressId: rng.nextDouble(),
      };
      int band(T it) =>
          (season == null || it.season == null || it.season == season) ? 0 : 1;
      rest.sort((a, b) {
        final byBand = band(a).compareTo(band(b));
        if (byBand != 0) return byBand;
        final byDue = (statOf(a).dueAt ?? now).compareTo(
          statOf(b).dueAt ?? now,
        );
        if (byDue != 0) return byDue;
        return shuffleKey[a.progressId]!.compareTo(shuffleKey[b.progressId]!);
      });
      taken.addAll(rest.take(length - taken.length));
    }

    return taken..shuffle(rng);
  }
}
