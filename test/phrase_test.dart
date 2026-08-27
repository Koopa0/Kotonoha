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

  test('phrase tokens exclude layout spaces', () {
    expect(KanaTokenizer.tokenize('そらが あおい'), ['そ', 'ら', 'が', 'あ', 'お', 'い']);
  });

  test('every phrase is orthographically clean hiragana', () {
    for (final p in kPhrases) {
      expect(p.romaji, isNotEmpty, reason: p.kana);
      expect(p.meaning, isNotEmpty, reason: p.kana);
      expect(
        validateKanaOrthography(p.kana, KanaScript.hiragana),
        isEmpty,
        reason: p.kana,
      );
    }
  });

  test('every phrase is readable once the full syllabary is learned', () {
    // The gate understands special moras (っ needs つ, digraph units gate as
    // themselves) — so with every hiragana unit learned, nothing in the corpus
    // can be permanently locked out.
    for (final p in kPhrases) {
      expect(
        KanaTokenizer.isReadable(p.kana, allHiraganaUnits),
        isTrue,
        reason: p.kana,
      );
    }
  });

  test("ReadingSet gates phrases by the learner's unlocked kana", () {
    final justSora = {'そ', 'ら', 'が', 'あ', 'お', 'い'};
    final readable = ReadingSet.readable(kPhrases, justSora);
    expect(readable.map((p) => p.kana), contains('そらが あおい'));
    expect(ReadingSet.readable(kPhrases, {'そ'}), isEmpty);
  });
}
