// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';

void main() {
  final now = DateTime(2026, 6);

  test('compose is deterministic, bounded, and draws from the dataset', () {
    final all = {for (final k in kKanji) ...k.readingIds};
    List<KanjiPrompt> run() => KanjiSession.compose(
      entries: kKanji,
      stats: const {},
      now: now,
      rng: Random(3),
      length: 10,
    );
    final a = run();
    final b = run();
    expect(a.length, 10);
    expect(a.map((p) => p.readingId), b.map((p) => p.readingId));
    for (final p in a) {
      expect(all.contains(p.readingId), isTrue);
    }
  });

  test('new readings are surfaced before ones that are not yet due', () {
    // Mark one reading as freshly answered (correct → due far in the future).
    const seen = KanjiEntry(
      char: '人',
      meaningZh: '人',
      readings: [Reading(text: 'ひと', kind: ReadingKind.kun)],
    );
    const fresh = KanjiEntry(
      char: '日',
      meaningZh: '日',
      readings: [Reading(text: 'ニチ', kind: ReadingKind.on)],
    );
    final stats = {
      KanjiEntry.readingId('人', 'ひと'): const ReadingStat().recordAnswer(
        correct: true,
        at: now,
      ), // due in ~1 day
    };
    final out = KanjiSession.compose(
      entries: const [seen, fresh],
      stats: stats,
      now: now,
      rng: Random(1),
      length: 2,
    );
    // The unseen 日#ニチ ranks ahead of the not-yet-due 人#ひと.
    expect(out.first.readingId, 'reading:日#ニチ');
  });
}
