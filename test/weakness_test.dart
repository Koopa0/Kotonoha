// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

void main() {
  const all = kHiraganaGojuon;
  final now = DateTime(2026, 5, 29, 12);

  String id(String c) => c;

  group('Weakness.score', () {
    test('unseen kana get the cold-start baseline', () {
      expect(
        Weakness.score(const KanaStat(), now: now),
        Weakness.unseenBaseline,
      );
    });

    test('higher wrong-rate scores weaker', () {
      final mostlyWrong = KanaStat(
        seenCount: 10,
        correctCount: 2,
        wrongCount: 8,
        lastReviewedAt: now,
      );
      final mostlyRight = KanaStat(
        seenCount: 10,
        correctCount: 9,
        wrongCount: 1,
        lastReviewedAt: now,
      );
      expect(
        Weakness.score(mostlyWrong, now: now),
        greaterThan(Weakness.score(mostlyRight, now: now)),
      );
    });

    test('a recent mistake scores weaker than an old one', () {
      final recent = KanaStat(
        seenCount: 4,
        correctCount: 2,
        wrongCount: 2,
        lastReviewedAt: now.subtract(const Duration(hours: 1)),
      );
      final old = KanaStat(
        seenCount: 4,
        correctCount: 2,
        wrongCount: 2,
        lastReviewedAt: now.subtract(const Duration(days: 30)),
      );
      expect(
        Weakness.score(recent, now: now),
        greaterThan(Weakness.score(old, now: now)),
      );
    });

    test('a well-known kana scores below the unseen baseline', () {
      final known = KanaStat(
        seenCount: 20,
        correctCount: 20,
        lastReviewedAt: now,
      );
      expect(
        Weakness.score(known, now: now),
        lessThan(Weakness.unseenBaseline),
      );
    });
  });

  group('Weakness.rankByWeakness', () {
    test('puts the kana with the worst record first', () {
      final stats = <String, KanaStat>{
        id('あ'): KanaStat(
          seenCount: 10,
          correctCount: 9,
          wrongCount: 1,
          lastReviewedAt: now,
        ),
        id('い'): KanaStat(
          seenCount: 10,
          correctCount: 1,
          wrongCount: 9,
          lastReviewedAt: now,
        ),
      };
      final ranked = Weakness.rankByWeakness(all, stats, now: now);
      // い (mostly wrong) must rank ahead of あ (mostly right) and of any unseen.
      expect(ranked.first.character, 'い');
      expect(
        ranked.indexWhere((k) => k.character == 'い'),
        lessThan(ranked.indexWhere((k) => k.character == 'あ')),
      );
    });

    test('is deterministic and stable for equal scores', () {
      final ranked1 = Weakness.rankByWeakness(all, const {}, now: now);
      final ranked2 = Weakness.rankByWeakness(all, const {}, now: now);
      expect(
        ranked1.map((k) => k.character).toList(),
        ranked2.map((k) => k.character).toList(),
      );
      // All unseen → original gojūon order preserved.
      expect(
        ranked1.map((k) => k.character).toList(),
        all.map((k) => k.character).toList(),
      );
    });

    test('weakest(count) returns at most count kana, weakest first', () {
      final stats = <String, KanaStat>{
        id('か'): KanaStat(seenCount: 5, wrongCount: 5, lastReviewedAt: now),
      };
      final top = Weakness.weakest(all, stats, now: now, count: 5);
      expect(top.length, 5);
      expect(top.first.character, 'か');
    });
  });
}
