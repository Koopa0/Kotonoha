// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';

void main() {
  const all = kHiraganaGojuon;
  final now = DateTime(2026, 5, 31, 12);
  const noStats = <String, KanaStat>{};

  test('deterministic for a fixed Random + clock', () {
    List<String> run() =>
        DailySession.compose(
              pool: all,
              stats: noStats,
              newCandidates: const [],
              now: now,
              rng: Random(42),
            )
            .map(
              (i) =>
                  '${i.question.target.character}/${i.question.direction.name}',
            )
            .toList();
    expect(run(), run());
  });

  test('length clamps to pool size; empty pool yields empty', () {
    final small = DailySession.compose(
      pool: all.take(5).toList(),
      stats: noStats,
      newCandidates: const [],
      now: now,
      rng: Random(1),
    );
    expect(small.length, 5);
    expect(
      DailySession.compose(
        pool: const [],
        stats: noStats,
        newCandidates: const [],
        now: now,
        rng: Random(1),
      ),
      isEmpty,
    );
  });

  test('items are mode=daily, well-formed 4-option questions', () {
    final items = DailySession.compose(
      pool: all,
      stats: noStats,
      newCandidates: const [],
      now: now,
      rng: Random(2),
    );
    expect(items.length, 12);
    for (final i in items) {
      expect(i.mode, PracticeMode.daily);
      expect(i.question.direction, isNot(QuizDirection.kanaRecall));
      expect(i.question.options.length, 4);
      expect(i.question.options.toSet().length, 4);
    }
  });

  test('visual-strong unknown listening is probed as soundToKana', () {
    final stats = <String, KanaStat>{
      for (final k in all)
        k.id: KanaStat(
          seenCount: 20,
          correctCount: 20,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          dueAt: now.add(const Duration(days: 30)),
        ),
    };
    final items = DailySession.compose(
      pool: all,
      stats: stats,
      newCandidates: const [],
      now: now,
      rng: Random(4),
    );
    expect(items, isNotEmpty);
    for (final i in items) {
      expect(i.question.direction, QuizDirection.soundToKana);
      expect(i.question.options.length, 4);
    }
  });

  test('visual-strong with reliable listening stays kanaRecall', () {
    final heard = now.subtract(const Duration(days: 2));
    final stats = <String, KanaStat>{
      for (final k in all)
        k.id: KanaStat(
          seenCount: 20,
          correctCount: 20,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          dueAt: now.add(const Duration(days: 30)),
          listenSeenCount: 2,
          listenCorrectCount: 2,
          lastListenAt: heard,
        ),
    };
    final items = DailySession.compose(
      pool: all,
      stats: stats,
      newCandidates: const [],
      now: now,
      rng: Random(4),
    );
    expect(items, isNotEmpty);
    for (final i in items) {
      expect(i.question.direction, QuizDirection.kanaRecall);
      expect(i.question.options, isEmpty);
    }
  });

  test('recent miss keeps multiple-choice even when accuracy is high', () {
    final stats = <String, KanaStat>{
      for (final k in all)
        k.id: KanaStat(
          seenCount: 20,
          correctCount: 19,
          wrongCount: 1,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(hours: 1)),
          lastMistakeAt: now.subtract(const Duration(hours: 3)),
          dueAt: now.add(const Duration(days: 30)),
        ),
    };
    final items = DailySession.compose(
      pool: all.take(10).toList(),
      stats: stats,
      newCandidates: const [],
      now: now,
      rng: Random(5),
    );
    expect(items, isNotEmpty);
    for (final i in items) {
      expect(i.question.direction, isNot(QuizDirection.kanaRecall));
      expect(i.question.options.length, 4);
    }
  });

  test('new items stay kanaToRomaji even when the rest are recall-ready', () {
    final stats = <String, KanaStat>{
      for (final k in all)
        k.id: KanaStat(
          seenCount: 20,
          correctCount: 20,
          srsLevel: 6,
          avgLatencyMs: 500,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          dueAt: now.add(const Duration(days: 30)),
        ),
    };
    final neu = all.take(3).toList();
    final items = DailySession.compose(
      pool: all,
      stats: stats,
      newCandidates: neu,
      now: now,
      rng: Random(6),
    );
    final newIds = neu.map((k) => k.id).toSet();
    final newItems = items.where((i) => newIds.contains(i.question.target.id));
    expect(newItems, isNotEmpty);
    for (final i in newItems) {
      expect(i.question.direction, QuizDirection.kanaToRomaji);
      expect(i.question.options.length, 4);
    }
  });

  test(
    'distractors stay same-script (hiragana pool → no katakana options)',
    () {
      final items = DailySession.compose(
        pool: all,
        stats: noStats,
        newCandidates: const [],
        now: now,
        rng: Random(3),
      );
      bool isKatakana(int r) => r >= 0x30A0 && r <= 0x30FF;
      for (final i in items) {
        for (final o in i.question.options) {
          expect(o.runes.any(isKatakana), isFalse);
        }
      }
    },
  );

  test('quiet run never generates a listening prompt', () {
    for (var seed = 0; seed < 200; seed++) {
      final items = DailySession.compose(
        pool: all,
        stats: noStats,
        newCandidates: const [],
        now: now,
        rng: Random(seed),
        quiet: true,
      );
      for (final i in items) {
        expect(
          i.question.direction,
          isNot(QuizDirection.soundToKana),
          reason: 'seed=$seed leaked a listening prompt into a quiet run',
        );
      }
    }
  });

  test('the default (non-quiet) run still includes listening prompts', () {
    var sawListening = false;
    for (var seed = 0; seed < 30 && !sawListening; seed++) {
      final items = DailySession.compose(
        pool: all,
        stats: noStats,
        newCandidates: const [],
        now: now,
        rng: Random(seed),
      );
      sawListening = items.any(
        (i) => i.question.direction == QuizDirection.soundToKana,
      );
    }
    expect(sawListening, isTrue);
  });

  test('quiet does not break the new-item guard (always kanaToRomaji)', () {
    final items = DailySession.compose(
      pool: all,
      stats: noStats,
      newCandidates: all.take(3).toList(),
      now: now,
      rng: Random(7),
      quiet: true,
    );
    final newIds = all.take(3).map((k) => k.id).toSet();
    final newItems = items.where((i) => newIds.contains(i.question.target.id));
    // Not vacuous: the new items really do surface (added before the fill).
    expect(newItems, isNotEmpty);
    for (final i in newItems) {
      expect(i.question.direction, QuizDirection.kanaToRomaji);
    }
  });

  test('review distractors lean on the target\'s look-alike group', () {
    final byChar = {for (final k in all) k.character: k};
    // The first curated group containing [char], minus the char itself.
    List<String> siblingsOf(String char) {
      final set = kConfusableSets.firstWhere(
        (s) => s.contains(char),
        orElse: () => const [],
      );
      return [
        for (final c in set)
          if (c != char && byChar.containsKey(c)) c,
      ];
    }

    for (var seed = 0; seed < 100; seed++) {
      final items = DailySession.compose(
        pool: all,
        stats: noStats,
        newCandidates: const [],
        now: now,
        rng: Random(seed),
      );
      for (final i in items) {
        final q = i.question;
        // Reviews are glyph-answered (romajiToKana / soundToKana), so options
        // are kana characters — a sibling shows up as its own glyph. Guard the
        // assumption explicitly: kanaToRomaji (new-item) options are romaji, a
        // different alphabet, and never occur here (no new candidates).
        if (q.direction == QuizDirection.kanaToRomaji) continue;
        final siblings = siblingsOf(q.target.character);
        if (siblings.isEmpty) continue;
        expect(
          q.options.any(siblings.contains),
          isTrue,
          reason:
              'seed=$seed ${q.target.character} (${q.direction.name}) had no '
              'look-alike among $siblings — options ${q.options}',
        );
      }
    }
  });
}
