// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// Grammar-pattern sentences for 《大家的日本語》 I, lessons 20–25.
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
/// A handful of kanji here carry furigana with NO reading id on purpose —
/// real, honest readings (私, 料理, 降る, 忙しい, 着く, 教える, 貸す, 咲く,
/// 晴れる, 何回) that are simply not yet in the course. Time nouns with an
/// irregular whole-word reading (きょう, きのう, あした, ゆうべ) are written
/// in plain kana rather than split into a wrong per-kanji furigana.
///
/// Pure data: no `package:flutter/*` imports.
const List<KanjiPhrase> kMinnaL20to25 = <KanjiPhrase>[
  // ── L20: 普通形(行く・行かない・行った・行かなかった)──
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちと'),
      RubySegment(text: '海', furigana: 'うみ'),
      RubySegment(text: 'に'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'く'),
    ],
    romaji: 'tomodachi to umi ni iku',
    meaning: '跟朋友一起去海邊。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'きょうは'),
      RubySegment(text: '会', furigana: 'かい'),
      RubySegment(text: '社', furigana: 'しゃ'),
      RubySegment(text: 'に'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'かない'),
    ],
    romaji: 'kyou wa kaisha ni ikanai',
    meaning: '今天不去公司。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'きのう'),
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'った'),
    ],
    romaji: 'kinou atarashii hon o katta',
    meaning: '昨天買了新書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ゆうべ'),
      RubySegment(text: '水', furigana: 'みず'),
      RubySegment(text: 'を'),
      RubySegment(text: '飲', furigana: 'の'),
      RubySegment(text: 'まなかった'),
    ],
    romaji: 'yuube mizu o nomanakatta',
    meaning: '昨晚沒有喝水。',
  ),

  // ── L20: 形容詞の普通形 ──
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'は'),
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
    ],
    romaji: 'kono mise wa atarashii',
    meaning: '這家店是新開的。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あの'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'は'),
      RubySegment(text: '高', furigana: 'たか'),
      RubySegment(text: 'くない'),
    ],
    romaji: 'ano hon wa takakunai',
    meaning: '那本書不貴。',
  ),

  // ── L21: 〜と思います ──
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あした'),
      RubySegment(text: 'は'),
      RubySegment(text: '雨', furigana: 'あめ'),
      RubySegment(text: 'が'),
      RubySegment(text: '降', furigana: 'ふ'),
      RubySegment(text: 'ると'),
      RubySegment(text: '思', furigana: 'おも'),
      RubySegment(text: 'います'),
    ],
    romaji: 'ashita wa ame ga furu to omoimasu',
    meaning: '我覺得明天會下雨。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'は'),
      RubySegment(text: 'おもしろいと'),
      RubySegment(text: '思', furigana: 'おも'),
      RubySegment(text: 'います'),
    ],
    romaji: 'kono hon wa omoshiroi to omoimasu',
    meaning: '我覺得這本書很有趣。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '田', furigana: 'た'),
      RubySegment(text: '中', furigana: 'なか'),
      RubySegment(text: 'さんは'),
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'だと'),
      RubySegment(text: '思', furigana: 'おも'),
      RubySegment(text: 'います'),
    ],
    romaji: 'tanaka san wa sensei da to omoimasu',
    meaning: '我覺得田中先生是老師。',
  ),

  // ── L21: 〜と言いました ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちは'),
      RubySegment(text: 'あした'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'くと'),
      RubySegment(text: '言', furigana: 'い'),
      RubySegment(text: 'いました'),
    ],
    romaji: 'tomodachi wa ashita iku to iimashita',
    meaning: '朋友說明天要去。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'は'),
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'が'),
      RubySegment(text: 'できたと'),
      RubySegment(text: '言', furigana: 'い'),
      RubySegment(text: 'いました'),
    ],
    romaji: 'sensei wa atarashii mise ga dekita to iimashita',
    meaning: '老師說有一家新店開了。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '母', furigana: 'はは'),
      RubySegment(text: 'は'),
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'まで'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'くと'),
      RubySegment(text: '言', furigana: 'い'),
      RubySegment(text: 'いました'),
    ],
    romaji: 'haha wa eki made aruku to iimashita',
    meaning: '媽媽說要走到車站。',
  ),

  // ── L21: 〜でしょう ──
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あした'),
      RubySegment(text: 'は'),
      RubySegment(text: '晴', furigana: 'は'),
      RubySegment(text: 'れるでしょう'),
    ],
    romaji: 'ashita wa hareru deshou',
    meaning: '明天大概會放晴吧。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '道', furigana: 'みち'),
      RubySegment(text: 'は'),
      RubySegment(text: '近', furigana: 'ちか'),
      RubySegment(text: 'いでしょう'),
    ],
    romaji: 'kono michi wa chikai deshou',
    meaning: '這條路應該很近吧。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あの'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'は'),
      RubySegment(text: '高', furigana: 'たか'),
      RubySegment(text: 'いでしょう'),
    ],
    romaji: 'ano mise wa takai deshou',
    meaning: '那家店應該很貴吧。',
  ),

  // ── L22: 名詞修飾(關係子句)──
  KanjiPhrase(
    segments: [
      RubySegment(text: 'きのう'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'った'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'は'),
      RubySegment(text: 'おもしろかったです'),
    ],
    romaji: 'kinou katta hon wa omoshirokatta desu',
    meaning: '昨天買的書很有趣。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちが'),
      RubySegment(text: '作', furigana: 'つく'),
      RubySegment(text: 'った'),
      RubySegment(text: '料', furigana: 'りょう'),
      RubySegment(text: '理', furigana: 'り'),
      RubySegment(text: 'は'),
      RubySegment(text: 'おいしかったです'),
    ],
    romaji: 'tomodachi ga tsukutta ryouri wa oishikatta desu',
    meaning: '朋友做的菜很好吃。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'で'),
      RubySegment(text: '待', furigana: 'ま'),
      RubySegment(text: 'っている'),
      RubySegment(text: '人', furigana: 'ひと'),
      RubySegment(text: 'は'),
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'です'),
    ],
    romaji: 'eki de matte iru hito wa sensei desu',
    meaning: '在車站等的人是老師。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'これは'),
      RubySegment(text: '母', furigana: 'はは'),
      RubySegment(text: 'が'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'んでいる'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'です'),
    ],
    romaji: 'kore wa haha ga yonde iru hon desu',
    meaning: '這是媽媽正在讀的書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま'),
      RubySegment(text: 'に'),
      RubySegment(text: '住', furigana: 'す'),
      RubySegment(text: 'んでいる'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'いました'),
    ],
    romaji: 'yama ni sunde iru tomodachi ni aimashita',
    meaning: '見到了住在山上的朋友。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'の'),
      RubySegment(text: '近', furigana: 'ちか'),
      RubySegment(text: 'くに'),
      RubySegment(text: 'できた'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'で'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'い'),
      RubySegment(text: '物', furigana: 'もの'),
      RubySegment(text: 'を'),
      RubySegment(text: 'しました'),
    ],
    romaji: 'eki no chikaku ni dekita mise de kaimono o shimashita',
    meaning: '在車站附近新開的店買了東西。',
  ),

  // ── L23: 〜とき ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ'),
      RubySegment(text: 'に'),
      RubySegment(text: '帰', furigana: 'かえ'),
      RubySegment(text: 'るとき'),
      RubySegment(text: '雨', furigana: 'あめ'),
      RubySegment(text: 'が'),
      RubySegment(text: '降', furigana: 'ふ'),
      RubySegment(text: 'っていました'),
    ],
    romaji: 'ie ni kaeru toki ame ga futte imashita',
    meaning: '回家的時候正下著雨。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '忙', furigana: 'いそが'),
      RubySegment(text: 'しいとき'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'みません'),
    ],
    romaji: 'isogashii toki hon o yomimasen',
    meaning: '忙碌的時候不看書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '子', furigana: 'こ'),
      RubySegment(text: 'どもの'),
      RubySegment(text: 'とき'),
      RubySegment(text: '山', furigana: 'やま'),
      RubySegment(text: 'に'),
      RubySegment(text: '住', furigana: 'す'),
      RubySegment(text: 'んでいました'),
    ],
    romaji: 'kodomo no toki yama ni sunde imashita',
    meaning: '小時候住在山上。',
  ),

  // ── L23: 〜と(條件)──
  KanjiPhrase(
    segments: [
      RubySegment(text: '春', furigana: 'はる'),
      RubySegment(text: 'に'),
      RubySegment(text: 'なると'),
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'が'),
      RubySegment(text: '咲', furigana: 'さ'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'haru ni naru to hana ga sakimasu',
    meaning: '一到春天花就會開。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '朝', furigana: 'あさ'),
      RubySegment(text: '早', furigana: 'はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '起', furigana: 'お'),
      RubySegment(text: 'きると'),
      RubySegment(text: '気', furigana: 'き'),
      RubySegment(text: '持', furigana: 'も'),
      RubySegment(text: 'ちが'),
      RubySegment(text: 'いいです'),
    ],
    romaji: 'asa hayaku okiru to kimochi ga ii desu',
    meaning: '早起會覺得很舒服。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'に'),
      RubySegment(text: '着', furigana: 'つ'),
      RubySegment(text: 'くと'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちが'),
      RubySegment(text: '待', furigana: 'ま'),
      RubySegment(text: 'っていました'),
    ],
    romaji: 'eki ni tsuku to tomodachi ga matte imashita',
    meaning: '一到車站朋友就在等著了。',
  ),

  // ── L24: くれます/あげます/もらいます ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちが'),
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: 'くれました'),
    ],
    romaji: 'tomodachi ga watashi ni hon o kuremashita',
    meaning: '朋友給了我一本書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'が'),
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'に'),
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: 'くれました'),
    ],
    romaji: 'sensei ga watashi ni hana o kuremashita',
    meaning: '老師給了我花。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: 'あげました'),
    ],
    romaji: 'watashi wa tomodachi ni hon o agemashita',
    meaning: '我送了朋友一本書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '母', furigana: 'はは'),
      RubySegment(text: 'は'),
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'に'),
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: 'あげました'),
    ],
    romaji: 'haha wa sensei ni hana o agemashita',
    meaning: '媽媽送花給老師。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: 'もらいました'),
    ],
    romaji: 'watashi wa tomodachi ni hon o moraimashita',
    meaning: '我從朋友那裡收到了一本書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'から'),
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: 'もらいました'),
    ],
    romaji: 'watashi wa sensei kara hana o moraimashita',
    meaning: '我從老師那裡收到了花。',
  ),

  // ── L24: 〜てくれます・〜てあげます・〜てもらいます ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちが'),
      RubySegment(text: '道', furigana: 'みち'),
      RubySegment(text: 'を'),
      RubySegment(text: '教', furigana: 'おし'),
      RubySegment(text: 'えてくれました'),
    ],
    romaji: 'tomodachi ga michi o oshiete kuremashita',
    meaning: '朋友告訴我怎麼走。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'が'),
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '貸', furigana: 'か'),
      RubySegment(text: 'してくれました'),
    ],
    romaji: 'sensei ga atarashii hon o kashite kuremashita',
    meaning: '老師借了新書給我。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '道', furigana: 'みち'),
      RubySegment(text: 'を'),
      RubySegment(text: '教', furigana: 'おし'),
      RubySegment(text: 'えてあげました'),
    ],
    romaji: 'watashi wa tomodachi ni michi o oshiete agemashita',
    meaning: '我告訴朋友怎麼走。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '父', furigana: 'ちち'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '貸', furigana: 'か'),
      RubySegment(text: 'してあげました'),
    ],
    romaji: 'watashi wa chichi ni hon o kashite agemashita',
    meaning: '我借了一本書給爸爸。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '道', furigana: 'みち'),
      RubySegment(text: 'を'),
      RubySegment(text: '教', furigana: 'おし'),
      RubySegment(text: 'えてもらいました'),
    ],
    romaji: 'watashi wa tomodachi ni michi o oshiete moraimashita',
    meaning: '我請朋友告訴我怎麼走。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '私', furigana: 'わたし'),
      RubySegment(text: 'は'),
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '貸', furigana: 'か'),
      RubySegment(text: 'してもらいました'),
    ],
    romaji: 'watashi wa sensei ni hon o kashite moraimashita',
    meaning: '我向老師借了一本書。',
  ),

  // ── L25: 〜たら ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '雨', furigana: 'あめ'),
      RubySegment(text: 'が'),
      RubySegment(text: '降', furigana: 'ふ'),
      RubySegment(text: 'ったら'),
      RubySegment(text: '家', furigana: 'いえ'),
      RubySegment(text: 'に'),
      RubySegment(text: 'います'),
    ],
    romaji: 'ame ga futtara ie ni imasu',
    meaning: '如果下雨的話就待在家裡。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'に'),
      RubySegment(text: '着', furigana: 'つ'),
      RubySegment(text: 'いたら'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'います'),
    ],
    romaji: 'eki ni tsuitara tomodachi ni aimasu',
    meaning: '到了車站就要跟朋友見面。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'んだら'),
      RubySegment(text: '貸', furigana: 'か'),
      RubySegment(text: 'してあげます'),
    ],
    romaji: 'atarashii hon o yondara kashite agemasu',
    meaning: '等我讀完這本新書,就借給你。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '時', furigana: 'じ'),
      RubySegment(text: '間', furigana: 'かん'),
      RubySegment(text: 'があったら'),
      RubySegment(text: '海', furigana: 'うみ'),
      RubySegment(text: 'に'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'きたいです'),
    ],
    romaji: 'jikan ga attara umi ni ikitai desu',
    meaning: '如果有時間的話想去海邊。',
  ),

  // ── L25: 〜ても ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '雨', furigana: 'あめ'),
      RubySegment(text: 'が'),
      RubySegment(text: '降', furigana: 'ふ'),
      RubySegment(text: 'っても'),
      RubySegment(text: '出', furigana: 'で'),
      RubySegment(text: 'かけます'),
    ],
    romaji: 'ame ga futte mo dekakemasu',
    meaning: '就算下雨也要出門。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '何', furigana: 'なん'),
      RubySegment(text: '回', furigana: 'かい'),
      RubySegment(text: '聞', furigana: 'き'),
      RubySegment(text: 'いても'),
      RubySegment(text: '分', furigana: 'わ'),
      RubySegment(text: 'かりません'),
    ],
    romaji: 'nankai kiite mo wakarimasen',
    meaning: '不管聽幾次都不懂。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '高', furigana: 'たか'),
      RubySegment(text: 'くても'),
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'います'),
    ],
    romaji: 'takakute mo atarashii hon o kaimasu',
    meaning: '就算貴也要買新書。',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '忙', furigana: 'いそが'),
      RubySegment(text: 'しくても'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'います'),
    ],
    romaji: 'isogashikute mo tomodachi ni aimasu',
    meaning: '再忙也要跟朋友見面。',
  ),
];
