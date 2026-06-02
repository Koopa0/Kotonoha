// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';

void main() {
  const spring = KotenLine(
    text: 'はる',
    reading: 'はる',
    gloss: 'g',
    attribution: 'a・公有領域',
    season: Season.spring,
  );
  const winter = KotenLine(
    text: 'ふゆ',
    reading: 'ふゆ',
    gloss: 'g',
    attribution: 'a・公有領域',
    season: Season.winter,
  );
  const neutral = KotenLine(
    text: 'む',
    reading: 'む',
    gloss: 'g',
    attribution: 'a・公有領域',
  );
  const pool = [spring, winter, neutral];

  KotenLine? pick(
    Random rng, {
    int seen = 100,
    Season? season,
    double chance = 1.0,
  }) => KotenShare.pick(
    pool: pool,
    seenKanaCount: seen,
    rng: rng,
    season: season,
    appearChance: chance,
  );

  test('an empty pool yields nothing', () {
    expect(
      KotenShare.pick(pool: const [], seenKanaCount: 100, rng: Random(1)),
      isNull,
    );
  });

  test(
    'not shown before the learner has met enough kana (the earned gate)',
    () {
      expect(pick(Random(1), seen: 5), isNull); // below default minSeen
      expect(pick(Random(1), seen: 16), isNotNull); // at the gate, chance 1
    },
  );

  test('appearChance 0 never surfaces; 1 always surfaces past the gate', () {
    for (var s = 0; s < 30; s++) {
      expect(pick(Random(s), chance: 0), isNull);
      expect(pick(Random(s)), isNotNull); // default chance 1.0 → always
    }
  });

  test('is deterministic under a fixed seed', () {
    expect(pick(Random(7))?.text, pick(Random(7))?.text);
  });

  test('off-season lines are weighted down but NEVER excluded (名残)', () {
    // Spring is current, yet a winter line must still surface across enough
    // draws — the year turns, but nothing is locked out.
    final seen = <String>{};
    for (var s = 0; s < 200; s++) {
      final l = pick(Random(s), season: Season.spring);
      if (l != null) seen.add(l.text);
    }
    expect(seen, containsAll(<String>{'はる', 'ふゆ', 'む'}));
  });
}
