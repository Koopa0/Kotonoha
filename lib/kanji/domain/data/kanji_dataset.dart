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
];
