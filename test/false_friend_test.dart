// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

void main() {
  Iterable<Word> seeded() => kWords.where((w) => w.falseFriend != null);

  test('the curated false-friend words are present', () {
    expect(
      seeded().map((w) => w.kana),
      containsAll(['てがみ', 'しんぶん', 'やくそく', 'けが']),
    );
  });

  test('every false-friend word is readable (no yōon/sokuon)', () {
    // A note can only ever surface once its word is readable, and the gate is
    // per-rune. A small kana (yōon/sokuon) would never satisfy it — so a seeded
    // false-friend word containing one would be a permanently-hidden note.
    const smallKana = {
      'ゃ', 'ゅ', 'ょ', 'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ', 'っ', //
      'ャ', 'ュ', 'ョ', 'ッ',
    };
    for (final w in seeded()) {
      for (final ch in w.characters) {
        expect(
          smallKana.contains(ch),
          isFalse,
          reason:
              '${w.kana} has a small kana ($ch) → its note could never show',
        );
      }
    }
  });

  test(
    'the note affirms the Japanese meaning first, gently — never a warning',
    () {
      final tegami = seeded().firstWhere((w) => w.kana == 'てがみ');
      final note = AppStrings.falseFriendNote(tegami.falseFriend!);
      // The Japanese sense leads; the Chinese trap is a soft aside that follows.
      expect(note.indexOf('手紙'), lessThan(note.indexOf('廁紙')));
      expect(note, contains('信'));
      expect(note, isNot(contains('小心')));
      expect(note, isNot(contains('!')));
    },
  );
}
