// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
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
      expect(i.question.options.length, 4);
      expect(i.question.options.toSet().length, 4);
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
}
