// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';

/// Integrity of the hand-typed reading dataset — the value is catching typos in
/// kana / romaji / meaning, since this is content not code.
void main() {
  // Single-rune hiragana characters (seion + dakuten + handakuten), and their
  // canonical romaji, from the kana dataset.
  final hiragana = kAllKana.where((k) => k.script == KanaScript.hiragana);
  final validChars = {
    for (final k in hiragana)
      if (k.character.runes.length == 1) k.character,
  };
  final charToRomaji = {
    for (final k in hiragana)
      if (k.character.runes.length == 1) k.character: k.romaji,
  };

  test('every word is non-empty and has a meaning', () {
    for (final w in kWords) {
      expect(w.kana, isNotEmpty, reason: w.romaji);
      expect(w.romaji, isNotEmpty, reason: w.kana);
      expect(w.meaning, isNotEmpty, reason: w.kana);
    }
  });

  test('no yōon — every character is a single-rune hiragana kana', () {
    for (final w in kWords) {
      for (final r in w.kana.runes) {
        final c = String.fromCharCode(r);
        expect(
          validChars.contains(c),
          isTrue,
          reason: '"$c" in ${w.kana} is not a single-rune hiragana',
        );
      }
    }
  });

  test('romaji equals the literal kana-by-kana reading (no typos)', () {
    for (final w in kWords) {
      final derived = w.kana.runes
          .map((r) => charToRomaji[String.fromCharCode(r)])
          .join();
      expect(
        w.romaji,
        derived,
        reason: '${w.kana}: stored "${w.romaji}" != derived "$derived"',
      );
    }
  });

  test('no duplicate words', () {
    final kanas = kWords.map((w) => w.kana).toList();
    expect(kanas.toSet().length, kanas.length);
  });
}
