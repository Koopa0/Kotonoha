// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/ferry_session.dart';

void main() {
  const words = [
    Word(kana: 'あい', romaji: 'ai', meaning: '愛'),
    Word(kana: 'いぬ', romaji: 'inu', meaning: '狗'),
    Word(
      kana: 'やま',
      romaji: 'yama',
      meaning: '山',
      theme: ContentTheme.yorushika,
    ),
    Word(kana: 'ゆめ', romaji: 'yume', meaning: '夢'),
  ];
  final chars = {'あ', 'い', 'ぬ', 'や', 'ま', 'ゆ', 'め'};
  final now = DateTime(2026, 8, 27, 9);

  WordStat seenAt(DateTime last) => WordStat.fromJson({
    's': 2,
    'c': 2,
    'w': 0,
    'sl': 1,
    'l': last.millisecondsSinceEpoch,
  });

  test('unseen words board first — themed ahead, then dataset order', () {
    final out = FerrySession.compose(
      words: words,
      learnedChars: chars,
      rng: Random(5),
      now: now,
      maxNew: 2,
    );
    // All four are unseen; only maxNew board: the themed やま first, then the
    // earliest by dataset order (あい).
    expect(out.length, 2);
    expect(out.map((w) => w.kana).toSet(), {'やま', 'あい'});
  });

  test('the boat fills with seen words, longest-unheard first', () {
    final stats = {
      'word:あい': seenAt(now.subtract(const Duration(days: 1))),
      'word:いぬ': seenAt(now.subtract(const Duration(days: 20))),
      'word:やま': seenAt(now.subtract(const Duration(days: 5))),
      // ゆめ unseen.
    };
    final out = FerrySession.compose(
      words: words,
      learnedChars: chars,
      rng: Random(6),
      now: now,
      stats: stats,
      length: 3,
      maxNew: 1,
    );
    // 1 new (ゆめ) + the two longest-unheard seen words.
    expect(out.map((w) => w.kana).toSet(), {'ゆめ', 'いぬ', 'やま'});
  });

  test('gates by readable kana and stays deterministic', () {
    List<Word> run() => FerrySession.compose(
      words: words,
      learnedChars: {'あ', 'い'}, // only あい readable
      rng: Random(9),
      now: now,
    );
    expect(run().map((w) => w.kana), ['あい']);
    expect(run().map((w) => w.kana), run().map((w) => w.kana));
  });
}
