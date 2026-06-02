// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/ferry_session.dart';

void main() {
  const words = [
    Word(kana: 'いぬ', romaji: 'inu', meaning: '狗'),
    Word(kana: 'きみ', romaji: 'kimi', meaning: '你', theme: ContentTheme.anime),
    Word(kana: 'やま', romaji: 'yama', meaning: '山'),
  ];
  final allChars = {'い', 'ぬ', 'き', 'み', 'や', 'ま'};

  test('themed (ear-known) words are ferried first', () {
    final out = FerrySession.compose(
      words: words,
      learnedChars: allChars,
      rng: Random(1),
      length: 3,
    );
    expect(out.length, 3);
    expect(out.first.kana, 'きみ'); // the themed one leads
  });

  test('gates by the learner\'s unlocked kana', () {
    final out = FerrySession.compose(
      words: words,
      learnedChars: {'き', 'み'},
      rng: Random(1),
    );
    expect(out.map((w) => w.kana), ['きみ']);
  });

  test('within a tier, least-recently-seen leads and most-recent trails', () {
    // All non-themed → same tier, so recency (not theme) decides the order.
    const tier = [
      Word(kana: 'いぬ', romaji: 'inu', meaning: '狗'),
      Word(kana: 'やま', romaji: 'yama', meaning: '山'),
      Word(kana: 'うみ', romaji: 'umi', meaning: '海'),
    ];
    final out = FerrySession.compose(
      words: tier,
      learnedChars: {'い', 'ぬ', 'や', 'ま', 'う', 'み'},
      rng: Random(1),
      length: 3,
      lastSeen: {'いぬ': 200, 'やま': 100}, // うみ never seen (absent → 0)
    );
    expect(out.first.kana, 'うみ'); // never-seen surfaces first
    expect(out.last.kana, 'いぬ'); // most-recently-seen sinks to the end
  });

  test('is deterministic under a fixed seed', () {
    List<Word> run() => FerrySession.compose(
      words: words,
      learnedChars: allChars,
      rng: Random(5),
      length: 3,
    );
    expect(run().map((w) => w.kana), run().map((w) => w.kana));
  });
}
