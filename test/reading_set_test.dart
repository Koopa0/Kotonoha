// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/season.dart';
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

  // The 黙読 track flows the real phrase corpus through the SAME generic — guard
  // that Phrase composes a bounded, readable session too (not just Word).
  test('session is generic: it composes a readable Phrase session', () {
    final allChars = {for (final p in kPhrases) ...p.characters};
    final out = ReadingSet.session(
      items: kPhrases,
      learnedChars: allChars,
      rng: Random(3),
      length: 5,
    );
    expect(out.length, 5);
    for (final p in out) {
      expect(p.characters.every(allChars.contains), isTrue);
    }
  });

  test('Season.forMonth maps each month to its season', () {
    expect(Season.forMonth(4), Season.spring);
    expect(Season.forMonth(7), Season.summer);
    expect(Season.forMonth(10), Season.autumn);
    expect(Season.forMonth(1), Season.winter);
    expect(Season.forMonth(12), Season.winter);
  });

  test('seasonal-lift floats in-season + season-neutral above off-season', () {
    const phrases = [
      Phrase(kana: 'ふゆ', romaji: 'fuyu', meaning: '冬', season: Season.winter),
      Phrase(kana: 'なつ', romaji: 'natsu', meaning: '夏', season: Season.summer),
      Phrase(kana: 'そら', romaji: 'sora', meaning: '天'), // season-neutral
    ];
    final out = ReadingSet.session(
      items: phrases,
      learnedChars: {'ふ', 'ゆ', 'な', 'つ', 'そ', 'ら'},
      rng: Random(1),
      length: 3,
      season: Season.winter,
    );
    // Winter (in-season) + そら (neutral) lead; summer sinks last — never excluded.
    expect(out.last.kana, 'なつ');
    expect(out.take(2).map((p) => p.kana), containsAll(['ふゆ', 'そら']));
  });

  test('novelty-bias surfaces never-seen, then least-recently-seen', () {
    const words = [
      Word(kana: 'あ', romaji: 'a', meaning: 'a'),
      Word(kana: 'い', romaji: 'i', meaning: 'i'),
      Word(kana: 'う', romaji: 'u', meaning: 'u'),
    ];
    final out = ReadingSet.session(
      items: words,
      learnedChars: {'あ', 'い', 'う'},
      rng: Random(1),
      length: 3,
      lastSeen: {'あ': 1000, 'い': 100}, // う never seen
    );
    expect(out.first.kana, 'う'); // never-seen first
    expect(out.last.kana, 'あ'); // most-recently-seen last
  });
}
