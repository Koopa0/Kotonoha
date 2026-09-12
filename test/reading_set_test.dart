// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

void main() {
  const words = [
    Word(kana: 'あい', romaji: 'ai', meaning: '愛'), // needs あ, い
    Word(kana: 'いぬ', romaji: 'inu', meaning: '狗'), // needs い, ぬ
    Word(kana: 'やま', romaji: 'yama', meaning: '山'), // needs や, ま
  ];
  final now = DateTime(2026, 8, 27, 9);

  WordStat seenStat({DateTime? dueAt, int level = 1}) => WordStat.fromJson({
    's': 3,
    'c': 3,
    'w': 0,
    'sl': level,
    if (dueAt != null) 'd': dueAt.millisecondsSinceEpoch,
  });

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
      now: now,
      length: 2,
      maxNew: 2,
    );
    final a = run();
    final b = run();
    expect(a.length, 2);
    expect(a.map((w) => w.kana), b.map((w) => w.kana)); // deterministic
    for (final w in a) {
      expect(KanaTokenizer.isReadable(w.kana, chars), isTrue);
    }
  });

  test('with no stats a session is only the paced trickle of new items', () {
    final out = ReadingSet.session(
      items: words,
      learnedChars: {'あ', 'い', 'ぬ', 'や', 'ま'},
      rng: Random(1),
      now: now,
      maxNew: 2,
    );
    // Three unseen candidates, but only maxNew board — and in dataset order
    // (the introduction order), so やま is the one left waiting.
    expect(out.length, 2);
    expect(out.map((w) => w.kana).toSet(), {'あい', 'いぬ'});
  });

  test('due items are always included, oldest due first when over length', () {
    final chars = {'あ', 'い', 'ぬ', 'や', 'ま'};
    final stats = {
      'word:あい': seenStat(dueAt: now.subtract(const Duration(days: 3))),
      'word:いぬ': seenStat(dueAt: now.subtract(const Duration(days: 9))),
      'word:やま': seenStat(dueAt: now.subtract(const Duration(days: 1))),
    };
    final out = ReadingSet.session(
      items: words,
      learnedChars: chars,
      rng: Random(2),
      now: now,
      stats: stats,
      length: 2,
    );
    // The two longest-overdue items are chosen (order then shuffled).
    expect(out.map((w) => w.kana).toSet(), {'いぬ', 'あい'});
  });

  test('the backlog gate: no new items while due alone fills the session', () {
    final chars = {'あ', 'い', 'ぬ', 'や', 'ま'};
    final stats = {
      'word:あい': seenStat(dueAt: now.subtract(const Duration(days: 1))),
      'word:いぬ': seenStat(dueAt: now.subtract(const Duration(days: 2))),
      // やま never seen.
    };
    final out = ReadingSet.session(
      items: words,
      learnedChars: chars,
      rng: Random(3),
      now: now,
      stats: stats,
      length: 2,
    );
    expect(out.map((w) => w.kana).toSet(), {'あい', 'いぬ'});
  });

  test('seen not-yet-due items fill the remainder, soonest due first', () {
    final chars = {'あ', 'い', 'ぬ', 'や', 'ま'};
    final stats = {
      'word:あい': seenStat(dueAt: now.add(const Duration(days: 30))),
      'word:いぬ': seenStat(dueAt: now.add(const Duration(days: 1))),
      'word:やま': seenStat(dueAt: now.add(const Duration(days: 7))),
    };
    final out = ReadingSet.session(
      items: words,
      learnedChars: chars,
      rng: Random(4),
      now: now,
      stats: stats,
      length: 2,
    );
    // Nothing due, nothing new — the two closest-to-due fill the session.
    expect(out.map((w) => w.kana).toSet(), {'いぬ', 'やま'});
  });

  // The 黙読 track flows the real phrase corpus through the SAME generic — guard
  // that Phrase composes a bounded, readable session too (not just Word).
  test('session is generic: it composes a readable Phrase session', () {
    final allChars = {
      for (final k in kAllKana)
        if (k.script == KanaScript.hiragana) k.character,
    };
    final out = ReadingSet.session(
      items: kPhrases,
      learnedChars: allChars,
      rng: Random(3),
      now: now,
      length: 5,
      maxNew: 5,
    );
    expect(out.length, 5);
    for (final p in out) {
      expect(KanaTokenizer.isReadable(p.kana, allChars), isTrue);
    }
  });

  test('takeIntro keeps catalog order and caps at introLength', () {
    const pool = [
      Word(kana: 'いち', romaji: 'ichi', meaning: '一'),
      Word(kana: 'に', romaji: 'ni', meaning: '二'),
      Word(kana: 'さん', romaji: 'san', meaning: '三'),
    ];
    expect(ReadingSet.takeIntro(pool, length: 2).map((w) => w.kana), [
      'いち',
      'に',
    ]);
    expect(ReadingSet.takeIntro(pool), pool);
    expect(ReadingSet.introLength, 8);
  });
}
