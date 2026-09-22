// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// Travel spellings met in words and kana phrases, now read in context.
/// Original sentences: two contexts for each newly covered travel word so
/// practice can vary the sentence without changing the word's reading unit.
/// These segments feed both 漢字の声 recall and 名残の仮名 reading.
const List<KanjiPhrase> kTravelReadings = [
  KanjiPhrase(
    segments: [
      RubySegment(text: 'このバスは'),
      RubySegment(text: '空港', furigana: 'くうこう'),
      RubySegment(text: 'に'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'きますか'),
    ],
    romaji: 'kono basu wa kuukou ni ikimasu ka',
    meaning: '這班公車有到機場嗎',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '空港', furigana: 'くうこう'),
      RubySegment(text: 'までお'),
      RubySegment(text: '願', furigana: 'ねが'),
      RubySegment(text: 'いします'),
    ],
    romaji: 'kuukou made onegai shimasu',
    meaning: '請到機場',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '飛行機', furigana: 'ひこうき'),
      RubySegment(text: 'に'),
      RubySegment(text: '乗', furigana: 'の'),
      RubySegment(text: 'ります'),
    ],
    romaji: 'hikouki ni norimasu',
    meaning: '搭飛機',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '飛行機', furigana: 'ひこうき'),
      RubySegment(text: 'が'),
      RubySegment(text: '見', furigana: 'み'),
      RubySegment(text: 'えます'),
    ],
    romaji: 'hikouki ga miemasu',
    meaning: '看得見飛機',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '荷物', furigana: 'にもつ'),
      RubySegment(text: 'はここに'),
      RubySegment(text: '置', furigana: 'お'),
      RubySegment(text: 'いてください'),
    ],
    romaji: 'nimotsu wa koko ni oite kudasai',
    meaning: '請把行李放在這裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '荷物', furigana: 'にもつ'),
      RubySegment(text: 'を'),
      RubySegment(text: '持', furigana: 'も'),
      RubySegment(text: 'ちます'),
    ],
    romaji: 'nimotsu o mochimasu',
    meaning: '拿行李',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '改札', furigana: 'かいさつ'),
      RubySegment(text: 'はどこですか'),
    ],
    romaji: 'kaisatsu wa doko desu ka',
    meaning: '驗票閘門在哪裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '改札', furigana: 'かいさつ'),
      RubySegment(text: 'で'),
      RubySegment(text: '待', furigana: 'ま'),
      RubySegment(text: 'ちます'),
    ],
    romaji: 'kaisatsu de machimasu',
    meaning: '在驗票閘門等',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '予約', furigana: 'よやく'),
      RubySegment(text: 'があります'),
    ],
    romaji: 'yoyaku ga arimasu',
    meaning: '我有預約',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '予約', furigana: 'よやく'),
      RubySegment(text: 'を'),
      RubySegment(text: '確認', furigana: 'かくにん'),
      RubySegment(text: 'します'),
    ],
    romaji: 'yoyaku o kakunin shimasu',
    meaning: '確認預約',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '乗', furigana: 'の'),
      RubySegment(text: 'り'),
      RubySegment(text: '換', furigana: 'か'),
      RubySegment(text: 'えはどこですか'),
    ],
    romaji: 'norikae wa doko desu ka',
    meaning: '在哪裡轉乘',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'で'),
      RubySegment(text: '乗', furigana: 'の'),
      RubySegment(text: 'り'),
      RubySegment(text: '換', furigana: 'か'),
      RubySegment(text: 'えます'),
    ],
    romaji: 'kono eki de norikaemasu',
    meaning: '在這個車站轉乘',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '両替', furigana: 'りょうがえ'),
      RubySegment(text: 'はどこでできますか'),
    ],
    romaji: 'ryougae wa doko de dekimasu ka',
    meaning: '哪裡可以換錢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '空港', furigana: 'くうこう'),
      RubySegment(text: 'で'),
      RubySegment(text: '両替', furigana: 'りょうがえ'),
      RubySegment(text: 'をします'),
    ],
    romaji: 'kuukou de ryougae o shimasu',
    meaning: '在機場換錢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'お'),
      RubySegment(text: '土産', furigana: 'みやげ'),
      RubySegment(text: 'を'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'います'),
    ],
    romaji: 'omiyage o kaimasu',
    meaning: '買伴手禮',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'お'),
      RubySegment(text: '土産', furigana: 'みやげ'),
      RubySegment(text: 'はかばんに'),
      RubySegment(text: '入', furigana: 'い'),
      RubySegment(text: 'れます'),
    ],
    romaji: 'omiyage wa kaban ni iremasu',
    meaning: '把伴手禮放進包包',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'はどこ'),
    ],
    romaji: 'eki wa doko',
    meaning: '車站在哪裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'カードは'),
      RubySegment(text: '使', furigana: 'つか'),
      RubySegment(text: 'えません'),
    ],
    romaji: 'kaado wa tsukaemasen',
    meaning: '不能用卡',
  ),
];
