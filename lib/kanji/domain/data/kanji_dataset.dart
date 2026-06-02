// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';

/// The starter kanji set — 30 JLPT N5 kanji in frequency order, 1–2 readings
/// each (capped to avoid retrieval interference). On-yomi in katakana, kun-yomi
/// in hiragana; one example word (in kana) + a Traditional-Chinese gloss per
/// reading, shown only on reveal. The 月火水木金土日 day-of-week set is kept
/// adjacent so one familiar paradigm reinforces seven kanji.
///
/// Pure data: no `package:flutter/*` imports.
const List<KanjiEntry> kKanji = <KanjiEntry>[
  KanjiEntry(
    char: '人',
    meaningZh: '人、人類',
    readings: [
      Reading(
        text: 'ひと',
        kind: ReadingKind.kun,
        exampleWord: 'ひと',
        exampleMeaning: '人',
      ),
      Reading(
        text: 'ジン',
        kind: ReadingKind.on,
        exampleWord: 'がいこくじん',
        exampleMeaning: '外國人',
      ),
    ],
  ),
  KanjiEntry(
    char: '日',
    meaningZh: '日、太陽',
    readings: [
      Reading(
        text: 'ニチ',
        kind: ReadingKind.on,
        exampleWord: 'にちようび',
        exampleMeaning: '星期日',
      ),
      Reading(
        text: 'ひ',
        kind: ReadingKind.kun,
        exampleWord: 'ひ',
        exampleMeaning: '日子、太陽',
      ),
    ],
  ),
  KanjiEntry(
    char: '本',
    meaningZh: '書本、根本',
    readings: [
      Reading(
        text: 'ホン',
        kind: ReadingKind.on,
        exampleWord: 'ほん',
        exampleMeaning: '書',
      ),
    ],
  ),
  KanjiEntry(
    char: '月',
    meaningZh: '月亮、月份',
    readings: [
      Reading(
        text: 'ゲツ',
        kind: ReadingKind.on,
        exampleWord: 'げつようび',
        exampleMeaning: '星期一',
      ),
      Reading(
        text: 'つき',
        kind: ReadingKind.kun,
        exampleWord: 'つき',
        exampleMeaning: '月亮',
      ),
    ],
  ),
  KanjiEntry(
    char: '火',
    meaningZh: '火',
    readings: [
      Reading(
        text: 'カ',
        kind: ReadingKind.on,
        exampleWord: 'かようび',
        exampleMeaning: '星期二',
      ),
      Reading(
        text: 'ひ',
        kind: ReadingKind.kun,
        exampleWord: 'ひ',
        exampleMeaning: '火',
      ),
    ],
  ),
  KanjiEntry(
    char: '水',
    meaningZh: '水',
    readings: [
      Reading(
        text: 'スイ',
        kind: ReadingKind.on,
        exampleWord: 'すいようび',
        exampleMeaning: '星期三',
      ),
      Reading(
        text: 'みず',
        kind: ReadingKind.kun,
        exampleWord: 'みず',
        exampleMeaning: '水',
      ),
    ],
  ),
  KanjiEntry(
    char: '木',
    meaningZh: '樹木、木頭',
    readings: [
      Reading(
        text: 'き',
        kind: ReadingKind.kun,
        exampleWord: 'き',
        exampleMeaning: '樹、木',
      ),
      Reading(
        text: 'モク',
        kind: ReadingKind.on,
        exampleWord: 'もくようび',
        exampleMeaning: '星期四',
      ),
    ],
  ),
  KanjiEntry(
    char: '金',
    meaningZh: '金、錢',
    readings: [
      Reading(
        text: 'キン',
        kind: ReadingKind.on,
        exampleWord: 'きんようび',
        exampleMeaning: '星期五',
      ),
      Reading(
        text: 'かね',
        kind: ReadingKind.kun,
        exampleWord: 'おかね',
        exampleMeaning: '錢',
      ),
    ],
  ),
  KanjiEntry(
    char: '土',
    meaningZh: '土、泥土',
    readings: [
      Reading(
        text: 'ド',
        kind: ReadingKind.on,
        exampleWord: 'どようび',
        exampleMeaning: '星期六',
      ),
      Reading(
        text: 'つち',
        kind: ReadingKind.kun,
        exampleWord: 'つち',
        exampleMeaning: '泥土',
      ),
    ],
  ),
  KanjiEntry(
    char: '山',
    meaningZh: '山',
    readings: [
      Reading(
        text: 'やま',
        kind: ReadingKind.kun,
        exampleWord: 'やま',
        exampleMeaning: '山',
      ),
      Reading(
        text: 'サン',
        kind: ReadingKind.on,
        exampleWord: 'ふじさん',
        exampleMeaning: '富士山',
      ),
    ],
  ),
  KanjiEntry(
    char: '川',
    meaningZh: '河川',
    readings: [
      Reading(
        text: 'かわ',
        kind: ReadingKind.kun,
        exampleWord: 'かわ',
        exampleMeaning: '河川',
      ),
    ],
  ),
  KanjiEntry(
    char: '田',
    meaningZh: '田、水田',
    readings: [
      Reading(
        text: 'た',
        kind: ReadingKind.kun,
        exampleWord: 'たんぼ',
        exampleMeaning: '稻田',
      ),
    ],
  ),
  KanjiEntry(
    char: '大',
    meaningZh: '大',
    readings: [
      Reading(
        text: 'おお',
        kind: ReadingKind.kun,
        exampleWord: 'おおきい',
        exampleMeaning: '大的',
      ),
      Reading(
        text: 'ダイ',
        kind: ReadingKind.on,
        exampleWord: 'だいがく',
        exampleMeaning: '大學',
      ),
    ],
  ),
  KanjiEntry(
    char: '小',
    meaningZh: '小',
    readings: [
      Reading(
        text: 'ちい',
        kind: ReadingKind.kun,
        exampleWord: 'ちいさい',
        exampleMeaning: '小的',
      ),
      Reading(
        text: 'ショウ',
        kind: ReadingKind.on,
        exampleWord: 'しょうがっこう',
        exampleMeaning: '小學',
      ),
    ],
  ),
  KanjiEntry(
    char: '上',
    meaningZh: '上、上面',
    readings: [
      Reading(
        text: 'うえ',
        kind: ReadingKind.kun,
        exampleWord: 'うえ',
        exampleMeaning: '上面',
      ),
    ],
  ),
  KanjiEntry(
    char: '下',
    meaningZh: '下、下面',
    readings: [
      Reading(
        text: 'した',
        kind: ReadingKind.kun,
        exampleWord: 'した',
        exampleMeaning: '下面',
      ),
    ],
  ),
  KanjiEntry(
    char: '中',
    meaningZh: '中、裡面',
    readings: [
      Reading(
        text: 'チュウ',
        kind: ReadingKind.on,
        exampleWord: 'ちゅうがっこう',
        exampleMeaning: '中學',
      ),
      Reading(
        text: 'なか',
        kind: ReadingKind.kun,
        exampleWord: 'なか',
        exampleMeaning: '裡面、中間',
      ),
    ],
  ),
  KanjiEntry(
    char: '半',
    meaningZh: '一半',
    readings: [
      Reading(
        text: 'ハン',
        kind: ReadingKind.on,
        exampleWord: 'はんぶん',
        exampleMeaning: '一半',
      ),
    ],
  ),
  KanjiEntry(
    char: '分',
    meaningZh: '分鐘、區分',
    readings: [
      Reading(
        text: 'フン',
        kind: ReadingKind.on,
        exampleWord: 'ごふん',
        exampleMeaning: '五分鐘',
      ),
      Reading(
        text: 'わ',
        kind: ReadingKind.kun,
        exampleWord: 'わかる',
        exampleMeaning: '明白、懂',
      ),
    ],
  ),
  KanjiEntry(
    char: '年',
    meaningZh: '年',
    readings: [
      Reading(
        text: 'ネン',
        kind: ReadingKind.on,
        exampleWord: 'まいねん',
        exampleMeaning: '每年',
      ),
      Reading(
        text: 'とし',
        kind: ReadingKind.kun,
        exampleWord: 'とし',
        exampleMeaning: '年、歲',
      ),
    ],
  ),
  KanjiEntry(
    char: '時',
    meaningZh: '時間、時刻',
    readings: [
      Reading(
        text: 'ジ',
        kind: ReadingKind.on,
        exampleWord: 'さんじ',
        exampleMeaning: '三點鐘',
      ),
      Reading(
        text: 'とき',
        kind: ReadingKind.kun,
        exampleWord: 'とき',
        exampleMeaning: '時候',
      ),
    ],
  ),
  KanjiEntry(
    char: '間',
    meaningZh: '之間、間隔',
    readings: [
      Reading(
        text: 'カン',
        kind: ReadingKind.on,
        exampleWord: 'じかん',
        exampleMeaning: '時間',
      ),
      Reading(
        text: 'あいだ',
        kind: ReadingKind.kun,
        exampleWord: 'あいだ',
        exampleMeaning: '之間',
      ),
    ],
  ),
  KanjiEntry(
    char: '今',
    meaningZh: '現在、今',
    readings: [
      Reading(
        text: 'いま',
        kind: ReadingKind.kun,
        exampleWord: 'いま',
        exampleMeaning: '現在',
      ),
    ],
  ),
  KanjiEntry(
    char: '何',
    meaningZh: '什麼',
    readings: [
      Reading(
        text: 'なに',
        kind: ReadingKind.kun,
        exampleWord: 'なに',
        exampleMeaning: '什麼',
      ),
    ],
  ),
  KanjiEntry(
    char: '男',
    meaningZh: '男',
    readings: [
      Reading(
        text: 'おとこ',
        kind: ReadingKind.kun,
        exampleWord: 'おとこ',
        exampleMeaning: '男人',
      ),
    ],
  ),
  KanjiEntry(
    char: '女',
    meaningZh: '女',
    readings: [
      Reading(
        text: 'おんな',
        kind: ReadingKind.kun,
        exampleWord: 'おんな',
        exampleMeaning: '女人',
      ),
    ],
  ),
  KanjiEntry(
    char: '子',
    meaningZh: '孩子、子',
    readings: [
      Reading(
        text: 'こ',
        kind: ReadingKind.kun,
        exampleWord: 'こども',
        exampleMeaning: '小孩',
      ),
    ],
  ),
  KanjiEntry(
    char: '目',
    meaningZh: '眼睛',
    readings: [
      Reading(
        text: 'め',
        kind: ReadingKind.kun,
        exampleWord: 'め',
        exampleMeaning: '眼睛',
      ),
    ],
  ),
  KanjiEntry(
    char: '口',
    meaningZh: '嘴、口',
    readings: [
      Reading(
        text: 'くち',
        kind: ReadingKind.kun,
        exampleWord: 'くち',
        exampleMeaning: '嘴巴',
      ),
    ],
  ),
  KanjiEntry(
    char: '見',
    meaningZh: '看、見',
    readings: [
      Reading(
        text: 'み',
        kind: ReadingKind.kun,
        exampleWord: 'みる',
        exampleMeaning: '看',
      ),
    ],
  ),
  // ── N5 expansion: nature/season, people/life, actions/qualities. Readings
  // adversarially re-verified (two independent passes); on'yomi katakana,
  // kun'yomi hiragana; one example word + 繁中 gloss each. ──
  KanjiEntry(
    char: '天',
    meaningZh: '天、天空',
    readings: [
      Reading(
        text: 'テン',
        kind: ReadingKind.on,
        exampleWord: 'てんき',
        exampleMeaning: '天氣',
      ),
    ],
  ),
  KanjiEntry(
    char: '空',
    meaningZh: '天空、空虛',
    readings: [
      Reading(
        text: 'そら',
        kind: ReadingKind.kun,
        exampleWord: 'そら',
        exampleMeaning: '天空',
      ),
      Reading(
        text: 'クウ',
        kind: ReadingKind.on,
        exampleWord: 'くうき',
        exampleMeaning: '空氣',
      ),
    ],
  ),
  KanjiEntry(
    char: '雨',
    meaningZh: '雨',
    readings: [
      Reading(
        text: 'あめ',
        kind: ReadingKind.kun,
        exampleWord: 'あめ',
        exampleMeaning: '雨',
      ),
      Reading(
        text: 'ウ',
        kind: ReadingKind.on,
        exampleWord: 'うてん',
        exampleMeaning: '雨天',
      ),
    ],
  ),
  KanjiEntry(
    char: '雪',
    meaningZh: '雪',
    readings: [
      Reading(
        text: 'ゆき',
        kind: ReadingKind.kun,
        exampleWord: 'ゆき',
        exampleMeaning: '雪',
      ),
    ],
  ),
  KanjiEntry(
    char: '風',
    meaningZh: '風',
    readings: [
      Reading(
        text: 'かぜ',
        kind: ReadingKind.kun,
        exampleWord: 'かぜ',
        exampleMeaning: '風',
      ),
      Reading(
        text: 'フウ',
        kind: ReadingKind.on,
        exampleWord: 'たいふう',
        exampleMeaning: '颱風',
      ),
    ],
  ),
  KanjiEntry(
    char: '花',
    meaningZh: '花',
    readings: [
      Reading(
        text: 'はな',
        kind: ReadingKind.kun,
        exampleWord: 'はな',
        exampleMeaning: '花',
      ),
      Reading(
        text: 'カ',
        kind: ReadingKind.on,
        exampleWord: 'かびん',
        exampleMeaning: '花瓶',
      ),
    ],
  ),
  KanjiEntry(
    char: '草',
    meaningZh: '草',
    readings: [
      Reading(
        text: 'くさ',
        kind: ReadingKind.kun,
        exampleWord: 'くさ',
        exampleMeaning: '草',
      ),
    ],
  ),
  KanjiEntry(
    char: '林',
    meaningZh: '樹林',
    readings: [
      Reading(
        text: 'はやし',
        kind: ReadingKind.kun,
        exampleWord: 'はやし',
        exampleMeaning: '樹林',
      ),
      Reading(
        text: 'リン',
        kind: ReadingKind.on,
        exampleWord: 'しんりん',
        exampleMeaning: '森林',
      ),
    ],
  ),
  KanjiEntry(
    char: '森',
    meaningZh: '森林',
    readings: [
      Reading(
        text: 'もり',
        kind: ReadingKind.kun,
        exampleWord: 'もり',
        exampleMeaning: '森林',
      ),
      Reading(
        text: 'シン',
        kind: ReadingKind.on,
        exampleWord: 'しんりん',
        exampleMeaning: '森林',
      ),
    ],
  ),
  KanjiEntry(
    char: '海',
    meaningZh: '海',
    readings: [
      Reading(
        text: 'うみ',
        kind: ReadingKind.kun,
        exampleWord: 'うみ',
        exampleMeaning: '海',
      ),
      Reading(
        text: 'カイ',
        kind: ReadingKind.on,
        exampleWord: 'かいがい',
        exampleMeaning: '海外',
      ),
    ],
  ),
  KanjiEntry(
    char: '気',
    meaningZh: '氣、氣息',
    readings: [
      Reading(
        text: 'キ',
        kind: ReadingKind.on,
        exampleWord: 'てんき',
        exampleMeaning: '天氣',
      ),
    ],
  ),
  KanjiEntry(
    char: '雲',
    meaningZh: '雲',
    readings: [
      Reading(
        text: 'くも',
        kind: ReadingKind.kun,
        exampleWord: 'くも',
        exampleMeaning: '雲',
      ),
    ],
  ),
  KanjiEntry(
    char: '星',
    meaningZh: '星',
    readings: [
      Reading(
        text: 'ほし',
        kind: ReadingKind.kun,
        exampleWord: 'ほし',
        exampleMeaning: '星星',
      ),
      Reading(
        text: 'セイ',
        kind: ReadingKind.on,
        exampleWord: 'せいざ',
        exampleMeaning: '星座',
      ),
    ],
  ),
  KanjiEntry(
    char: '春',
    meaningZh: '春',
    readings: [
      Reading(
        text: 'はる',
        kind: ReadingKind.kun,
        exampleWord: 'はる',
        exampleMeaning: '春天',
      ),
    ],
  ),
  KanjiEntry(
    char: '夏',
    meaningZh: '夏',
    readings: [
      Reading(
        text: 'なつ',
        kind: ReadingKind.kun,
        exampleWord: 'なつ',
        exampleMeaning: '夏天',
      ),
    ],
  ),
  KanjiEntry(
    char: '秋',
    meaningZh: '秋',
    readings: [
      Reading(
        text: 'あき',
        kind: ReadingKind.kun,
        exampleWord: 'あき',
        exampleMeaning: '秋天',
      ),
    ],
  ),
  KanjiEntry(
    char: '冬',
    meaningZh: '冬',
    readings: [
      Reading(
        text: 'ふゆ',
        kind: ReadingKind.kun,
        exampleWord: 'ふゆ',
        exampleMeaning: '冬天',
      ),
    ],
  ),
  KanjiEntry(
    char: '朝',
    meaningZh: '早晨',
    readings: [
      Reading(
        text: 'あさ',
        kind: ReadingKind.kun,
        exampleWord: 'あさ',
        exampleMeaning: '早晨',
      ),
      Reading(
        text: 'チョウ',
        kind: ReadingKind.on,
        exampleWord: 'ちょうしょく',
        exampleMeaning: '早餐',
      ),
    ],
  ),
  KanjiEntry(
    char: '夜',
    meaningZh: '夜晚',
    readings: [
      Reading(
        text: 'よる',
        kind: ReadingKind.kun,
        exampleWord: 'よる',
        exampleMeaning: '夜晚',
      ),
      Reading(
        text: 'ヤ',
        kind: ReadingKind.on,
        exampleWord: 'やかん',
        exampleMeaning: '夜間',
      ),
    ],
  ),
  KanjiEntry(
    char: '父',
    meaningZh: '父親',
    readings: [
      Reading(
        text: 'ちち',
        kind: ReadingKind.kun,
        exampleWord: 'ちち',
        exampleMeaning: '（我）父親',
      ),
      Reading(
        text: 'フ',
        kind: ReadingKind.on,
        exampleWord: 'そふ',
        exampleMeaning: '祖父',
      ),
    ],
  ),
  KanjiEntry(
    char: '母',
    meaningZh: '母親',
    readings: [
      Reading(
        text: 'はは',
        kind: ReadingKind.kun,
        exampleWord: 'はは',
        exampleMeaning: '（我）母親',
      ),
      Reading(
        text: 'ボ',
        kind: ReadingKind.on,
        exampleWord: 'ぼこく',
        exampleMeaning: '母國',
      ),
    ],
  ),
  KanjiEntry(
    char: '友',
    meaningZh: '朋友',
    readings: [
      Reading(
        text: 'とも',
        kind: ReadingKind.kun,
        exampleWord: 'ともだち',
        exampleMeaning: '朋友',
      ),
      Reading(
        text: 'ユウ',
        kind: ReadingKind.on,
        exampleWord: 'ゆうじん',
        exampleMeaning: '友人',
      ),
    ],
  ),
  KanjiEntry(
    char: '先',
    meaningZh: '先、前',
    readings: [
      Reading(
        text: 'さき',
        kind: ReadingKind.kun,
        exampleWord: 'さき',
        exampleMeaning: '前頭、先前',
      ),
      Reading(
        text: 'セン',
        kind: ReadingKind.on,
        exampleWord: 'せんせい',
        exampleMeaning: '老師',
      ),
    ],
  ),
  KanjiEntry(
    char: '生',
    meaningZh: '生、活',
    readings: [
      Reading(
        text: 'セイ',
        kind: ReadingKind.on,
        exampleWord: 'がくせい',
        exampleMeaning: '學生',
      ),
      Reading(
        text: 'い',
        kind: ReadingKind.kun,
        exampleWord: 'いきる',
        exampleMeaning: '活著、生存',
      ),
    ],
  ),
  KanjiEntry(
    char: '学',
    meaningZh: '學習、學問',
    readings: [
      Reading(
        text: 'ガク',
        kind: ReadingKind.on,
        exampleWord: 'がっこう',
        exampleMeaning: '學校',
      ),
      Reading(
        text: 'まな',
        kind: ReadingKind.kun,
        exampleWord: 'まなぶ',
        exampleMeaning: '學習',
      ),
    ],
  ),
  KanjiEntry(
    char: '校',
    meaningZh: '學校',
    readings: [
      Reading(
        text: 'コウ',
        kind: ReadingKind.on,
        exampleWord: 'こうちょう',
        exampleMeaning: '校長',
      ),
    ],
  ),
  KanjiEntry(
    char: '家',
    meaningZh: '家、住處',
    readings: [
      Reading(
        text: 'いえ',
        kind: ReadingKind.kun,
        exampleWord: 'いえ',
        exampleMeaning: '家、房子',
      ),
      Reading(
        text: 'カ',
        kind: ReadingKind.on,
        exampleWord: 'かぞく',
        exampleMeaning: '家人、家族',
      ),
    ],
  ),
  KanjiEntry(
    char: '手',
    meaningZh: '手',
    readings: [
      Reading(
        text: 'て',
        kind: ReadingKind.kun,
        exampleWord: 'て',
        exampleMeaning: '手',
      ),
      Reading(
        text: 'シュ',
        kind: ReadingKind.on,
        exampleWord: 'せんしゅ',
        exampleMeaning: '選手',
      ),
    ],
  ),
  KanjiEntry(
    char: '耳',
    meaningZh: '耳朵',
    readings: [
      Reading(
        text: 'みみ',
        kind: ReadingKind.kun,
        exampleWord: 'みみ',
        exampleMeaning: '耳朵',
      ),
    ],
  ),
  KanjiEntry(
    char: '足',
    meaningZh: '腳、足',
    readings: [
      Reading(
        text: 'あし',
        kind: ReadingKind.kun,
        exampleWord: 'あし',
        exampleMeaning: '腳、足',
      ),
      Reading(
        text: 'ソク',
        kind: ReadingKind.on,
        exampleWord: 'えんそく',
        exampleMeaning: '遠足',
      ),
    ],
  ),
  KanjiEntry(
    char: '体',
    meaningZh: '身體',
    readings: [
      Reading(
        text: 'からだ',
        kind: ReadingKind.kun,
        exampleWord: 'からだ',
        exampleMeaning: '身體',
      ),
      Reading(
        text: 'タイ',
        kind: ReadingKind.on,
        exampleWord: 'たいいく',
        exampleMeaning: '體育',
      ),
    ],
  ),
  KanjiEntry(
    char: '名',
    meaningZh: '名字、名稱',
    readings: [
      Reading(
        text: 'な',
        kind: ReadingKind.kun,
        exampleWord: 'なまえ',
        exampleMeaning: '名字',
      ),
      Reading(
        text: 'メイ',
        kind: ReadingKind.on,
        exampleWord: 'ゆうめい',
        exampleMeaning: '有名',
      ),
    ],
  ),
  KanjiEntry(
    char: '言',
    meaningZh: '說、言語',
    readings: [
      Reading(
        text: 'い',
        kind: ReadingKind.kun,
        exampleWord: 'いう',
        exampleMeaning: '說',
      ),
      Reading(
        text: 'ゲン',
        kind: ReadingKind.on,
        exampleWord: 'げんご',
        exampleMeaning: '語言',
      ),
    ],
  ),
  KanjiEntry(
    char: '行',
    meaningZh: '去、行走',
    readings: [
      Reading(
        text: 'い',
        kind: ReadingKind.kun,
        exampleWord: 'いく',
        exampleMeaning: '去',
      ),
      Reading(
        text: 'コウ',
        kind: ReadingKind.on,
        exampleWord: 'りょこう',
        exampleMeaning: '旅行',
      ),
    ],
  ),
  KanjiEntry(
    char: '来',
    meaningZh: '來、來臨',
    readings: [
      Reading(
        text: 'く',
        kind: ReadingKind.kun,
        exampleWord: 'くる',
        exampleMeaning: '來',
      ),
      Reading(
        text: 'ライ',
        kind: ReadingKind.on,
        exampleWord: 'らいねん',
        exampleMeaning: '明年',
      ),
    ],
  ),
  KanjiEntry(
    char: '食',
    meaningZh: '吃、食物',
    readings: [
      Reading(
        text: 'た',
        kind: ReadingKind.kun,
        exampleWord: 'たべる',
        exampleMeaning: '吃',
      ),
      Reading(
        text: 'ショク',
        kind: ReadingKind.on,
        exampleWord: 'しょくじ',
        exampleMeaning: '用餐、飲食',
      ),
    ],
  ),
  KanjiEntry(
    char: '飲',
    meaningZh: '喝、飲',
    readings: [
      Reading(
        text: 'の',
        kind: ReadingKind.kun,
        exampleWord: 'のむ',
        exampleMeaning: '喝',
      ),
      Reading(
        text: 'イン',
        kind: ReadingKind.on,
        exampleWord: 'いんしょく',
        exampleMeaning: '飲食',
      ),
    ],
  ),
  KanjiEntry(
    char: '出',
    meaningZh: '出、外出',
    readings: [
      Reading(
        text: 'で',
        kind: ReadingKind.kun,
        exampleWord: 'でる',
        exampleMeaning: '出去、出來',
      ),
      Reading(
        text: 'シュツ',
        kind: ReadingKind.on,
        exampleWord: 'しゅっせき',
        exampleMeaning: '出席',
      ),
    ],
  ),
  KanjiEntry(
    char: '入',
    meaningZh: '進、放入',
    readings: [
      Reading(
        text: 'はい',
        kind: ReadingKind.kun,
        exampleWord: 'はいる',
        exampleMeaning: '進入',
      ),
      Reading(
        text: 'ニュウ',
        kind: ReadingKind.on,
        exampleWord: 'にゅうがく',
        exampleMeaning: '入學',
      ),
    ],
  ),
  KanjiEntry(
    char: '立',
    meaningZh: '站、立',
    readings: [
      Reading(
        text: 'た',
        kind: ReadingKind.kun,
        exampleWord: 'たつ',
        exampleMeaning: '站立',
      ),
      Reading(
        text: 'リツ',
        kind: ReadingKind.on,
        exampleWord: 'こくりつ',
        exampleMeaning: '國立',
      ),
    ],
  ),
  KanjiEntry(
    char: '休',
    meaningZh: '休息',
    readings: [
      Reading(
        text: 'やす',
        kind: ReadingKind.kun,
        exampleWord: 'やすむ',
        exampleMeaning: '休息',
      ),
      Reading(
        text: 'キュウ',
        kind: ReadingKind.on,
        exampleWord: 'きゅうじつ',
        exampleMeaning: '假日',
      ),
    ],
  ),
  KanjiEntry(
    char: '話',
    meaningZh: '說話、故事',
    readings: [
      Reading(
        text: 'はな',
        kind: ReadingKind.kun,
        exampleWord: 'はなす',
        exampleMeaning: '說話',
      ),
      Reading(
        text: 'ワ',
        kind: ReadingKind.on,
        exampleWord: 'かいわ',
        exampleMeaning: '會話',
      ),
    ],
  ),
  KanjiEntry(
    char: '聞',
    meaningZh: '聽、聞',
    readings: [
      Reading(
        text: 'き',
        kind: ReadingKind.kun,
        exampleWord: 'きく',
        exampleMeaning: '聽、詢問',
      ),
      Reading(
        text: 'ブン',
        kind: ReadingKind.on,
        exampleWord: 'しんぶん',
        exampleMeaning: '報紙',
      ),
    ],
  ),
  KanjiEntry(
    char: '読',
    meaningZh: '讀、閱讀',
    readings: [
      Reading(
        text: 'よ',
        kind: ReadingKind.kun,
        exampleWord: 'よむ',
        exampleMeaning: '讀、閱讀',
      ),
      Reading(
        text: 'ドク',
        kind: ReadingKind.on,
        exampleWord: 'どくしょ',
        exampleMeaning: '讀書',
      ),
    ],
  ),
  KanjiEntry(
    char: '書',
    meaningZh: '寫、書寫',
    readings: [
      Reading(
        text: 'か',
        kind: ReadingKind.kun,
        exampleWord: 'かく',
        exampleMeaning: '寫',
      ),
      Reading(
        text: 'ショ',
        kind: ReadingKind.on,
        exampleWord: 'じしょ',
        exampleMeaning: '字典',
      ),
    ],
  ),
  KanjiEntry(
    char: '多',
    meaningZh: '多',
    readings: [
      Reading(
        text: 'おお',
        kind: ReadingKind.kun,
        exampleWord: 'おおい',
        exampleMeaning: '多的',
      ),
      Reading(
        text: 'タ',
        kind: ReadingKind.on,
        exampleWord: 'たぶん',
        exampleMeaning: '大概、多半',
      ),
    ],
  ),
  KanjiEntry(
    char: '少',
    meaningZh: '少',
    readings: [
      Reading(
        text: 'すく',
        kind: ReadingKind.kun,
        exampleWord: 'すくない',
        exampleMeaning: '少的',
      ),
      Reading(
        text: 'ショウ',
        kind: ReadingKind.on,
        exampleWord: 'しょうしょう',
        exampleMeaning: '稍微、少許',
      ),
    ],
  ),
  KanjiEntry(
    char: '新',
    meaningZh: '新',
    readings: [
      Reading(
        text: 'あたら',
        kind: ReadingKind.kun,
        exampleWord: 'あたらしい',
        exampleMeaning: '新的',
      ),
      Reading(
        text: 'シン',
        kind: ReadingKind.on,
        exampleWord: 'しんぶん',
        exampleMeaning: '報紙',
      ),
    ],
  ),
  KanjiEntry(
    char: '古',
    meaningZh: '舊、古老',
    readings: [
      Reading(
        text: 'ふる',
        kind: ReadingKind.kun,
        exampleWord: 'ふるい',
        exampleMeaning: '舊的',
      ),
      Reading(
        text: 'コ',
        kind: ReadingKind.on,
        exampleWord: 'ちゅうこ',
        exampleMeaning: '中古、二手',
      ),
    ],
  ),
  KanjiEntry(
    char: '高',
    meaningZh: '高、貴',
    readings: [
      Reading(
        text: 'たか',
        kind: ReadingKind.kun,
        exampleWord: 'たかい',
        exampleMeaning: '高的、貴的',
      ),
      Reading(
        text: 'コウ',
        kind: ReadingKind.on,
        exampleWord: 'こうこう',
        exampleMeaning: '高中',
      ),
    ],
  ),
  KanjiEntry(
    char: '安',
    meaningZh: '便宜、安心',
    readings: [
      Reading(
        text: 'やす',
        kind: ReadingKind.kun,
        exampleWord: 'やすい',
        exampleMeaning: '便宜的',
      ),
      Reading(
        text: 'アン',
        kind: ReadingKind.on,
        exampleWord: 'あんしん',
        exampleMeaning: '安心',
      ),
    ],
  ),
  KanjiEntry(
    char: '長',
    meaningZh: '長、首長',
    readings: [
      Reading(
        text: 'なが',
        kind: ReadingKind.kun,
        exampleWord: 'ながい',
        exampleMeaning: '長的',
      ),
      Reading(
        text: 'チョウ',
        kind: ReadingKind.on,
        exampleWord: 'しゃちょう',
        exampleMeaning: '社長',
      ),
    ],
  ),
];
