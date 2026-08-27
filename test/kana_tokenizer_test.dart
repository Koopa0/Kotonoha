// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';

import 'helpers/kana_orthography.dart';

void main() {
  group('tokenize', () {
    test('plain kana split rune by rune', () {
      expect(KanaTokenizer.tokenize('いぬ'), ['い', 'ぬ']);
    });

    test('yōon digraphs stay one token (greedy)', () {
      expect(KanaTokenizer.tokenize('しゃしん'), ['しゃ', 'し', 'ん']);
      expect(KanaTokenizer.tokenize('きゃく'), ['きゃ', 'く']);
    });

    test('sokuon and chōonpu are their own tokens', () {
      expect(KanaTokenizer.tokenize('がっこう'), ['が', 'っ', 'こ', 'う']);
      expect(KanaTokenizer.tokenize('コーヒー'), ['コ', 'ー', 'ヒ', 'ー']);
    });

    test('small-vowel combinations attach to their base', () {
      expect(KanaTokenizer.tokenize('ファン'), ['ファ', 'ン']);
      expect(KanaTokenizer.tokenize('パーティー'), ['パ', 'ー', 'ティ', 'ー']);
    });

    test('punctuation is dropped — it is read as a pause, never sounded', () {
      // Punctuation rides inside a plain-kana segment (んで、) so a sentence
      // can use natural Japanese commas without the gate treating them as an
      // unlearnable unit.
      expect(KanaTokenizer.tokenize('んで、'), ['ん', 'で']);
      expect(KanaTokenizer.tokenize('はい。'), ['は', 'い']);
      expect(KanaTokenizer.isReadable('んで、', {'ん', 'で'}), isTrue);
    });

    test('layout spaces are dropped', () {
      expect(KanaTokenizer.tokenize('そらが あおい'), ['そ', 'ら', 'が', 'あ', 'お', 'い']);
    });
  });

  group('isReadable', () {
    test('a plain word needs every unit learned', () {
      expect(KanaTokenizer.isReadable('いぬ', {'い', 'ぬ'}), isTrue);
      expect(KanaTokenizer.isReadable('いぬ', {'い'}), isFalse);
    });

    test('sokuon is backed by つ/ツ, never learned on its own', () {
      const base = {'が', 'こ', 'う'};
      expect(KanaTokenizer.isReadable('がっこう', {...base, 'つ'}), isTrue);
      expect(KanaTokenizer.isReadable('がっこう', base), isFalse);
      expect(KanaTokenizer.isReadable('コップ', {'コ', 'プ', 'ツ'}), isTrue);
      expect(KanaTokenizer.isReadable('コップ', {'コ', 'プ', 'つ'}), isFalse);
    });

    test('a yōon digraph needs the digraph unit itself', () {
      expect(KanaTokenizer.isReadable('しゃしん', {'しゃ', 'し', 'ん'}), isTrue);
      // Knowing the parts is not knowing the unit.
      expect(KanaTokenizer.isReadable('しゃしん', {'し', 'や', 'ん'}), isFalse);
    });

    test('chōonpu rides on whatever it stretches', () {
      expect(KanaTokenizer.isReadable('コーヒー', {'コ', 'ヒ'}), isTrue);
      expect(KanaTokenizer.isReadable('コーヒー', {'コ'}), isFalse);
      expect(
        KanaTokenizer.isReadable('ー', {'コ'}),
        isFalse,
      ); // nothing before it
    });

    test('a small-vowel combo needs its base and the full-size vowel', () {
      expect(KanaTokenizer.isReadable('ファン', {'フ', 'ア', 'ン'}), isTrue);
      expect(KanaTokenizer.isReadable('ファン', {'フ', 'ン'}), isFalse);
    });

    test('empty text reads as nothing', () {
      expect(KanaTokenizer.isReadable('', {'あ'}), isFalse);
    });
  });

  group('deriveRomaji (canonical orthography)', () {
    const h = KanaScript.hiragana;
    const k = KanaScript.katakana;
    test('sokuon doubles the next consonant; っち is tch', () {
      expect(deriveRomaji('がっこう', h), 'gakkou');
      expect(deriveRomaji('みっつ', h), 'mittsu');
      expect(deriveRomaji('いっしょ', h), 'issho');
      expect(deriveRomaji('まっちゃ', h), 'matcha');
      expect(deriveRomaji('チェック', k), 'chekku');
    });

    test('chōonpu repeats the previous vowel', () {
      expect(deriveRomaji('コーヒー', k), 'koohii');
      expect(deriveRomaji('パーティー', k), 'paatii');
    });

    test("ん is n, and n' before a vowel or y", () {
      expect(deriveRomaji('げんき', h), 'genki');
      expect(deriveRomaji('ほんや', h), "hon'ya");
      expect(deriveRomaji('きんえん', h), "kin'en");
    });

    test('small-vowel combos read from the curated table', () {
      expect(deriveRomaji('ファン', k), 'fan');
      expect(deriveRomaji('ウィン', k), 'win');
    });
  });

  group('validateKanaOrthography', () {
    const h = KanaScript.hiragana;
    const k = KanaScript.katakana;
    test('legal words are clean', () {
      for (final (kana, script) in [
        ('がっこう', h),
        ('しゃしん', h),
        ('ほんや', h),
        ('コーヒー', k),
        ('ファン', k),
        ('チェック', k),
      ]) {
        expect(validateKanaOrthography(kana, script), isEmpty, reason: kana);
      }
    });

    test('illegal special-mora environments are reported', () {
      expect(validateKanaOrthography('っか', h), isNotEmpty); // leading っ
      expect(validateKanaOrthography('あっ', h), isNotEmpty); // trailing っ
      expect(validateKanaOrthography('あっあ', h), isNotEmpty); // っ before vowel
      expect(validateKanaOrthography('ーア', k), isNotEmpty); // leading ー
      expect(validateKanaOrthography('ラーめん', k), isNotEmpty); // mixed script
      expect(validateKanaOrthography('らーめん', h), isNotEmpty); // ー in hiragana
      expect(validateKanaOrthography('パンー', k), isNotEmpty); // ー after ん
    });
  });
}
