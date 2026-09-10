// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

/// Inversion of the #12 sampling probe: equally-strong not-due kana must
/// not lock あいうえ into every session, and true weaks must still repeat.
void main() {
  final start = DateTime(2026, 9, 10, 10);
  const pool46 = kHiraganaGojuon;
  const pool208 = kAllKana;

  Map<String, KanaStat> strongNotDue(List<Kana> pool) => {
    for (final k in pool)
      k.id: KanaStat(
        seenCount: 20,
        correctCount: 20,
        srsLevel: 6,
        avgLatencyMs: 500,
        lastReviewedAt: start.subtract(const Duration(days: 1)),
        dueAt: start.add(const Duration(days: 30)),
      ),
  };

  Map<String, int> runSessions({
    required List<Kana> pool,
    required Map<String, KanaStat> stats,
    required int rounds,
    Duration step = const Duration(minutes: 5),
  }) {
    final counts = <String, int>{};
    for (var session = 0; session < rounds; session++) {
      final now = start.add(step * session);
      final items = DailySession.compose(
        pool: pool,
        stats: stats,
        newCandidates: const [],
        now: now,
        rng: Random(session),
      );
      for (final item in items) {
        final k = item.question.target;
        expect(pool.any((p) => p.id == k.id), isTrue);
        counts.update(k.character, (n) => n + 1, ifAbsent: () => 1);
        stats[k.id] = stats[k.id]!.recordAnswer(
          correct: true,
          at: now,
          latencyMs: 500,
        );
      }
    }
    return counts;
  }

  test('46 equally strong not-due: first four do not lock every session', () {
    final stats = strongNotDue(pool46);
    final counts = runSessions(pool: pool46, stats: stats, rounds: 10);

    expect(counts.values.reduce((a, b) => a + b), 120);
    expect(counts.length, greaterThan(40));
    for (final k in pool46.take(4)) {
      expect(
        counts[k.character] ?? 0,
        lessThan(10),
        reason: '${k.character} still occupied every weak slot',
      );
    }
    expect(
      pool46.take(4).every((k) => (counts[k.character] ?? 0) == 10),
      isFalse,
    );
  });

  test('cross-day coverage prefers kana not reviewed yesterday', () {
    final stats = strongNotDue(pool46);
    final day1 = DailySession.compose(
      pool: pool46,
      stats: stats,
      newCandidates: const [],
      now: start,
      rng: Random(0),
    );
    final day1Ids = {for (final i in day1) i.question.target.id};
    for (final i in day1) {
      stats[i.question.target.id] = stats[i.question.target.id]!.recordAnswer(
        correct: true,
        at: start,
        latencyMs: 500,
      );
    }
    final day2 = DailySession.compose(
      pool: pool46,
      stats: stats,
      newCandidates: const [],
      now: start.add(const Duration(days: 1)),
      rng: Random(1),
    );
    final day2Ids = {for (final i in day2) i.question.target.id};
    expect(day2Ids.intersection(day1Ids).length, lessThan(4));
  });

  test('four true weaks still occupy the weak quota across rounds', () {
    final stats = strongNotDue(pool46);
    final now = start;
    for (final c in ['か', 'き', 'く', 'け']) {
      stats[c] = KanaStat(
        seenCount: 20,
        correctCount: 8,
        wrongCount: 12,
        srsLevel: 1,
        avgLatencyMs: 1400,
        lastReviewedAt: now.subtract(const Duration(days: 2)),
        lastMistakeAt: now.subtract(const Duration(hours: 3)),
        dueAt: now.add(const Duration(days: 30)),
      );
    }
    final counts = runSessions(pool: pool46, stats: stats, rounds: 10);
    for (final c in ['か', 'き', 'く', 'け']) {
      expect(
        counts[c] ?? 0,
        greaterThanOrEqualTo(8),
        reason: 'true weak $c was under-served for uniformity',
      );
    }
  });

  test('few unlocked: compose stays inside the tiny learned pool', () {
    final small = pool46.take(5).toList();
    final stats = strongNotDue(small);
    final items = DailySession.compose(
      pool: small,
      stats: stats,
      newCandidates: const [],
      now: start,
      rng: Random(3),
    );
    expect(items.length, 5);
    for (final i in items) {
      expect(small.map((k) => k.id), contains(i.question.target.id));
    }
  });

  test('large due backlog still services at least kDue due items', () {
    final dueIds = pool46.take(40).map((k) => k.id).toSet();
    final stats = {
      for (final k in pool46)
        k.id: KanaStat(
          seenCount: 20,
          correctCount: 20,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: start.subtract(const Duration(days: 20)),
          dueAt: dueIds.contains(k.id)
              ? start.subtract(const Duration(days: 1))
              : start.add(const Duration(days: 30)),
        ),
    };
    var minDue = 12;
    for (var seed = 0; seed < 40; seed++) {
      final items = DailySession.compose(
        pool: pool46,
        stats: stats,
        newCandidates: const [],
        now: start,
        rng: Random(seed),
      );
      final duePicked = items
          .where((i) => dueIds.contains(i.question.target.id))
          .length;
      if (duePicked < minDue) minDue = duePicked;
    }
    expect(minDue, greaterThanOrEqualTo(DailySession.kDue));
  });

  test('mixed 208: targets stay in pool; no unlearned leak', () {
    final stats = <String, KanaStat>{};
    final rng = Random(208);
    for (final k in pool208) {
      if (rng.nextBool()) {
        stats[k.id] = KanaStat(
          seenCount: 8,
          correctCount: 6,
          wrongCount: 2,
          srsLevel: 2,
          avgLatencyMs: 700,
          lastReviewedAt: start.subtract(Duration(days: rng.nextInt(20))),
          lastMistakeAt: start.subtract(Duration(days: 2 + rng.nextInt(10))),
          dueAt: rng.nextBool()
              ? start.subtract(const Duration(hours: 3))
              : start.add(const Duration(days: 10)),
        );
      }
    }
    final items = DailySession.compose(
      pool: pool208,
      stats: stats,
      newCandidates: const [],
      now: start,
      rng: Random(11),
    );
    expect(items.length, 12);
    final poolIds = pool208.map((k) => k.id).toSet();
    for (final i in items) {
      expect(poolIds.contains(i.question.target.id), isTrue);
      if (i.question.direction == QuizDirection.kanaRecall) {
        expect(i.question.options, isEmpty);
      } else {
        expect(i.question.options.length, 4);
      }
    }
  });

  test('legacy 1/1000 miss on あいうえ does not lock 20 recovered sessions', () {
    final oldMistakes = pool46.take(4).map((k) => k.id).toSet();
    final stats = {
      for (final k in pool46)
        k.id: KanaStat(
          seenCount: 1000,
          correctCount: oldMistakes.contains(k.id) ? 999 : 1000,
          wrongCount: oldMistakes.contains(k.id) ? 1 : 0,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: start.subtract(const Duration(days: 1)),
          dueAt: start.add(const Duration(days: 30)),
        ),
    };
    final counts = runSessions(pool: pool46, stats: stats, rounds: 20);
    for (final id in oldMistakes) {
      expect(
        Weakness.isActionable(stats[id]!, now: start),
        isFalse,
        reason: '$id stayed actionable after recovered fast reviews',
      );
      expect(
        counts[id] ?? 0,
        lessThan(20),
        reason: '$id still occupied every weak slot',
      );
    }
    expect(oldMistakes.every((id) => (counts[id] ?? 0) == 20), isFalse);
    final remaining = counts.entries
        .where((e) => !oldMistakes.contains(e.key))
        .map((e) => e.value);
    expect(remaining, isNotEmpty);
    expect(remaining.reduce(min), greaterThanOrEqualTo(3));
  });

  test(
    'a 3-hour-old miss on otherwise recovered あいうえ still takes weak slots',
    () {
      final recent = pool46.take(4).map((k) => k.id).toSet();
      final stats = {
        for (final k in pool46)
          k.id: KanaStat(
            seenCount: 1000,
            correctCount: recent.contains(k.id) ? 999 : 1000,
            wrongCount: recent.contains(k.id) ? 1 : 0,
            srsLevel: 6,
            avgLatencyMs: 500,
            lastReviewedAt: start.subtract(const Duration(days: 1)),
            lastMistakeAt: recent.contains(k.id)
                ? start.subtract(const Duration(hours: 3))
                : null,
            dueAt: start.add(const Duration(days: 30)),
          ),
      };
      final counts = runSessions(pool: pool46, stats: stats, rounds: 10);
      for (final id in recent) {
        expect(Weakness.isActionable(stats[id]!, now: start), isTrue);
        expect(
          counts[id] ?? 0,
          greaterThanOrEqualTo(8),
          reason: 'recent miss $id was dropped from the weak quota',
        );
      }
    },
  );

  test(
    'year-old lastMistakeAt on recovered あいうえ does not lock 20 sessions',
    () {
      final oldMistakes = pool46.take(4).map((k) => k.id).toSet();
      final stats = {
        for (final k in pool46)
          k.id: KanaStat(
            seenCount: 1000,
            correctCount: oldMistakes.contains(k.id) ? 999 : 1000,
            wrongCount: oldMistakes.contains(k.id) ? 1 : 0,
            srsLevel: 6,
            avgLatencyMs: 500,
            lastReviewedAt: start.subtract(const Duration(days: 1)),
            lastMistakeAt: oldMistakes.contains(k.id)
                ? start.subtract(const Duration(days: 365))
                : null,
            dueAt: start.add(const Duration(days: 30)),
          ),
      };
      final counts = runSessions(pool: pool46, stats: stats, rounds: 20);
      for (final id in oldMistakes) {
        expect(Weakness.isActionable(stats[id]!, now: start), isFalse);
        expect(counts[id] ?? 0, lessThan(20));
      }
    },
  );

  test('shuffle is not the fix: equal-score weaks are empty, fill covers', () {
    final stats = strongNotDue(pool46);
    final items = DailySession.compose(
      pool: pool46,
      stats: stats,
      newCandidates: const [],
      now: start,
      rng: Random(0),
    );
    // A single session of all-strong items is just coverage fill — the
    // first four gojūon are not forced members.
    final ids = items.map((i) => i.question.target.character).toSet();
    expect(ids.containsAll(['あ', 'い', 'う', 'え']), isFalse);
  });
}
