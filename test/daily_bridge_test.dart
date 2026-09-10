// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';

void main() {
  final now = DateTime(2026, 9, 10, 10);
  final byChar = {for (final k in kAllKana) k.character: k};

  Kana kana(String ch) => byChar[ch]!;

  WordStat seen({int level = 1}) => WordStat(
    seenCount: 2,
    correctCount: 2,
    srsLevel: level,
    lastReviewedAt: now.subtract(const Duration(days: 2)),
    dueAt: now.subtract(const Duration(hours: 1)),
  );

  Set<String> charsFor(String text) => KanaTokenizer.tokenize(text).toSet();

  test('newbie with no seen words gets no transfer (no cold word test)', () {
    final items = DailyBridge.compose(
      sessionKana: [kana('ホ'), kana('テ'), kana('ル')],
      words: kWords,
      phrases: kPhrases,
      learnedChars: {
        for (final k in kAllKana)
          if (k.script == KanaScript.katakana) k.character,
      },
      wordStats: const {},
      now: now,
      rng: Random(1),
    );
    expect(items, isEmpty);
  });

  test('unreadable seen word is not transferred', () {
    const hotel = Word(
      kana: 'ホテル',
      romaji: 'hoteru',
      meaning: '飯店',
      script: KanaScript.katakana,
    );
    final items = DailyBridge.compose(
      sessionKana: [kana('ホ')],
      words: const [hotel],
      phrases: const [],
      learnedChars: {'ア'}, // ホテル needs ホ/テ/ル
      wordStats: {'word:ホテル': seen()},
      now: now,
      rng: Random(2),
    );
    expect(items, isEmpty);
  });

  test('seen readable word containing the session kana is transferred', () {
    const hotel = Word(
      kana: 'ホテル',
      romaji: 'hoteru',
      meaning: '飯店',
      script: KanaScript.katakana,
    );
    final items = DailyBridge.compose(
      sessionKana: [kana('ホ')],
      words: const [hotel],
      phrases: const [],
      learnedChars: charsFor('ホテル'),
      wordStats: {'word:ホテル': seen()},
      now: now,
      rng: Random(3),
    );
    expect(items.map((i) => i.progressId), ['word:ホテル']);
  });

  test('an unseen readable word is never the transfer target', () {
    const hotel = Word(
      kana: 'ホテル',
      romaji: 'hoteru',
      meaning: '飯店',
      script: KanaScript.katakana,
    );
    const mask = Word(
      kana: 'マスク',
      romaji: 'masuku',
      meaning: '口罩',
      script: KanaScript.katakana,
    );
    final items = DailyBridge.compose(
      sessionKana: [kana('マ')],
      words: const [hotel, mask],
      phrases: const [],
      learnedChars: {...charsFor('ホテル'), ...charsFor('マスク')},
      wordStats: {'word:ホテル': seen()},
      now: now,
      rng: Random(4),
    );
    expect(items.map((i) => i.displayText), isNot(contains('マスク')));
  });

  test('a readable new sentence may board after a seen word', () {
    const hotel = Word(
      kana: 'ホテル',
      romaji: 'hoteru',
      meaning: '飯店',
      script: KanaScript.katakana,
    );
    const phrase = Phrase(
      kana: 'じんじゃは どこ',
      romaji: 'jinja wa doko',
      meaning: '神社在哪裡',
    );
    final learned = {...charsFor('ホテル'), ...charsFor(phrase.kana)};
    final items = DailyBridge.compose(
      sessionKana: [kana('ホ'), kana('じ')],
      words: const [hotel],
      phrases: const [phrase],
      learnedChars: learned,
      wordStats: {'word:ホテル': seen()},
      now: now,
      rng: Random(5),
    );
    expect(items.length, 2);
    expect(items.first.progressId, 'word:ホテル');
    expect(items.last.progressId, 'phrase:じんじゃは どこ');
    expect(items.last, isA<Phrase>());
  });

  test('excludeProgressIds blocks a mechanical もう一回 replay', () {
    const hotel = Word(
      kana: 'ホテル',
      romaji: 'hoteru',
      meaning: '飯店',
      script: KanaScript.katakana,
    );
    const towel = Word(
      kana: 'タオル',
      romaji: 'taoru',
      meaning: '毛巾',
      script: KanaScript.katakana,
    );
    final learned = {...charsFor('ホテル'), ...charsFor('タオル')};
    final stats = {'word:ホテル': seen(), 'word:タオル': seen()};
    final first = DailyBridge.compose(
      sessionKana: [kana('ホ'), kana('タ')],
      words: const [hotel, towel],
      phrases: const [],
      learnedChars: learned,
      wordStats: stats,
      now: now,
      rng: Random(8),
    );
    expect(first, isNotEmpty);
    final second = DailyBridge.compose(
      sessionKana: [kana('ホ'), kana('タ')],
      words: const [hotel, towel],
      phrases: const [],
      learnedChars: learned,
      wordStats: stats,
      now: now,
      rng: Random(8),
      excludeProgressIds: {for (final i in first) i.progressId},
    );
    expect(second, isNotEmpty);
    expect(
      second.first.progressId,
      isNot(first.first.progressId),
      reason: 'same seed + exclude must 換詞, not restamp the batch',
    );
  });

  test(
    'when every eligible id is excluded, compose wraps instead of emptying',
    () {
      const hotel = Word(
        kana: 'ホテル',
        romaji: 'hoteru',
        meaning: '飯店',
        script: KanaScript.katakana,
      );
      const towel = Word(
        kana: 'タオル',
        romaji: 'taoru',
        meaning: '毛巾',
        script: KanaScript.katakana,
      );
      final learned = {...charsFor('ホテル'), ...charsFor('タオル')};
      final stats = {'word:ホテル': seen(), 'word:タオル': seen()};
      final wrapped = DailyBridge.compose(
        sessionKana: [kana('ホ'), kana('タ')],
        words: const [hotel, towel],
        phrases: const [],
        learnedChars: learned,
        wordStats: stats,
        now: now,
        rng: Random(8),
        excludeProgressIds: {'word:ホテル', 'word:タオル'},
      );
      expect(wrapped, isNotEmpty);
      expect(wrapped.first.progressId, anyOf('word:ホテル', 'word:タオル'));
      expect(
        DailyBridge.shouldRenew(wrapped.first.progressId, {
          'word:ホテル',
          'word:タオル',
        }),
        isFalse,
      );
    },
  );

  test('containsUnit sees a kana inside a loanword', () {
    expect(DailyBridge.containsUnit('ホテル', 'ホ'), isTrue);
    expect(DailyBridge.containsUnit('ホテル', 'テ'), isTrue);
    expect(DailyBridge.containsUnit('マスク', 'ホ'), isFalse);
    expect(DailyBridge.containsUnit('じんじゃは どこ', 'じ'), isTrue);
  });

  test('first-batch travel words and sentences stay unique and gated', () {
    final wordKanas = kWords.map((w) => w.kana).toList();
    expect(wordKanas.where((k) => k == 'ホテル').length, 1);
    expect(wordKanas.where((k) => k == 'レストラン').length, 1);
    expect(wordKanas.where((k) => k == 'カメラ').length, 1);
    expect(wordKanas.where((k) => k == 'タオル').length, 1);
    expect(wordKanas, containsAll(['マスク', 'ナイフ']));
    expect(wordKanas.toSet().length, wordKanas.length);

    const added = {
      'じんじゃは どこ',
      'しずかな てらに はいる',
      'ふるい おしろが みえる',
      'この ふくは ちいさい',
      'あかい ふくを かう',
      'いりぐちで ならぶ',
      'にもつは だいじょうぶ',
      'たすけて ください',
    };
    final phraseKanas = kPhrases.map((p) => p.kana).toList();
    expect(phraseKanas.toSet().length, phraseKanas.length);
    expect(added.length, 8);
    expect(phraseKanas.toSet().intersection(added), added);

    final allUnits = {for (final k in kAllKana) k.character};
    for (final p in kPhrases.where((p) => added.contains(p.kana))) {
      expect(
        KanaTokenizer.isReadable(p.kana, allUnits),
        isTrue,
        reason: p.kana,
      );
    }
    for (final w in kWords.where((w) => w.kana == 'マスク' || w.kana == 'ナイフ')) {
      expect(
        KanaTokenizer.isReadable(w.kana, allUnits),
        isTrue,
        reason: w.kana,
      );
    }
  });
}
