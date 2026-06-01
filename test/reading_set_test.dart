// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

void main() {
  const words = [
    Word(kana: 'あい', romaji: 'ai', meaning: '愛'), // needs あ, い
    Word(kana: 'いぬ', romaji: 'inu', meaning: '狗'), // needs い, ぬ
    Word(kana: 'やま', romaji: 'yama', meaning: '山'), // needs や, ま
  ];

  test('readable returns only words whose every kana is unlocked', () {
    expect(ReadingSet.readable(words, {'あ', 'い'}).map((w) => w.kana), ['あい']);
    expect(ReadingSet.readable(words, {'あ', 'い', 'ぬ'}).map((w) => w.kana), [
      'あい',
      'いぬ',
    ]);
    expect(ReadingSet.readable(words, {'や'}), isEmpty); // ま missing
    expect(ReadingSet.readable(words, const {}), isEmpty);
  });

  test('session is deterministic, bounded, and only readable words', () {
    final chars = {'あ', 'い', 'ぬ', 'や', 'ま'};
    List<Word> run() => ReadingSet.session(
      items: words,
      learnedChars: chars,
      rng: Random(7),
      length: 2,
    );
    final a = run();
    final b = run();
    expect(a.length, 2);
    expect(a.map((w) => w.kana), b.map((w) => w.kana)); // deterministic
    for (final w in a) {
      expect(w.characters.every(chars.contains), isTrue);
    }
  });

  test('session length clamps to the readable supply', () {
    final out = ReadingSet.session(
      items: words,
      learnedChars: {'あ', 'い'},
      rng: Random(1),
    );
    expect(out.length, 1); // only あい is readable
  });
}
