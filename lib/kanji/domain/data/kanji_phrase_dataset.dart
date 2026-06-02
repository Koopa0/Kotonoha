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
  // ── Seasonal / 物の哀れ register (名残の仮名). Every kanji's furigana is a real
  // reading in kKanji, so the furigana fades as that reading matures. ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '雪', furigana: 'ゆき', readingId: 'reading:雪#ゆき'),
      RubySegment(text: 'の'),
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
    ],
    romaji: 'yuki no yama',
    meaning: '覆雪的山',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '月', furigana: 'つき', readingId: 'reading:月#つき'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'る'),
    ],
    romaji: 'tsuki o miru',
    meaning: '凝望月色',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'の'),
      RubySegment(text: '名', furigana: 'な', readingId: 'reading:名#な'),
    ],
    romaji: 'hana no na',
    meaning: '那花的名字',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '秋', furigana: 'あき', readingId: 'reading:秋#あき'),
      RubySegment(text: 'の'),
      RubySegment(text: '風', furigana: 'かぜ', readingId: 'reading:風#かぜ'),
    ],
    romaji: 'aki no kaze',
    meaning: '秋日的風',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '雨', furigana: 'あめ', readingId: 'reading:雨#あめ'),
      RubySegment(text: 'の'),
      RubySegment(text: '夜', furigana: 'よる', readingId: 'reading:夜#よる'),
    ],
    romaji: 'ame no yoru',
    meaning: '落雨的夜',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '星', furigana: 'ほし', readingId: 'reading:星#ほし'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'る'),
    ],
    romaji: 'hoshi o miru',
    meaning: '仰望星辰',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '森', furigana: 'もり', readingId: 'reading:森#もり'),
      RubySegment(text: 'の'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
    ],
    romaji: 'mori no naka',
    meaning: '森林深處',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'る'),
    ],
    romaji: 'umi o miru',
    meaning: '望向大海',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '春', furigana: 'はる', readingId: 'reading:春#はる'),
      RubySegment(text: 'の'),
      RubySegment(text: '雨', furigana: 'あめ', readingId: 'reading:雨#あめ'),
    ],
    romaji: 'haru no ame',
    meaning: '春雨',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '冬', furigana: 'ふゆ', readingId: 'reading:冬#ふゆ'),
      RubySegment(text: 'の'),
      RubySegment(text: '星', furigana: 'ほし', readingId: 'reading:星#ほし'),
    ],
    romaji: 'fuyu no hoshi',
    meaning: '冬夜的星',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '雲', furigana: 'くも', readingId: 'reading:雲#くも'),
      RubySegment(text: 'が'),
      RubySegment(text: '来', furigana: 'く', readingId: 'reading:来#く'),
      RubySegment(text: 'る'),
    ],
    romaji: 'kumo ga kuru',
    meaning: '雲湧而來',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '風', furigana: 'かぜ', readingId: 'reading:風#かぜ'),
      RubySegment(text: 'を'),
      RubySegment(text: '聞', furigana: 'き', readingId: 'reading:聞#き'),
      RubySegment(text: 'く'),
    ],
    romaji: 'kaze o kiku',
    meaning: '聆聽風聲',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '草', furigana: 'くさ', readingId: 'reading:草#くさ'),
      RubySegment(text: 'の'),
      RubySegment(text: '上', furigana: 'うえ', readingId: 'reading:上#うえ'),
    ],
    romaji: 'kusa no ue',
    meaning: '草地之上',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '夏', furigana: 'なつ', readingId: 'reading:夏#なつ'),
      RubySegment(text: 'の'),
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
    ],
    romaji: 'natsu no umi',
    meaning: '夏日的海',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '空', furigana: 'そら', readingId: 'reading:空#そら'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'る'),
    ],
    romaji: 'sora o miru',
    meaning: '望著天空',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'が'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'える'),
    ],
    romaji: 'hana ga mieru',
    meaning: '看得見花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '雪', furigana: 'ゆき', readingId: 'reading:雪#ゆき'),
      RubySegment(text: 'が'),
      RubySegment(text: '来', furigana: 'く', readingId: 'reading:来#く'),
      RubySegment(text: 'る'),
    ],
    romaji: 'yuki ga kuru',
    meaning: '雪將至',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '朝', furigana: 'あさ', readingId: 'reading:朝#あさ'),
      RubySegment(text: 'の'),
      RubySegment(text: '風', furigana: 'かぜ', readingId: 'reading:風#かぜ'),
    ],
    romaji: 'asa no kaze',
    meaning: '晨風',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '林', furigana: 'はやし', readingId: 'reading:林#はやし'),
      RubySegment(text: 'に'),
      RubySegment(text: '雨', furigana: 'あめ', readingId: 'reading:雨#あめ'),
    ],
    romaji: 'hayashi ni ame',
    meaning: '雨落樹林',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
      RubySegment(text: 'に'),
      RubySegment(text: '雲', furigana: 'くも', readingId: 'reading:雲#くも'),
    ],
    romaji: 'yama ni kumo',
    meaning: '雲繞山巔',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '夜', furigana: 'よる', readingId: 'reading:夜#よる'),
      RubySegment(text: 'の'),
      RubySegment(text: '雨', furigana: 'あめ', readingId: 'reading:雨#あめ'),
    ],
    romaji: 'yoru no ame',
    meaning: '夜雨',
  ),
];
