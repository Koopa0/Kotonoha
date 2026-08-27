// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';

bool _isKatakana(String s) => s.runes.every((r) => r >= 0x30A0 && r <= 0x30FF);
bool _isHiragana(String s) => s.runes.every((r) => r >= 0x3040 && r <= 0x309F);

void main() {
  test('110 single-character kanji, each with 1–2 readings', () {
    expect(kKanji.length, 110);
    for (final k in kKanji) {
      expect(k.char.runes.length, 1, reason: k.char);
      expect(k.meaningZh, isNotEmpty, reason: k.char);
      expect(k.readings.length, inInclusiveRange(1, 2), reason: k.char);
    }
  });

  test('on-yomi is katakana, kun-yomi is hiragana (no mis-tagging)', () {
    for (final k in kKanji) {
      for (final r in k.readings) {
        expect(r.text, isNotEmpty, reason: k.char);
        if (r.kind == ReadingKind.on) {
          expect(
            _isKatakana(r.text),
            isTrue,
            reason: '${k.char} on-yomi "${r.text}" is not katakana',
          );
        } else {
          expect(
            _isHiragana(r.text),
            isTrue,
            reason: '${k.char} kun-yomi "${r.text}" is not hiragana',
          );
        }
      }
    }
  });

  test('every reading id is unique', () {
    final ids = [for (final k in kKanji) ...k.readingIds];
    expect(ids.toSet().length, ids.length);
  });

  test('every reading carries an example word and gloss', () {
    for (final k in kKanji) {
      for (final r in k.readings) {
        expect(r.exampleWord, isNotNull, reason: '${k.char} ${r.text}');
        expect(r.exampleMeaning, isNotNull, reason: '${k.char} ${r.text}');
      }
    }
  });
}
