// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// Short kanji sentences for the furigana-fade reading bridge. Every kanji uses
/// a reading from kKanji (so its furigana fades as that reading matures), and
/// the surrounding kana is N5-simple. Reading-ids match `reading:漢字#ヨミ`.
///
/// Pure data: no `package:flutter/*` imports.
const List<KanjiPhrase> kKanjiPhrases = <KanjiPhrase>[
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'る'),
    ],
    romaji: 'yama o miru',
    meaning: '看山',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '川', furigana: 'かわ', readingId: 'reading:川#かわ'),
      RubySegment(text: 'が'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'える'),
    ],
    romaji: 'kawa ga mieru',
    meaning: '看得見河',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '火', furigana: 'ひ', readingId: 'reading:火#ひ'),
      RubySegment(text: 'と'),
      RubySegment(text: '水', furigana: 'みず', readingId: 'reading:水#みず'),
    ],
    romaji: 'hi to mizu',
    meaning: '火與水',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '上', furigana: 'うえ', readingId: 'reading:上#うえ'),
      RubySegment(text: 'と'),
      RubySegment(text: '下', furigana: 'した', readingId: 'reading:下#した'),
    ],
    romaji: 'ue to shita',
    meaning: '上與下',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '男', furigana: 'おとこ', readingId: 'reading:男#おとこ'),
      RubySegment(text: 'と'),
      RubySegment(text: '女', furigana: 'おんな', readingId: 'reading:女#おんな'),
    ],
    romaji: 'otoko to onna',
    meaning: '男與女',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '大', furigana: 'おお', readingId: 'reading:大#おお'),
      RubySegment(text: 'きい'),
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
    ],
    romaji: 'ookii yama',
    meaning: '大的山',
  ),
];
