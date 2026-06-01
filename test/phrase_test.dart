// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

void main() {
  final hiragana = {
    for (final k in kAllKana)
      if (k.script == KanaScript.hiragana && k.character.runes.length == 1)
        k.character,
  };

  test('phrase characters exclude layout spaces', () {
    const p = Phrase(kana: 'そらが あおい', romaji: 'sora ga aoi', meaning: '天空是藍的');
    expect(p.characters.contains(' '), isFalse);
    expect(p.characters, {'そ', 'ら', 'が', 'あ', 'お', 'い'});
  });

  test('every phrase is built from real single-rune hiragana', () {
    for (final p in kPhrases) {
      expect(p.romaji, isNotEmpty, reason: p.kana);
      expect(p.meaning, isNotEmpty, reason: p.kana);
      for (final c in p.characters) {
        expect(hiragana.contains(c), isTrue, reason: '"$c" in ${p.kana}');
      }
    }
  });

  test('ReadingSet gates phrases by the learner\'s unlocked kana', () {
    final justSora = {'そ', 'ら', 'が', 'あ', 'お', 'い'};
    final readable = ReadingSet.readable(kPhrases, justSora);
    expect(readable.map((p) => p.kana), contains('そらが あおい'));
    expect(ReadingSet.readable(kPhrases, {'そ'}), isEmpty);
  });
}
