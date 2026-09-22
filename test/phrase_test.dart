// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

import 'helpers/kana_orthography.dart';

void main() {
  final allHiraganaUnits = {
    for (final k in kAllKana)
      if (k.script == KanaScript.hiragana) k.character,
  };

  test(
    'every phrase supplies a written form without changing kana identity',
    () {
      for (final phrase in kPhrases) {
        expect(phrase.writtenForm, isNotNull, reason: phrase.kana);
        expect(phrase.writtenForm!.trim(), isNotEmpty, reason: phrase.kana);
        expect(phrase.displayText, phrase.kana);
        expect(phrase.progressId, 'phrase:${phrase.kana}');
        expect(phrase.gatingText, [phrase.kana]);
      }
      expect(kPhrases.map((p) => p.progressId).toSet().length, kPhrases.length);
    },
  );

  test('written forms preserve sentence senses and normal kana usage', () {
    const expected = {
      'えきは どこ': '駅はどこ',
      'カードは つかえません': 'カードは使えません',
      'よやくが あります': '予約があります',
      'かぜが すずしい': '風が涼しい',
      'てがみを かく': '手紙を書く',
      'ただいま': 'ただいま',
      'この バスは くうこうに いきますか': 'このバスは空港に行きますか',
    };
    for (final entry in expected.entries) {
      expect(
        kPhrases.singleWhere((p) => p.kana == entry.key).writtenForm,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('phrase tokens exclude layout spaces', () {
    expect(KanaTokenizer.tokenize('そらが あおい'), ['そ', 'ら', 'が', 'あ', 'お', 'い']);
  });

  test('every phrase is orthographically clean for its scripts', () {
    final allUnits = {for (final k in kAllKana) k.character};
    for (final p in kPhrases) {
      expect(p.romaji, isNotEmpty, reason: p.kana);
      expect(p.meaning, isNotEmpty, reason: p.kana);
      final mixed = p.kana.runes.any((r) => r >= 0x30A0 && r <= 0x30FF);
      if (mixed) {
        expect(
          KanaTokenizer.isReadable(p.kana, allUnits),
          isTrue,
          reason: p.kana,
        );
        continue;
      }
      expect(
        validateKanaOrthography(p.kana, KanaScript.hiragana),
        isEmpty,
        reason: p.kana,
      );
    }
  });

  test('every phrase is readable once the full syllabary is learned', () {
    // The gate understands special moras (っ needs つ, digraph units gate as
    // themselves) — so with every unit learned, nothing in the corpus
    // can be permanently locked out. Mixed shop chunks need both scripts.
    final allUnits = {for (final k in kAllKana) k.character};
    for (final p in kPhrases) {
      final units = p.kana.runes.any((r) => r >= 0x30A0 && r <= 0x30FF)
          ? allUnits
          : allHiraganaUnits;
      expect(KanaTokenizer.isReadable(p.kana, units), isTrue, reason: p.kana);
    }
  });

  test("ReadingSet gates phrases by the learner's unlocked kana", () {
    final justSora = {'そ', 'ら', 'が', 'あ', 'お', 'い'};
    final readable = ReadingSet.readable(kPhrases, justSora);
    expect(readable.map((p) => p.kana), contains('そらが あおい'));
    expect(ReadingSet.readable(kPhrases, {'そ'}), isEmpty);
  });
}
