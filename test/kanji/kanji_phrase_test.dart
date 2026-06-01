// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

void main() {
  test('written / reading / plainKana getters', () {
    const p = KanjiPhrase(
      segments: [
        RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
        RubySegment(text: 'を'),
        RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
        RubySegment(text: 'る'),
      ],
      romaji: 'yama o miru',
      meaning: '看山',
    );
    expect(p.written, '山を見る');
    expect(p.reading, 'やまをみる');
    expect(p.plainKana, {'を', 'る'});
  });

  test('every furigana segment resolves to a real reading id (fade works)', () {
    final validIds = {for (final k in kKanji) ...k.readingIds};
    for (final p in kKanjiPhrases) {
      expect(p.romaji, isNotEmpty, reason: p.written);
      expect(p.meaning, isNotEmpty, reason: p.written);
      for (final s in p.segments) {
        if (s.isKanji) {
          expect(s.text.runes.length, 1, reason: p.written);
          expect(
            validIds.contains(s.readingId),
            isTrue,
            reason: '${p.written}: ${s.readingId} not in kKanji',
          );
        }
      }
    }
  });
}
