// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';

import 'helpers/kana_orthography.dart';

/// Integrity of the hand-typed reading dataset — the value is catching typos in
/// kana / romaji / meaning, since this is content not code.
void main() {
  test('every word is non-empty and has a meaning', () {
    for (final w in kWords) {
      expect(w.kana, isNotEmpty, reason: w.romaji);
      expect(w.romaji, isNotEmpty, reason: w.kana);
      expect(w.meaning, isNotEmpty, reason: w.kana);
    }
  });

  test('every corpus word explicitly supplies a Japanese written form', () {
    for (final w in kWords) {
      expect(w.writtenForm, isNotNull, reason: w.kana);
      expect(w.writtenForm!.trim(), isNotEmpty, reason: w.kana);
      expect(w.progressId, 'word:${w.kana}');
      expect(w.displayText, w.kana);
      expect(w.gatingText, [w.kana]);
    }
  });

  test(
    'Japanese spellings are independent of Traditional Chinese meanings',
    () {
      const expected = {
        'くうこう': '空港',
        'えき': '駅',
        'ひこうき': '飛行機',
        'びょういん': '病院',
        'がっこう': '学校',
        'くすり': '薬',
        'かみ': '紙（紙）・髪（頭髮）',
        'はやい': '速い（快）・早い（早）',
        'やさしい': '優しい（溫柔）・易しい（簡單）',
        'とまる': '止まる（停下）・泊まる（過夜）',
        'コーヒー': 'コーヒー',
        'ください': 'ください',
        'エム': 'M',
      };
      for (final entry in expected.entries) {
        expect(
          kWords.singleWhere((w) => w.kana == entry.key).writtenForm,
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test('every word is orthographically clean for its script', () {
    // Script-pure units, curated small-vowel combos only, and legal
    // special-mora environments (no leading/trailing っ, ー only in katakana
    // after a lengthenable vowel, っ only before an obstruent).
    for (final w in kWords) {
      expect(
        validateKanaOrthography(w.kana, w.script),
        isEmpty,
        reason: w.kana,
      );
    }
  });

  test('romaji equals the canonical derived transcription (no typos)', () {
    // An orthography check against the app's transcription rules — sokuon
    // doubles the next consonant (っち → tch), chōonpu repeats the previous
    // vowel, ん before a vowel or y is n'. Not a pronunciation authority.
    for (final w in kWords) {
      final derived = deriveRomaji(w.kana, w.script);
      expect(
        w.romaji,
        derived,
        reason: '${w.kana}: stored "${w.romaji}" != derived "$derived"',
      );
    }
  });

  test('every word becomes readable with its full syllabary learned', () {
    // The gate understands special moras — nothing in the corpus can be
    // permanently locked out.
    for (final w in kWords) {
      final units = {
        for (final k in kAllKana)
          if (k.script == w.script) k.character,
      };
      expect(KanaTokenizer.isReadable(w.kana, units), isTrue, reason: w.kana);
    }
  });

  test('no duplicate words', () {
    final kanas = kWords.map((w) => w.kana).toList();
    expect(kanas.toSet().length, kanas.length);
  });
}
