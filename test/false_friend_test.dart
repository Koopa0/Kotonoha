// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

void main() {
  Iterable<Word> seeded() => kWords.where((w) => w.falseFriend != null);

  test('the curated false-friend words are present', () {
    expect(
      seeded().map((w) => w.kana),
      containsAll(['てがみ', 'しんぶん', 'やくそく', 'けが']),
    );
  });

  test('every false-friend word becomes readable with the full syllabary', () {
    // A note can only ever surface once its word is readable — a word the gate
    // could never pass would be a permanently-hidden note.
    for (final w in seeded()) {
      final units = {
        for (final k in kAllKana)
          if (k.script == w.script) k.character,
      };
      expect(
        KanaTokenizer.isReadable(w.kana, units),
        isTrue,
        reason: '${w.kana}: its false-friend note could never show',
      );
    }
  });

  test('the note affirms the Japanese meaning first, gently — never a warning', () {
    final tegami = seeded().firstWhere((w) => w.kana == 'てがみ');
    final note = AppStrings.falseFriendNote(tegami.falseFriend!);
    // The Japanese sense leads; the Chinese trap is a soft aside that follows.
    expect(note.indexOf('手紙'), lessThan(note.indexOf('廁紙')));
    expect(note, contains('信'));
    expect(note, isNot(contains('小心')));
    expect(note, isNot(contains('!')));
  });
}
