// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';

/// Integrity of the hand-typed reading dataset — the value is catching typos in
/// kana / romaji / meaning, since this is content not code.
void main() {
  // Single-rune kana per script (seion + dakuten + handakuten) and their
  // canonical romaji, from the kana dataset — a word is validated against the
  // script it declares.
  final validByScript = <KanaScript, Set<String>>{};
  final romajiByScript = <KanaScript, Map<String, String>>{};
  for (final k in kAllKana) {
    if (k.character.runes.length != 1) continue;
    (validByScript[k.script] ??= {}).add(k.character);
    (romajiByScript[k.script] ??= {})[k.character] = k.romaji;
  }

  test('every word is non-empty and has a meaning', () {
    for (final w in kWords) {
      expect(w.kana, isNotEmpty, reason: w.romaji);
      expect(w.romaji, isNotEmpty, reason: w.kana);
      expect(w.meaning, isNotEmpty, reason: w.kana);
    }
  });

  test(
    'no yōon / chōonpu — every char is a single-rune kana of its script',
    () {
      for (final w in kWords) {
        for (final r in w.kana.runes) {
          final c = String.fromCharCode(r);
          expect(
            validByScript[w.script]!.contains(c),
            isTrue,
            reason:
                '"$c" in ${w.kana} is not a single-rune ${w.script.name} kana',
          );
        }
      }
    },
  );

  test('romaji equals the literal kana-by-kana reading (no typos)', () {
    for (final w in kWords) {
      final map = romajiByScript[w.script]!;
      final derived = w.kana.runes
          .map((r) => map[String.fromCharCode(r)])
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
