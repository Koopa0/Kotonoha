// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/use_cases/insights.dart';

void main() {
  Attempt a(
    String item, {
    required bool correct,
    int rt = 0,
    String mode = 'daily',
  }) => Attempt(
    ts: 1,
    itemId: item,
    mode: mode,
    correct: correct,
    rtMs: rt,
    sessionId: 's',
  );

  test('empty stream summarises to zeros', () {
    final s = Insights.summarize(const []);
    expect(s.total, 0);
    expect(s.correct, 0);
    expect(s.accuracy, 0);
    expect(s.avgRtMs, isNull);
    expect(s.perMode, isEmpty);
    expect(s.distinctItems, 0);
  });

  test('counts, accuracy, distinct items, and per-mode tallies', () {
    final s = Insights.summarize([
      a('あ', correct: true, rt: 400),
      a('あ', correct: false, rt: 600, mode: 'confusable'),
      a('か', correct: true, rt: 800),
      a('いぬ', correct: true, mode: 'reading'), // untimed (rt 0)
    ]);
    expect(s.total, 4);
    expect(s.correct, 3);
    expect(s.accuracy, closeTo(0.75, 1e-9));
    expect(s.distinctItems, 3); // あ, か, いぬ
    expect(s.perMode, {'daily': 2, 'confusable': 1, 'reading': 1});
  });

  test('avgRtMs averages only timed attempts (rt > 0)', () {
    final s = Insights.summarize([
      a('あ', correct: true, rt: 400),
      a('か', correct: true, rt: 800),
      a('いぬ', correct: true, mode: 'reading'), // rt 0 — excluded
    ]);
    expect(s.avgRtMs, 600); // (400 + 800) / 2, the rt-0 one ignored
  });
}
