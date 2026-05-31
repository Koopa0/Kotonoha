// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';

void main() {
  group('hiragana gojūon dataset', () {
    test('contains exactly 46 kana', () {
      expect(kHiraganaGojuon.length, 46);
    });

    test('every entry is hiragana with non-empty romaji', () {
      for (final k in kHiraganaGojuon) {
        expect(k.script, KanaScript.hiragana);
        expect(k.character.isNotEmpty, isTrue);
        expect(k.romaji.isNotEmpty, isTrue);
      }
    });

    test('no duplicate characters and no duplicate romaji', () {
      final chars = kHiraganaGojuon.map((k) => k.character).toSet();
      final romaji = kHiraganaGojuon.map((k) => k.romaji).toSet();
      expect(chars.length, 46);
      expect(romaji.length, 46);
    });

    test('uses canonical Hepburn for the tricky kana', () {
      String romajiOf(String c) =>
          kHiraganaGojuon.firstWhere((k) => k.character == c).romaji;
      expect(romajiOf('し'), 'shi');
      expect(romajiOf('ち'), 'chi');
      expect(romajiOf('つ'), 'tsu');
      expect(romajiOf('ふ'), 'fu');
      expect(romajiOf('を'), 'wo');
      expect(romajiOf('ん'), 'n');
    });

    test('contains the complete expected character set', () {
      const expected =
          'あいうえお'
          'かきくけこ'
          'さしすせそ'
          'たちつてと'
          'なにぬねの'
          'はひふへほ'
          'まみむめも'
          'やゆよ'
          'らりるれろ'
          'わをん';
      final actual = kHiraganaGojuon.map((k) => k.character).join();
      expect(actual, expected);
    });

    test('row/column indices are within grid bounds', () {
      for (final k in kHiraganaGojuon) {
        expect(k.row, inInclusiveRange(0, kGojuonRowCount - 1));
        expect(k.column, inInclusiveRange(0, kGojuonColumnCount - 1));
      }
    });
  });

  group('katakana gojūon dataset', () {
    test('contains exactly 46 katakana, all katakana script', () {
      expect(kKatakanaGojuon.length, 46);
      for (final k in kKatakanaGojuon) {
        expect(k.script, KanaScript.katakana);
      }
    });

    test('romaji set matches hiragana (same sounds)', () {
      expect(
        kKatakanaGojuon.map((k) => k.romaji).toSet(),
        kHiraganaGojuon.map((k) => k.romaji).toSet(),
      );
    });

    test('contains the complete expected character set', () {
      const expected =
          'アイウエオ'
          'カキクケコ'
          'サシスセソ'
          'タチツテト'
          'ナニヌネノ'
          'ハヒフヘホ'
          'マミムメモ'
          'ヤユヨ'
          'ラリルレロ'
          'ワヲン';
      expect(kKatakanaGojuon.map((k) => k.character).join(), expected);
    });

    test('kAllKana is 208 kana with unique characters', () {
      expect(kAllKana.length, 208); // 92 gojūon + 116 extended
      expect(kAllKana.map((k) => k.character).toSet().length, 208);
    });
  });

  group('extended kana (dakuten / handakuten / yōon)', () {
    test('counts per script', () {
      expect(kHiraganaDakuten.length, 20);
      expect(kHiraganaHandakuten.length, 5);
      expect(kHiraganaYoon.length, 33);
      expect(kKatakanaDakuten.length, 20);
      expect(kKatakanaHandakuten.length, 5);
      expect(kKatakanaYoon.length, 33);
    });

    test('dakuten/handakuten reuse a valid base cell', () {
      for (final k in [
        ...kHiraganaDakuten,
        ...kHiraganaHandakuten,
        ...kKatakanaDakuten,
        ...kKatakanaHandakuten,
      ]) {
        expect(k.row, inInclusiveRange(0, 10));
        expect(k.column, inInclusiveRange(0, 4));
        expect(
          k.kind == KanaKind.dakuon || k.kind == KanaKind.handakuon,
          isTrue,
        );
        expect(k.isGojuon, isFalse);
      }
    });

    test('yōon are 2-codepoint, off-grid (row/col = -1)', () {
      for (final k in [...kHiraganaYoon, ...kKatakanaYoon]) {
        expect(k.row, -1);
        expect(k.column, -1);
        expect(k.character.runes.length, 2);
        expect(k.kind, KanaKind.yoon);
        expect(k.romaji.isNotEmpty, isTrue);
      }
    });

    test('gojūon lists stay exactly 46 (invariant preserved)', () {
      expect(kHiraganaGojuon.length, 46);
      expect(kKatakanaGojuon.length, 46);
    });
  });
}
