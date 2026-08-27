// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// Grammar-pattern sentences for 《大家的日本語》 I, lessons 1–6.
///
/// Part of the N5 spine: every pattern in these lessons appears as several
/// natural sentences, so review meets the PATTERN rather than a memorised card
/// face. Nothing here names or explains a pattern — the textbook is the grammar
/// authority; this corpus only makes its shapes familiar to the eye.
///
/// LIST ORDER IS THE INTRODUCTION ORDER, and for this track it is the only
/// pedagogical staging there is: mixed-script sentences gate on their plain
/// kana alone, so the readability gate no longer sorts easy from hard.
///
/// A handful of kanji here carry furigana with NO reading id on purpose: 来
/// (来ます/来ました is き, not the registered dictionary-form く), 少 (少し is
/// すこ, not the registered すく), 夕 (unregistered), and the number kanji
/// 九・三・七・二・十・一 (spoken time/counting readings; no numeral kanji is
/// in the course at all) are real, honest readings that just are not yet in
/// the course — see [RubySegment.fades].
///
/// Pure data: no `package:flutter/*` imports.
const List<KanjiPhrase> kMinnaL01to06 = <KanjiPhrase>[
  // 文型:NはNです
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんは'),
      RubySegment(text: '学', furigana: 'がく', readingId: 'reading:学#ガク'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'tanaka san wa gakusei desu',
    meaning: '田中是學生。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'マイクさんは'),
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'maiku san wa sensei desu',
    meaning: '麥克是老師。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ワンさんは'),
      RubySegment(text: '外', furigana: 'がい', readingId: 'reading:外#ガイ'),
      RubySegment(text: '国', furigana: 'こく', readingId: 'reading:国#コク'),
      RubySegment(text: '人', furigana: 'じん', readingId: 'reading:人#ジン'),
      RubySegment(text: 'です'),
    ],
    romaji: 'wan san wa gaikokujin desu',
    meaning: '王先生是外國人。',
  ),

  // 文型:NはNじゃありません
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんは'),
      RubySegment(text: '学', furigana: 'がく', readingId: 'reading:学#ガク'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'じゃありません'),
    ],
    romaji: 'tanaka san wa gakusei ja arimasen',
    meaning: '田中不是學生。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'マイクさんは'),
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'じゃありません'),
    ],
    romaji: 'maiku san wa sensei ja arimasen',
    meaning: '麥克不是老師。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ワンさんは'),
      RubySegment(text: '学', furigana: 'がく', readingId: 'reading:学#ガク'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'じゃありません'),
    ],
    romaji: 'wan san wa gakusei ja arimasen',
    meaning: '王先生不是學生。',
  ),

  // 文型:も
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんも'),
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'tanaka san mo sensei desu',
    meaning: '田中也是老師。',
  ),

  // 文型:の(所屬) — combined with Nですか for natural variety.
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんの'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'ですか'),
    ],
    romaji: 'tanaka san no hon desu ka',
    meaning: '是田中的書嗎?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '父', furigana: 'ちち', readingId: 'reading:父#ちち'),
      RubySegment(text: 'の'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'ですか'),
    ],
    romaji: 'chichi no hana desu ka',
    meaning: '是父親的花嗎?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '母', furigana: 'はは', readingId: 'reading:母#はは'),
      RubySegment(text: 'の'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'ですか'),
    ],
    romaji: 'haha no hon desu ka',
    meaning: '是母親的書嗎?',
  ),

  // 文型:これ・それ・あれ
  KanjiPhrase(
    segments: [
      RubySegment(text: 'これは'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'です'),
    ],
    romaji: 'kore wa hon desu',
    meaning: '這是書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あれは'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'です'),
    ],
    romaji: 'are wa hana desu',
    meaning: '遠處那個是花。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'それは'),
      RubySegment(text: 'わたし'),
      RubySegment(text: 'の'),
      RubySegment(text: 'です'),
    ],
    romaji: 'sore wa watashi no desu',
    meaning: '那是我的。',
  ),

  // 文型:このN・そのN・あのN — combined with の(所有物,ellipsis).
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'は'),
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんの'),
      RubySegment(text: 'です'),
    ],
    romaji: 'kono hon wa tanaka san no desu',
    meaning: '這本書是田中的。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'その'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'は'),
      RubySegment(text: '母', furigana: 'はは', readingId: 'reading:母#はは'),
      RubySegment(text: 'のです'),
    ],
    romaji: 'sono hana wa haha no desu',
    meaning: '那朵花是母親的。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あの'),
      RubySegment(text: '人', furigana: 'ひと', readingId: 'reading:人#ひと'),
      RubySegment(text: 'は'),
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'ano hito wa sensei desu',
    meaning: '那位是老師。',
  ),

  // 文型:そうです
  KanjiPhrase(
    segments: [
      RubySegment(text: 'はい'),
      RubySegment(text: 'そうです'),
    ],
    romaji: 'hai sou desu',
    meaning: '是的,沒錯。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いいえ'),
      RubySegment(text: 'そうじゃありません'),
    ],
    romaji: 'iie sou ja arimasen',
    meaning: '不,不是那樣。',
  ),
  KanjiPhrase(
    segments: [RubySegment(text: 'そうですか')],
    romaji: 'sou desu ka',
    meaning: '是這樣嗎?',
  ),

  // 文型:ここ・そこ・あそこ — combined with NはPlaceです.
  KanjiPhrase(
    segments: [
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'はここです'),
    ],
    romaji: 'kaisha wa koko desu',
    meaning: '公司在這裡。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'はそこです'),
    ],
    romaji: 'eki wa soko desu',
    meaning: '車站在那裡。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'はあそこです'),
    ],
    romaji: 'umi wa asoko desu',
    meaning: '海在那邊。',
  ),

  // 文型:どこ
  KanjiPhrase(
    segments: [
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'はどこですか'),
    ],
    romaji: 'kaisha wa doko desu ka',
    meaning: '公司在哪裡?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'はどこですか'),
    ],
    romaji: 'eki wa doko desu ka',
    meaning: '車站在哪裡?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'はどこですか'),
    ],
    romaji: 'mise wa doko desu ka',
    meaning: '店在哪裡?',
  ),

  // 文型:いくらですか
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'はいくらですか'),
    ],
    romaji: 'hon wa ikura desu ka',
    meaning: '這本書多少錢?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'はいくらですか'),
    ],
    romaji: 'kono hana wa ikura desu ka',
    meaning: '這朵花多少錢?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'しん', readingId: 'reading:新#シン'),
      RubySegment(text: '聞', furigana: 'ぶん', readingId: 'reading:聞#ブン'),
      RubySegment(text: 'はいくらですか'),
    ],
    romaji: 'shinbun wa ikura desu ka',
    meaning: '報紙多少錢?',
  ),

  // 文型:今〜時〜分です
  KanjiPhrase(
    segments: [
      RubySegment(text: '今', furigana: 'いま', readingId: 'reading:今#いま'),
      RubySegment(text: '九', furigana: 'く'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'ima kuji desu',
    meaning: '現在九點。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '今', furigana: 'いま', readingId: 'reading:今#いま'),
      RubySegment(text: '三', furigana: 'さん'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: '半', furigana: 'はん', readingId: 'reading:半#ハン'),
      RubySegment(text: 'です'),
    ],
    romaji: 'ima sanji han desu',
    meaning: '現在三點半。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '今', furigana: 'いま', readingId: 'reading:今#いま'),
      RubySegment(text: '七', furigana: 'しち'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: '二', furigana: 'に'),
      RubySegment(text: '分', furigana: 'ふん', readingId: 'reading:分#フン'),
      RubySegment(text: 'です'),
    ],
    romaji: 'ima shichiji nifun desu',
    meaning: '現在七點兩分。',
  ),

  // 文型:Vます・Vません・Vました — combined with と(名詞並列).
  KanjiPhrase(
    segments: [
      RubySegment(text: '父', furigana: 'ちち', readingId: 'reading:父#ちち'),
      RubySegment(text: 'と'),
      RubySegment(text: '母', furigana: 'はは', readingId: 'reading:母#はは'),
      RubySegment(text: 'は'),
      RubySegment(text: '休', furigana: 'やす', readingId: 'reading:休#やす'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'chichi to haha wa yasumimasu',
    meaning: '父親和母親都要休息。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんと'),
      RubySegment(text: 'マイクさんは'),
      RubySegment(text: '休', furigana: 'やす', readingId: 'reading:休#やす'),
      RubySegment(text: 'みません'),
    ],
    romaji: 'tanaka san to maiku san wa yasumimasen',
    meaning: '田中和麥克都不休息。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '父', furigana: 'ちち', readingId: 'reading:父#ちち'),
      RubySegment(text: 'と'),
      RubySegment(text: '母', furigana: 'はは', readingId: 'reading:母#はは'),
      RubySegment(text: 'は'),
      RubySegment(text: '九', furigana: 'く'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: 'に'),
      RubySegment(text: '寝', furigana: 'ね', readingId: 'reading:寝#ね'),
      RubySegment(text: 'ました'),
    ],
    romaji: 'chichi to haha wa kuji ni nemashita',
    meaning: '父親和母親九點睡了。',
  ),

  // 文型:〜から〜まで
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'から'),
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'まで'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'eki kara kaisha made arukimasu',
    meaning: '從車站走到公司。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'から'),
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'まで'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'ie kara eki made arukimasu',
    meaning: '從家裡走到車站。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '十', furigana: 'じゅう'),
      RubySegment(text: '二', furigana: 'に'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: 'から'),
      RubySegment(text: '一', furigana: 'いち'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: 'まで'),
      RubySegment(text: '休', furigana: 'やす', readingId: 'reading:休#やす'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'juuniji kara ichiji made yasumimasu',
    meaning: '從十二點休息到一點。',
  ),

  // 文型:Placeへ行きます・来ます・帰ります — combined with Vehicleで.
  KanjiPhrase(
    segments: [
      RubySegment(text: 'バスで'),
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'basu de kaisha e ikimasu',
    meaning: '搭公車去公司。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'タクシーで'),
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'takushii de eki e ikimasu',
    meaning: '搭計程車去車站。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'バイクで'),
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '帰', furigana: 'かえ', readingId: 'reading:帰#かえ'),
      RubySegment(text: 'ります'),
    ],
    romaji: 'baiku de ie e kaerimasu',
    meaning: '騎機車回家。',
  ),

  // 文型:人と行きます
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: 'と'),
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'tomo to umi e ikimasu',
    meaning: '和朋友去海邊。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '父', furigana: 'ちち', readingId: 'reading:父#ちち'),
      RubySegment(text: 'と'),
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'chichi to machi e ikimasu',
    meaning: '和父親去鎮上。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た', readingId: 'reading:田#た'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'さんと'),
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'tanaka san to kaisha e ikimasu',
    meaning: '和田中一起去公司。',
  ),

  // 文型:いつ
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いつ'),
      RubySegment(text: '国', furigana: 'くに', readingId: 'reading:国#くに'),
      RubySegment(text: 'へ'),
      RubySegment(text: '帰', furigana: 'かえ', readingId: 'reading:帰#かえ'),
      RubySegment(text: 'りますか'),
    ],
    romaji: 'itsu kuni e kaerimasu ka',
    meaning: '什麼時候回國?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いつ'),
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'へ'),
      // 来る is irregular: the ます-stem reads き, not the registered
      // dictionary-form く — honestly furigana'd, no reading id (see header).
      RubySegment(text: '来', furigana: 'き'),
      RubySegment(text: 'ますか'),
    ],
    romaji: 'itsu kaisha e kimasu ka',
    meaning: '什麼時候來公司?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いつ'),
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'きますか'),
    ],
    romaji: 'itsu umi e ikimasu ka',
    meaning: '什麼時候去海邊?',
  ),

  // 文型:何をしますか — combined with Nを V.
  KanjiPhrase(
    segments: [
      RubySegment(text: '何', furigana: 'なに', readingId: 'reading:何#なに'),
      RubySegment(text: 'を'),
      RubySegment(text: 'しますか'),
    ],
    romaji: 'nani o shimasu ka',
    meaning: '要做什麼?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'で'),
      RubySegment(text: '何', furigana: 'なに', readingId: 'reading:何#なに'),
      RubySegment(text: 'を'),
      RubySegment(text: 'しますか'),
    ],
    romaji: 'ie de nani o shimasu ka',
    meaning: '在家要做什麼?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'で'),
      RubySegment(text: '何', furigana: 'なに', readingId: 'reading:何#なに'),
      RubySegment(text: 'を'),
      RubySegment(text: 'しますか'),
    ],
    romaji: 'kaisha de nani o shimasu ka',
    meaning: '在公司要做什麼?',
  ),

  // 文型:PlaceでV — combined with Nを V・〜ませんか・〜ましょう.
  KanjiPhrase(
    segments: [
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'で'),
      RubySegment(text: '夕', furigana: 'ゆう'),
      RubySegment(text: '日', furigana: 'ひ', readingId: 'reading:日#ひ'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み', readingId: 'reading:見#み'),
      RubySegment(text: 'ませんか'),
    ],
    romaji: 'umi de yuuhi o mimasen ka',
    meaning: '要不要在海邊看夕陽?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'で'),
      RubySegment(text: '新', furigana: 'しん', readingId: 'reading:新#シン'),
      RubySegment(text: '聞', furigana: 'ぶん', readingId: 'reading:聞#ブン'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ', readingId: 'reading:読#よ'),
      RubySegment(text: 'みましょう'),
    ],
    romaji: 'ie de shinbun o yomimashou',
    meaning: '在家看報紙吧。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あの'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'で'),
      RubySegment(text: 'コーヒーを'),
      RubySegment(text: '飲', furigana: 'の', readingId: 'reading:飲#の'),
      RubySegment(text: 'みませんか'),
    ],
    romaji: 'ano mise de koohii o nomimasen ka',
    meaning: '要不要在那家店喝咖啡?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'で'),
      RubySegment(text: '少', furigana: 'すこ'),
      RubySegment(text: 'し'),
      RubySegment(text: '休', furigana: 'やす', readingId: 'reading:休#やす'),
      RubySegment(text: 'みませんか'),
    ],
    romaji: 'kaisha de sukoshi yasumimasen ka',
    meaning: '要不要在公司休息一下?',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'で'),
      RubySegment(text: '待', furigana: 'ま', readingId: 'reading:待#ま'),
      RubySegment(text: 'ちましょう'),
    ],
    romaji: 'eki de machimashou',
    meaning: '在車站等吧。',
  ),

  // 文型:〜ましょう
  KanjiPhrase(
    segments: [
      RubySegment(text: 'もう'),
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '帰', furigana: 'かえ', readingId: 'reading:帰#かえ'),
      RubySegment(text: 'りましょう'),
    ],
    romaji: 'mou ie e kaerimashou',
    meaning: '回家吧。',
  ),
];
