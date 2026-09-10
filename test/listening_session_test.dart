// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/listening_session.dart';

void main() {
  final allChars = {for (final kana in kAllKana) kana.character};

  test('T01 pool resolves every listed id from the shipped corpus', () {
    final ids = ListeningSession.pool().map((i) => i.progressId).toSet();
    expect(ids, ListeningSession.t01ProgressIds.toSet());
    expect(ListeningSession.t01ProgressIds.toSet().length, ids.length);
    for (final id in ListeningSession.t01ProgressIds) {
      expect(
        [...kWords, ...kPhrases].where((i) => i.progressId == id),
        hasLength(1),
        reason: 'T01 id must exist exactly once: $id',
      );
    }
  });

  test('hasReadyItems is false until a T01 item has been met', () {
    expect(
      ListeningSession.hasReadyItems(learnedChars: allChars, stats: const {}),
      isFalse,
    );
    expect(
      ListeningSession.hasReadyItems(
        learnedChars: allChars,
        stats: {
          'word:えき': WordStat.fromJson({'s': 1, 'c': 1, 'w': 0, 'sl': 1}),
        },
      ),
      isTrue,
    );
  });

  test('compose never introduces unseen items', () {
    final now = DateTime(2026, 9, 10, 12);
    final seen = {
      'phrase:えきは どこ': WordStat.fromJson({
        's': 2,
        'c': 2,
        'w': 0,
        'sl': 1,
        'd': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      }),
      'phrase:もういちど いってください': WordStat.fromJson({
        's': 1,
        'c': 1,
        'w': 0,
        'sl': 1,
      }),
    };
    final items = ListeningSession.compose(
      learnedChars: allChars,
      rng: Random(4),
      now: now,
      stats: seen,
    );
    expect(items, isNotEmpty);
    expect(items.length, lessThanOrEqualTo(ListeningSession.length));
    expect(
      items.map((i) => i.progressId).toSet(),
      everyElement(isIn(seen.keys)),
    );
  });

  test('compose is empty when nothing in T01 has been met', () {
    expect(
      ListeningSession.compose(
        learnedChars: allChars,
        rng: Random(1),
        now: DateTime(2026, 9, 10),
      ),
      isEmpty,
    );
  });
}
