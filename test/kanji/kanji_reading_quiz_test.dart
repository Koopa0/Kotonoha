// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_reading_quiz.dart';

/// The honest "choose the reading" beat: pick the kana reading, with distractors
/// that are real same-kind readings of OTHER kanji — so owning the meaning gives
/// no edge and the on/kun script never gives the answer away.
void main() {
  const pool = [
    KanjiEntry(
      char: '月',
      meaningZh: '月',
      readings: [
        Reading(text: 'つき', kind: ReadingKind.kun),
        Reading(text: 'ゲツ', kind: ReadingKind.on),
      ],
    ),
    KanjiEntry(
      char: '山',
      meaningZh: '山',
      readings: [
        Reading(text: 'やま', kind: ReadingKind.kun),
        Reading(text: 'サン', kind: ReadingKind.on),
      ],
    ),
    KanjiEntry(
      char: '川',
      meaningZh: '川',
      readings: [Reading(text: 'かわ', kind: ReadingKind.kun)],
    ),
    KanjiEntry(
      char: '火',
      meaningZh: '火',
      readings: [
        Reading(text: 'ひ', kind: ReadingKind.kun),
        Reading(text: 'カ', kind: ReadingKind.on),
      ],
    ),
  ];
  const target = KanjiEntry(
    char: '月',
    meaningZh: '月',
    readings: [
      Reading(text: 'つき', kind: ReadingKind.kun),
      Reading(text: 'ゲツ', kind: ReadingKind.on),
    ],
  );
  const kun = Reading(text: 'つき', kind: ReadingKind.kun);
  const on = Reading(text: 'ゲツ', kind: ReadingKind.on);

  test('answer appears exactly once and correctIndex points at it', () {
    final q = const KanjiReadingQuiz().buildQuestion(
      target,
      kun,
      pool,
      Random(1),
    );
    expect(q.options.where((o) => o == 'つき').length, 1);
    expect(q.options[q.correctIndex], 'つき');
    expect(q.answer, 'つき');
    expect(q.options.length, 4);
  });

  test('distractors are same-kind readings of OTHER kanji only', () {
    final q = const KanjiReadingQuiz().buildQuestion(
      target,
      kun,
      pool,
      Random(2),
    );
    final distractors = [...q.options]..remove('つき');
    for (final d in distractors) {
      expect(['やま', 'かわ', 'ひ'].contains(d), isTrue, reason: d);
    }
    expect(q.options.contains('ゲツ'), isFalse); // not 月's own on-reading
  });

  test('deterministic under a seeded Random', () {
    final a = const KanjiReadingQuiz().buildQuestion(
      target,
      kun,
      pool,
      Random(7),
    );
    final b = const KanjiReadingQuiz().buildQuestion(
      target,
      kun,
      pool,
      Random(7),
    );
    expect(a.options, b.options);
    expect(a.correctIndex, b.correctIndex);
  });

  test('clamps options when same-kind distractors are scarce', () {
    // Only サン and カ are on-readings of other kanji → answer + 2 = 3 options.
    final q = const KanjiReadingQuiz().buildQuestion(
      target,
      on,
      pool,
      Random(1),
    );
    expect(q.options.length, 3);
    expect(q.options.contains('サン'), isTrue);
    expect(q.options.contains('カ'), isTrue);
  });
}
