// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';

/// #70: historically verified listening still ages. The 40-day composer/stat
/// numbers are a production counterexample on main `51af48a` (480 kanaRecall,
/// lastListenAt frozen on day 0), not a claim about a real learner.
void main() {
  const pool = kHiraganaGojuon;
  final day0 = DateTime(2026, 9, 10, 12);

  Map<String, KanaStat> seededVerified({DateTime? heardAt}) {
    final heard = heardAt ?? day0;
    return {
      for (final k in pool)
        k.id: KanaStat(
          seenCount: 8,
          correctCount: 8,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: heard,
          dueAt: heard.add(const Duration(days: 30)),
          listenSeenCount: 2,
          listenCorrectCount: 2,
          lastListenAt: heard,
        ),
    };
  }

  Map<String, KanaStat> visualUnknown() => {
    for (final k in pool)
      k.id: KanaStat(
        seenCount: 8,
        correctCount: 8,
        srsLevel: 6,
        avgLatencyMs: 500,
        lastReviewedAt: day0,
        dueAt: day0.add(const Duration(days: 30)),
      ),
  };

  List<QuizDirection> composeDirections({
    required Map<String, KanaStat> stats,
    required DateTime now,
    bool quiet = false,
    int seed = 0,
  }) {
    final items = DailySession.compose(
      pool: pool,
      stats: stats,
      newCandidates: const [],
      now: now,
      rng: Random(seed),
      quiet: quiet,
    );
    expect(items.length, 12);
    for (final item in items) {
      expect(pool.any((p) => p.id == item.question.target.id), isTrue);
      if (item.question.direction == QuizDirection.soundToKana) {
        expect(item.question.options.length, 4);
        expect(item.question.isForcedCorrect, isFalse);
      }
    }
    return [for (final i in items) i.question.direction];
  }

  test('day 0 and day 1 stay recall; day 8 and day 40 re-sample sound', () {
    final stats = seededVerified();
    expect(
      composeDirections(stats: stats, now: day0),
      everyElement(QuizDirection.kanaRecall),
    );
    expect(
      composeDirections(
        stats: stats,
        now: day0.add(const Duration(days: 1)),
        seed: 1,
      ),
      everyElement(QuizDirection.kanaRecall),
    );
    expect(
      composeDirections(
        stats: stats,
        now: day0.add(KanaStat.kListeningRecheckWindow),
        seed: 7,
      ),
      everyElement(QuizDirection.kanaRecall),
    );
    expect(
      composeDirections(
        stats: stats,
        now: day0.add(const Duration(days: 8)),
        seed: 8,
      ),
      everyElement(QuizDirection.soundToKana),
    );
    expect(
      composeDirections(
        stats: stats,
        now: day0.add(const Duration(days: 40)),
        seed: 40,
      ),
      everyElement(QuizDirection.soundToKana),
    );
  });

  test('40-day composer/stat: directions and targets both spread', () {
    final stats = seededVerified();
    final directionCounts = <QuizDirection, int>{};
    final targetCounts = <String, int>{};
    final soundTargetCounts = <String, int>{};

    for (var day = 1; day <= 40; day++) {
      final now = day0.add(Duration(days: day));
      final items = DailySession.compose(
        pool: pool,
        stats: stats,
        newCandidates: const [],
        now: now,
        rng: Random(day),
      );
      expect(items.length, 12);
      for (final item in items) {
        final dir = item.question.direction;
        final id = item.question.target.id;
        expect(pool.any((p) => p.id == id), isTrue);
        directionCounts.update(dir, (n) => n + 1, ifAbsent: () => 1);
        targetCounts.update(id, (n) => n + 1, ifAbsent: () => 1);
        if (dir == QuizDirection.soundToKana) {
          expect(item.question.options.length, 4);
          expect(item.question.isForcedCorrect, isFalse);
          soundTargetCounts.update(id, (n) => n + 1, ifAbsent: () => 1);
        }
        stats[id] = stats[id]!.recordAnswer(
          correct: true,
          at: now,
          latencyMs: 500,
          listening: dir == QuizDirection.soundToKana,
        );
      }
    }

    final day40 = day0.add(const Duration(days: 40));
    final recall = directionCounts[QuizDirection.kanaRecall] ?? 0;
    final sound = directionCounts[QuizDirection.soundToKana] ?? 0;
    final minSound = soundTargetCounts.values.reduce(min);
    final maxSound = soundTargetCounts.values.reduce(max);
    final lastListenDays = stats.values
        .map((s) => s.lastListenAt!.difference(day0).inDays)
        .toSet();

    expect(recall, 294);
    expect(sound, 186);
    expect(directionCounts[QuizDirection.romajiToKana] ?? 0, 0);
    expect(targetCounts.length, 46);
    expect(
      soundTargetCounts.length,
      46,
      reason: 'spot checks cannot lock a few glyphs',
    );
    expect(minSound, 3);
    expect(maxSound, 5);
    expect(lastListenDays.contains(0), isFalse);
    expect(lastListenDays, {32, 33, 34, 35, 36, 37, 38, 39, 40});

    for (final s in stats.values) {
      expect(s.hasReliableListening(now: day40), isTrue);
      expect(s.listenWrongCount, 0);
      expect(s.srsLevel, 6);
    }
  });

  test('unknown listening control still probes sound after 40 quiet days', () {
    final dirs = composeDirections(
      stats: visualUnknown(),
      now: day0.add(const Duration(days: 40)),
      seed: 40,
    );
    expect(dirs, everyElement(QuizDirection.soundToKana));
  });

  test('quiet control stays silent for stale verified hears', () {
    final dirs = composeDirections(
      stats: seededVerified(),
      now: day0.add(const Duration(days: 40)),
      seed: 40,
      quiet: true,
    );
    expect(dirs, everyElement(QuizDirection.kanaRecall));
  });

  test('unlearned kana stay out of the daily target pool', () {
    final learned = pool.take(20).toList();
    final stats = {
      for (final k in learned)
        k.id: KanaStat(
          seenCount: 8,
          correctCount: 8,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: day0,
          dueAt: day0.add(const Duration(days: 30)),
          listenSeenCount: 2,
          listenCorrectCount: 2,
          lastListenAt: day0,
        ),
    };
    final items = DailySession.compose(
      pool: learned,
      stats: stats,
      newCandidates: const [],
      now: day0.add(const Duration(days: 8)),
      rng: Random(8),
    );
    final learnedIds = learned.map((k) => k.id).toSet();
    for (final item in items) {
      expect(learnedIds.contains(item.question.target.id), isTrue);
      expect(item.question.direction, QuizDirection.soundToKana);
    }
  });
}
