// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';

void main() {
  final now = DateTime(2026, 6);

  KanjiUnit unit(String written, String reading) => KanjiUnit(
    written: written,
    reading: reading,
    example: KanjiPhrase(
      segments: [
        RubySegment(text: written, furigana: reading),
        const RubySegment(text: 'を'),
      ],
      romaji: 'x',
      meaning: 'x',
    ),
  );

  test('compose is deterministic, bounded, and draws from the units given', () {
    final units = kKanjiUnits;
    final ids = {for (final u in units) u.id};
    List<KanjiUnit> run() => KanjiSession.compose(
      units: units,
      stats: const {},
      now: now,
      rng: Random(3),
      length: 10,
      maxNew: 10,
    );
    final a = run();
    final b = run();
    expect(a.length, 10);
    expect(a.map((u) => u.id), b.map((u) => u.id));
    for (final u in a) {
      expect(ids.contains(u.id), isTrue);
    }
  });

  test('a cold start is a trickle of new units, not the whole corpus', () {
    final out = KanjiSession.compose(
      units: kKanjiUnits,
      stats: const {},
      now: now,
      rng: Random(3),
    );
    expect(out.length, KanjiSession.kDefaultMaxNew);
    expect(out.map((u) => u.id).toSet(), hasLength(out.length));
  });

  test('never-met units are surfaced before ones that are not yet due', () {
    final seen = unit('人', 'ひと');
    final fresh = unit('日', 'ひ');
    final stats = {
      seen.id: const ReadingStat().recordAnswer(
        correct: true,
        at: now,
      ), // due in ~1 day
    };

    final out = KanjiSession.compose(
      units: [seen, fresh],
      stats: stats,
      now: now,
      rng: Random(1),
      length: 2,
    );

    expect(out.first.id, fresh.id);
  });

  test('within a tier, a weaker unit resurfaces before a crisp one', () {
    final past = DateTime(2026, 5);
    final later = DateTime(2026, 6); // a month on — both stats are due
    final weak = unit('一', 'いち');
    final strong = unit('二', 'に');
    final stats = {
      // missed → high wrong-rate
      weak.id: const ReadingStat().recordAnswer(correct: false, at: past),
      // correct → low wrong-rate
      strong.id: const ReadingStat().recordAnswer(correct: true, at: past),
    };

    final out = KanjiSession.compose(
      units: [strong, weak],
      stats: stats,
      now: later,
      rng: Random(1),
      length: 2,
    );

    expect(out.first.id, weak.id);
  });

  test('due units fill the session before any new intake', () {
    final due = [for (var i = 0; i < 12; i++) unit('D$i', 'だ$i')];
    final fresh = [for (var i = 0; i < 20; i++) unit('N$i', 'な$i')];
    final past = now.subtract(const Duration(days: 1));
    final stats = {
      for (final u in due)
        u.id: ReadingStat(
          seenCount: 1,
          correctCount: 1,
          srsLevel: 1,
          lastReviewedAt: past,
          dueAt: past,
        ),
    };

    final out = KanjiSession.compose(
      units: [...fresh, ...due],
      stats: stats,
      now: now,
      rng: Random(2),
    );

    expect(out.map((u) => u.id).toSet(), {for (final u in due) u.id});
    expect(out.any((u) => stats[u.id] == null), isFalse);
  });

  test('review intent (maxNew: 0) never boards an unmet unit', () {
    final seen = unit('人', 'ひと');
    final fresh = unit('日', 'ひ');
    final past = now.subtract(const Duration(days: 1));
    final stats = {
      seen.id: ReadingStat(
        seenCount: 1,
        correctCount: 1,
        srsLevel: 1,
        lastReviewedAt: past,
        dueAt: past,
      ),
    };

    final out = KanjiSession.compose(
      units: [seen, fresh],
      stats: stats,
      now: now,
      rng: Random(4),
      length: 12,
      maxNew: 0,
    );

    expect(out.map((u) => u.id), [seen.id]);
  });

  test('each unit appears at most once per session (teach XOR recall)', () {
    // The honest screen routes new→teach / met→recall off this one-pass
    // uniqueness: a unit is never taught AND recalled in the same session.
    final out = KanjiSession.compose(
      units: kKanjiUnits,
      stats: const {},
      now: now,
      rng: Random(5),
      length: 1000, // larger than the corpus → take everything
      maxNew: 1000,
    );
    final ids = out.map((u) => u.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
