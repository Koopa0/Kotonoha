// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

import '../helpers/kana_orthography.dart';

void main() {
  test('written / reading / gatingText getters', () {
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
    expect(p.gatingText, ['を', 'る']);
  });

  test('a furigana segment either fades against a real reading, or never', () {
    // A kanji the curriculum has not taught yet carries furigana with NO
    // reading id and keeps it forever (honest: the app never fades a reading
    // it never taught). What must never happen is a reading id pointing at
    // nothing — that would silently read as level 0 and look identical to
    // "brand new" while actually being a typo.
    final validIds = {for (final k in kKanji) ...k.readingIds};
    for (final p in kKanjiPhrases) {
      expect(p.romaji, isNotEmpty, reason: p.written);
      expect(p.meaning, isNotEmpty, reason: p.written);
      for (final s in p.segments) {
        if (s.isKanji) {
          expect(s.text.runes.length, 1, reason: p.written);
          expect(
            s.furigana!.runes.every((r) => r >= 0x3040 && r <= 0x30ff),
            isTrue,
            reason: '${p.written}: furigana "${s.furigana}" is not kana',
          );
          if (s.readingId != null) {
            expect(
              validIds.contains(s.readingId),
              isTrue,
              reason: '${p.written}: ${s.readingId} not in kKanji',
            );
          }
        }
      }
    }
  });

  test('every sentence romaji is derivable from its own furigana reading', () {
    // The one mechanical check on furigana correctness at corpus scale: a
    // typo in any furigana changes `reading`, which changes what the romaji
    // can be, and the two stop agreeing. Particle readings (は/へ/を) and the
    // optional ん-apostrophe are genuinely ambiguous without word boundaries,
    // so the derivation offers every legal transcription and the stored
    // romaji must be one of them.
    for (final p in kKanjiPhrases) {
      final candidates = possibleReadingRomaji(p.reading);
      expect(
        candidates,
        isNotEmpty,
        reason: '${p.written}: reading "${p.reading}" is not transcribable',
      );
      expect(
        candidates.contains(p.romaji.replaceAll(RegExp('[ ,.、。]'), '')),
        isTrue,
        reason:
            '${p.written}: romaji "${p.romaji}" does not match its reading '
            '"${p.reading}"',
      );
    }
  });

  test(
    'every phrase has at least one plain kana segment (the gate is real)',
    () {
      // The readability gate asks whether the NON-kanji kana is known. A phrase
      // with no plain segment (書道-style, all kanji + furigana) passes that gate
      // vacuously — readable, and unlocking the track, before a single kana is
      // learned. The corpus must always give the gate something real to hold.
      for (final p in kKanjiPhrases) {
        expect(
          p.gatingText,
          isNotEmpty,
          reason: '${p.written}: no plain kana segment — readable at zero kana',
        );
      }
    },
  );
  test('no phrase is readable on the first kana row alone (unlock order)', () {
    // The home's unlock choreography is 詞 → 句 → 漢字句. A kanji phrase whose
    // plain kana happens to fit inside あ行 (近い店-style: plain = い) would
    // open the kanji-sentence track the moment the very first row is learned,
    // shoving its unlock line in front of the guidance step. Pin the order.
    const firstRow = {'あ', 'い', 'う', 'え', 'お'};
    for (final p in kKanjiPhrases) {
      expect(
        p.gatingText.every((s) => KanaTokenizer.isReadable(s, firstRow)),
        isFalse,
        reason: '${p.written}: readable with あ行 alone',
      );
    }
  });
}
