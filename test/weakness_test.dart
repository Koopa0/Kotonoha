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
        lastReviewedAt: now,
        lastMistakeAt: now.subtract(const Duration(hours: 1)),
      );
      final old = KanaStat(
        seenCount: 4,
        correctCount: 2,
        wrongCount: 2,
        lastReviewedAt: now,
        lastMistakeAt: now.subtract(const Duration(days: 30)),
      );
      expect(
        Weakness.score(recent, now: now),
        greaterThan(Weakness.score(old, now: now)),
      );
    });

    test('a later correct fast answer does not revive an old mistake', () {
      final old = KanaStat(
        seenCount: 100,
        correctCount: 99,
        wrongCount: 1,
        lastReviewedAt: now.subtract(const Duration(days: 30)),
        lastMistakeAt: now.subtract(const Duration(days: 30)),
        avgLatencyMs: 500,
        srsLevel: 6,
        dueAt: now,
      );
      final before = Weakness.score(old, now: now);
      final after = old.recordAnswer(correct: true, at: now, latencyMs: 500);
      expect(after.lastMistakeAt, old.lastMistakeAt);
      expect(Weakness.score(after, now: now), lessThanOrEqualTo(before));
    });

    test('legacy wrongCount without lastMistakeAt gets no recency boost', () {
      final legacy = KanaStat(
        seenCount: 100,
        correctCount: 99,
        wrongCount: 1,
        lastReviewedAt: now,
        avgLatencyMs: 500,
        srsLevel: 6,
      );
      // 0.7 * 0.01 + 0 recency + 0 slowness. Must not treat lastReviewedAt
      // as a fresh mistake.
      expect(Weakness.score(legacy, now: now), closeTo(0.007, 0.0001));
    });

    test('a new wrong answer still gets full recency', () {
      final missed = const KanaStat(
        seenCount: 10,
        correctCount: 10,
      ).recordAnswer(correct: false, at: now);
      expect(missed.lastMistakeAt, now);
      expect(Weakness.score(missed, now: now), greaterThan(0.3));
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
