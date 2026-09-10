// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

/// Regression for #50: visual fluency on the shared [KanaStat] must not hide
/// an unverified sound direction. The production counts below are a
/// composer＋stat counterexample, not a claim about a real learner.
void main() {
  const pool = kHiraganaGojuon;
  final now = DateTime(2026, 9, 10, 12);

  /// End state of the documented 24 quiet visual days: 46 learned hiragana,
  /// many romajiToKana / kanaRecall, zero scored hears.
  Map<String, KanaStat> visualReadyUnknown() => {
    for (final k in pool)
      k.id: KanaStat(
        seenCount: 6,
        correctCount: 6,
        srsLevel: 6,
        avgLatencyMs: 500,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
        dueAt: now.add(const Duration(days: 30)),
      ),
  };

  Map<QuizDirection, int> countDirections({
    required Map<String, KanaStat> stats,
    required bool quiet,
    int rounds = 20,
  }) {
    final counts = <QuizDirection, int>{};
    for (var session = 0; session < rounds; session++) {
      final items = DailySession.compose(
        pool: pool,
        stats: stats,
        newCandidates: const [],
        now: now.add(Duration(minutes: session)),
        rng: Random(session),
        quiet: quiet,
      );
      expect(items.length, 12);
      for (final item in items) {
        expect(pool.any((p) => p.id == item.question.target.id), isTrue);
        counts.update(item.question.direction, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  test(
    'production visual-only history: ordinary daily still probes listening',
    () {
      final counts = countDirections(stats: visualReadyUnknown(), quiet: false);
      final sound = counts[QuizDirection.soundToKana] ?? 0;
      final recall = counts[QuizDirection.kanaRecall] ?? 0;
      expect(sound, 240);
      expect(recall, 0);
      expect(counts[QuizDirection.romajiToKana] ?? 0, 0);
    },
  );

  test('quiet never plays sound and keeps silent recall, not easy MCQ', () {
    final counts = countDirections(stats: visualReadyUnknown(), quiet: true);
    expect(counts[QuizDirection.soundToKana] ?? 0, 0);
    expect(counts[QuizDirection.kanaRecall], 240);
    expect(counts[QuizDirection.romajiToKana] ?? 0, 0);
  });

  test('reliable listening evidence returns visual-strong items to recall', () {
    final heard = now.subtract(const Duration(days: 3));
    final stats = {
      for (final k in pool)
        k.id: KanaStat(
          seenCount: 6,
          correctCount: 6,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          dueAt: now.add(const Duration(days: 30)),
          listenSeenCount: 2,
          listenCorrectCount: 2,
          lastListenAt: heard,
        ),
    };
    final counts = countDirections(stats: stats, quiet: false);
    expect(counts[QuizDirection.kanaRecall], 240);
    expect(counts[QuizDirection.soundToKana] ?? 0, 0);
  });

  test('quiet plus a recent listening miss stays visual, never sound', () {
    final stats = {
      for (final k in pool)
        k.id: KanaStat(
          seenCount: 8,
          correctCount: 6,
          wrongCount: 2,
          srsLevel: 0,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(hours: 1)),
          lastMistakeAt: now.subtract(const Duration(hours: 1)),
          dueAt: now.add(const Duration(minutes: 10)),
          listenSeenCount: 3,
          listenCorrectCount: 2,
          listenWrongCount: 1,
          lastListenAt: now.subtract(const Duration(hours: 1)),
          lastListenMistakeAt: now.subtract(const Duration(hours: 1)),
        ),
    };
    final counts = countDirections(stats: stats, quiet: true, rounds: 5);
    expect(counts[QuizDirection.soundToKana] ?? 0, 0);
    expect(counts[QuizDirection.romajiToKana], 60);
  });

  test('a recent listening miss keeps probing sound, not recall', () {
    final stats = {
      for (final k in pool)
        k.id: KanaStat(
          seenCount: 8,
          correctCount: 6,
          wrongCount: 2,
          srsLevel: 0,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(hours: 1)),
          lastMistakeAt: now.subtract(const Duration(hours: 1)),
          dueAt: now.add(const Duration(minutes: 10)),
          listenSeenCount: 3,
          listenCorrectCount: 2,
          listenWrongCount: 1,
          lastListenAt: now.subtract(const Duration(hours: 1)),
          lastListenMistakeAt: now.subtract(const Duration(hours: 1)),
        ),
    };
    final counts = countDirections(stats: stats, quiet: false, rounds: 5);
    expect(counts[QuizDirection.soundToKana], 60);
    expect(counts[QuizDirection.kanaRecall] ?? 0, 0);
  });

  test('unknown listening is not a miss and does not deduct fluency', () {
    final stat = visualReadyUnknown()[pool.first.id]!;
    expect(stat.listeningUnknown, isTrue);
    expect(stat.hasRecentListeningMiss(now: now), isFalse);
    expect(DailySession.readyForRecall(stat, now: now), isTrue);
    expect(Weakness.isActionable(stat, now: now), isFalse);
  });

  test('due, learned-range, and new-item guards still hold after probes', () {
    final stats = visualReadyUnknown();
    final neu = pool.take(3).toList();
    final dueIds = pool.skip(10).take(7).map((k) => k.id).toSet();
    for (final id in dueIds) {
      final s = stats[id]!;
      stats[id] = KanaStat(
        seenCount: s.seenCount,
        correctCount: s.correctCount,
        srsLevel: s.srsLevel,
        avgLatencyMs: s.avgLatencyMs,
        lastReviewedAt: now.subtract(const Duration(days: 8)),
        dueAt: now.subtract(const Duration(hours: 1)),
      );
    }
    final items = DailySession.compose(
      pool: pool,
      stats: stats,
      newCandidates: neu,
      now: now,
      rng: Random(3),
    );
    final ids = items.map((i) => i.question.target.id).toSet();
    expect(ids.length, items.length);
    expect(ids.intersection(dueIds), isNotEmpty);
    final newIds = neu.map((k) => k.id).toSet();
    final newItems = items.where((i) => newIds.contains(i.question.target.id));
    expect(newItems, isNotEmpty);
    for (final i in newItems) {
      expect(i.question.direction, QuizDirection.kanaToRomaji);
    }
    for (final i in items) {
      expect(pool.any((p) => p.id == i.question.target.id), isTrue);
    }
    for (final i in items.where(
      (i) => !newIds.contains(i.question.target.id),
    )) {
      expect(i.question.direction, QuizDirection.soundToKana);
    }
  });
}
