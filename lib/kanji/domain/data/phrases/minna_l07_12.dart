// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// Grammar-pattern sentences for 《大家的日本語》 I, lessons 7–12.
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
/// Pure data: no `package:flutter/*` imports.
const List<KanjiPhrase> kMinnaL07to12 = <KanjiPhrase>[
  // 文型:Toolで V ──────────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ペンで'),
      RubySegment(text: '書', furigana: 'か', readingId: 'reading:書#か'),
      RubySegment(text: 'く'),
    ],
    romaji: 'pen de kaku',
    meaning: '用筆寫',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'はしで'),
      RubySegment(text: '食', furigana: 'た', readingId: 'reading:食#た'),
      RubySegment(text: 'べる'),
    ],
    romaji: 'hashi de taberu',
    meaning: '用筷子吃',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '手', furigana: 'て', readingId: 'reading:手#て'),
      RubySegment(text: 'で'),
      RubySegment(text: '作', furigana: 'つく', readingId: 'reading:作#つく'),
      RubySegment(text: 'る'),
    ],
    romaji: 'te de tsukuru',
    meaning: '用手做',
  ),

  // 文型:人にNをあげます・もらいます ──────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: 'に'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'を'),
      RubySegment(text: 'あげる'),
    ],
    romaji: 'tomo ni hana o ageru',
    meaning: '送花給朋友',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '父', furigana: 'ちち', readingId: 'reading:父#ちち'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: 'あげる'),
    ],
    romaji: 'chichi ni hon o ageru',
    meaning: '送書給父親',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: 'もらう'),
    ],
    romaji: 'sensei ni hon o morau',
    meaning: '從老師那裡得到書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '母', furigana: 'はは', readingId: 'reading:母#はは'),
      RubySegment(text: 'に'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'を'),
      RubySegment(text: 'もらう'),
    ],
    romaji: 'haha ni hana o morau',
    meaning: '從母親那裡得到花',
  ),

  // 文型:もう〜ました ────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'もう'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ', readingId: 'reading:読#よ'),
      RubySegment(text: 'みました'),
    ],
    romaji: 'mou hon o yomimashita',
    meaning: '已經看完書了',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'もう'),
      RubySegment(text: '手', furigana: 'て', readingId: 'reading:手#て'),
      RubySegment(text: '紙', furigana: 'がみ'),
      RubySegment(text: 'を'),
      RubySegment(text: '書', furigana: 'か', readingId: 'reading:書#か'),
      RubySegment(text: 'きました'),
    ],
    romaji: 'mou tegami o kakimashita',
    meaning: '已經寫完信了',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'もうご'),
      RubySegment(text: '飯', furigana: 'はん'),
      RubySegment(text: 'を'),
      RubySegment(text: '食', furigana: 'た', readingId: 'reading:食#た'),
      RubySegment(text: 'べました'),
    ],
    romaji: 'mou gohan o tabemashita',
    meaning: '已經吃飯了',
  ),

  // 文型:な形容詞 ────────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'にぎやかな'),
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
    ],
    romaji: 'nigiyaka na machi',
    meaning: '熱鬧的城鎮',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '元', furigana: 'げん'),
      RubySegment(text: '気', furigana: 'き', readingId: 'reading:気#キ'),
      RubySegment(text: 'な'),
      RubySegment(text: '子', furigana: 'こ', readingId: 'reading:子#こ'),
    ],
    romaji: 'genki na ko',
    meaning: '有精神的孩子',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '有', furigana: 'ゆう'),
      RubySegment(text: '名', furigana: 'めい', readingId: 'reading:名#メイ'),
      RubySegment(text: 'な'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'yuumei na mise',
    meaning: '有名的店',
  ),

  // 文型:い形容詞 ────────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '古', furigana: 'ふる', readingId: 'reading:古#ふる'),
      RubySegment(text: 'い'),
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'furui ie desu',
    meaning: '房子很舊',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '安', furigana: 'やす', readingId: 'reading:安#やす'),
      RubySegment(text: 'い'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'です'),
    ],
    romaji: 'yasui mise desu',
    meaning: '這家店很便宜',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '高', furigana: 'たか', readingId: 'reading:高#たか'),
      RubySegment(text: 'い'),
      RubySegment(text: '木', furigana: 'き', readingId: 'reading:木#き'),
      RubySegment(text: 'です'),
    ],
    romaji: 'takai ki desu',
    meaning: '這棵樹很高',
  ),

  // 文型:〜が(逆接) ─────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '安', furigana: 'やす', readingId: 'reading:安#やす'),
      RubySegment(text: 'いですが'),
      RubySegment(text: '遠', furigana: 'とお'),
      RubySegment(text: 'いです'),
    ],
    romaji: 'yasui desu ga tooi desu',
    meaning: '便宜但是很遠',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'あたら', readingId: 'reading:新#あたら'),
      RubySegment(text: 'しいですが'),
      RubySegment(text: '高', furigana: 'たか', readingId: 'reading:高#たか'),
      RubySegment(text: 'いです'),
    ],
    romaji: 'atarashii desu ga takai desu',
    meaning: '雖然新但是很貴',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'いですが'),
      RubySegment(text: '小', furigana: 'ちい', readingId: 'reading:小#ちい'),
      RubySegment(text: 'さいです'),
    ],
    romaji: 'chikai desu ga chiisai desu',
    meaning: '雖然近但是很小',
  ),

  // 文型:どんな N ────────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'どんな'),
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'に'),
      RubySegment(text: '住', furigana: 'す', readingId: 'reading:住#す'),
      RubySegment(text: 'みますか'),
    ],
    romaji: 'donna ie ni sumimasu ka',
    meaning: '要住在什麼樣的房子呢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'どんな'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'が'),
      RubySegment(text: '好', furigana: 'す'),
      RubySegment(text: 'きですか'),
    ],
    romaji: 'donna hon ga suki desu ka',
    meaning: '喜歡什麼樣的書呢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'どんな'),
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'に'),
      RubySegment(text: '住', furigana: 'す', readingId: 'reading:住#す'),
      RubySegment(text: 'みますか'),
    ],
    romaji: 'donna machi ni sumimasu ka',
    meaning: '要住在什麼樣的城鎮呢',
  ),

  // 文型:Nが好きです・上手です・わかります ─────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'が'),
      RubySegment(text: '好', furigana: 'す'),
      RubySegment(text: 'きです'),
    ],
    romaji: 'hana ga suki desu',
    meaning: '喜歡花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '料', furigana: 'りょう'),
      RubySegment(text: '理', furigana: 'り'),
      RubySegment(text: 'が'),
      RubySegment(text: '上', furigana: 'じょう'),
      RubySegment(text: '手', furigana: 'ず'),
      RubySegment(text: 'です'),
    ],
    romaji: 'ryouri ga jouzu desu',
    meaning: '擅長做菜',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '日', furigana: 'に'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: '語', furigana: 'ご', readingId: 'reading:語#ゴ'),
      RubySegment(text: 'が'),
      RubySegment(text: 'わかります'),
    ],
    romaji: 'nihongo ga wakarimasu',
    meaning: '懂日語',
  ),

  // 文型:Nがあります(所有) ────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: '間', furigana: 'かん', readingId: 'reading:間#カン'),
      RubySegment(text: 'が'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'jikan ga arimasu',
    meaning: '有時間',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'お'),
      RubySegment(text: '金', furigana: 'かね', readingId: 'reading:金#かね'),
      RubySegment(text: 'が'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'okane ga arimasu',
    meaning: '有錢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '用', furigana: 'よう'),
      RubySegment(text: '事', furigana: 'じ'),
      RubySegment(text: 'が'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'youji ga arimasu',
    meaning: '有事情要辦',
  ),

  // 文型:〜から(理由) ──────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '雨', furigana: 'あめ', readingId: 'reading:雨#あめ'),
      RubySegment(text: 'ですから'),
      RubySegment(text: '休', furigana: 'やす', readingId: 'reading:休#やす'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'ame desu kara yasumimasu',
    meaning: '因為下雨所以休息',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '忙', furigana: 'いそが'),
      RubySegment(text: 'しいですから'),
      RubySegment(text: '帰', furigana: 'かえ', readingId: 'reading:帰#かえ'),
      RubySegment(text: 'ります'),
    ],
    romaji: 'isogashii desu kara kaerimasu',
    meaning: '因為很忙所以要回去了',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '安', furigana: 'やす', readingId: 'reading:安#やす'),
      RubySegment(text: 'いですから'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'います'),
    ],
    romaji: 'yasui desu kara kaimasu',
    meaning: '因為便宜所以要買',
  ),

  // 文型:どうして ────────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'どうして'),
      RubySegment(text: '休', furigana: 'やす', readingId: 'reading:休#やす'),
      RubySegment(text: 'みますか'),
    ],
    romaji: 'doushite yasumimasu ka',
    meaning: '為什麼要休息呢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'どうして'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'いますか'),
    ],
    romaji: 'doushite hon o kaimasu ka',
    meaning: '為什麼要買書呢',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'どうして'),
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'まで'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'きますか'),
    ],
    romaji: 'doushite eki made arukimasu ka',
    meaning: '為什麼要走到車站呢',
  ),

  // 文型:Placeに Nがあります・います ─────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'に'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'が'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'machi ni mise ga arimasu',
    meaning: '城鎮裡有商店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'くに'),
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'が'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'chikaku ni eki ga arimasu',
    meaning: '附近有車站',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'に'),
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: '達', furigana: 'だち'),
      RubySegment(text: 'が'),
      RubySegment(text: 'います'),
    ],
    romaji: 'mise ni tomodachi ga imasu',
    meaning: '店裡有朋友',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'に'),
      RubySegment(text: '父', furigana: 'ちち', readingId: 'reading:父#ちち'),
      RubySegment(text: 'が'),
      RubySegment(text: 'います'),
    ],
    romaji: 'kaisha ni chichi ga imasu',
    meaning: '我爸爸在公司',
  ),

  // 文型:Nは Placeにあります・います ─────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'は'),
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'に'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'eki wa machi ni arimasu',
    meaning: '車站在城鎮裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'は'),
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'に'),
      RubySegment(text: 'います'),
    ],
    romaji: 'sensei wa eki ni imasu',
    meaning: '老師在車站',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: '達', furigana: 'だち'),
      RubySegment(text: 'は'),
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'に'),
      RubySegment(text: 'います'),
    ],
    romaji: 'tomodachi wa machi ni imasu',
    meaning: '朋友在城鎮裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'は'),
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'に'),
      RubySegment(text: 'あります'),
    ],
    romaji: 'hon wa ie ni arimasu',
    meaning: '書在家裡',
  ),

  // 文型:の(位置:上・下・中・近く) ──────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'かばんの'),
      RubySegment(text: '上', furigana: 'うえ', readingId: 'reading:上#うえ'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'があります'),
    ],
    romaji: 'kaban no ue ni hon ga arimasu',
    meaning: '包包上面有書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'かばんの'),
      RubySegment(text: '下', furigana: 'した', readingId: 'reading:下#した'),
      RubySegment(text: 'に'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'があります'),
    ],
    romaji: 'kaban no shita ni hana ga arimasu',
    meaning: '包包下面有花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'かばんの'),
      RubySegment(text: '中', furigana: 'なか', readingId: 'reading:中#なか'),
      RubySegment(text: 'に'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'があります'),
    ],
    romaji: 'kaban no naka ni hon ga arimasu',
    meaning: '包包裡面有書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'の'),
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'くに'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'があります'),
    ],
    romaji: 'eki no chikaku ni mise ga arimasu',
    meaning: '車站附近有商店',
  ),

  // 文型:数量詞(〜つ・〜人・〜枚・〜回) ────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'を'),
      RubySegment(text: 'みっつ'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'います'),
    ],
    romaji: 'hana o mittsu kaimasu',
    meaning: '買三朵花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'が'),
      RubySegment(text: 'ふたり'),
      RubySegment(text: 'います'),
    ],
    romaji: 'sensei ga futari imasu',
    meaning: '有兩位老師',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'カードを'),
      RubySegment(text: '三', furigana: 'さん'),
      RubySegment(text: 'まい'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'います'),
    ],
    romaji: 'kaado o sanmai kaimasu',
    meaning: '買三張卡片',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '三', furigana: 'さん'),
      RubySegment(text: '回', furigana: 'かい'),
      RubySegment(text: '泳', furigana: 'およ'),
      RubySegment(text: 'ぎます'),
    ],
    romaji: 'sankai oyogimasu',
    meaning: '游三次',
  ),

  // 文型:〜だけ ──────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '水', furigana: 'みず', readingId: 'reading:水#みず'),
      RubySegment(text: 'だけ'),
      RubySegment(text: '飲', furigana: 'の', readingId: 'reading:飲#の'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'mizu dake nomimasu',
    meaning: '只喝水',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '少', furigana: 'すこ'),
      RubySegment(text: 'しだけ'),
      RubySegment(text: '食', furigana: 'た', readingId: 'reading:食#た'),
      RubySegment(text: 'べます'),
    ],
    romaji: 'sukoshi dake tabemasu',
    meaning: '只吃一點點',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'くだけ'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'chikaku dake arukimasu',
    meaning: '只在附近走走',
  ),

  // 文型:時間の長さ(〜時間・〜年) ──────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '二', furigana: 'に'),
      RubySegment(text: '時', furigana: 'じ', readingId: 'reading:時#ジ'),
      RubySegment(text: '間', furigana: 'かん', readingId: 'reading:間#カン'),
      RubySegment(text: '読', furigana: 'よ', readingId: 'reading:読#よ'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'nijikan yomimasu',
    meaning: '讀兩個小時',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '三', furigana: 'さん'),
      RubySegment(text: '年', furigana: 'ねん', readingId: 'reading:年#ネン'),
      RubySegment(text: '住', furigana: 'す', readingId: 'reading:住#す'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'sannen sumimasu',
    meaning: '住三年',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '一', furigana: 'いち'),
      RubySegment(text: '年', furigana: 'ねん', readingId: 'reading:年#ネン'),
      RubySegment(text: '待', furigana: 'ま', readingId: 'reading:待#ま'),
      RubySegment(text: 'ちます'),
    ],
    romaji: 'ichinen machimasu',
    meaning: '等一年',
  ),

  // 文型:過去(Nでした・い形かったです・な形でした) ──────
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん', readingId: 'reading:先#セン'),
      RubySegment(text: '生', furigana: 'せい', readingId: 'reading:生#セイ'),
      RubySegment(text: 'でした'),
    ],
    romaji: 'sensei deshita',
    meaning: '以前是老師',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '忙', furigana: 'いそが'),
      RubySegment(text: 'しかったです'),
    ],
    romaji: 'isogashikatta desu',
    meaning: '以前很忙',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '静', furigana: 'しず'),
      RubySegment(text: 'かでした'),
    ],
    romaji: 'shizuka deshita',
    meaning: '以前很安靜',
  ),

  // 文型:比較(AよりBのほうが) ────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
      RubySegment(text: 'より'),
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'のほうが'),
      RubySegment(text: '好', furigana: 'す'),
      RubySegment(text: 'きです'),
    ],
    romaji: 'yama yori umi no hou ga suki desu',
    meaning: '比起山更喜歡海',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'より'),
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'のほうが'),
      RubySegment(text: '好', furigana: 'す'),
      RubySegment(text: 'きです'),
    ],
    romaji: 'hon yori hana no hou ga suki desu',
    meaning: '比起書更喜歡花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'より'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'のほうが'),
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'いです'),
    ],
    romaji: 'eki yori mise no hou ga chikai desu',
    meaning: '比起車站商店比較近',
  ),

  // 文型:いちばん ────────────────────────────────────────
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いちばん'),
      RubySegment(text: '安', furigana: 'やす', readingId: 'reading:安#やす'),
      RubySegment(text: 'い'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'ichiban yasui mise',
    meaning: '最便宜的店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いちばん'),
      RubySegment(text: '新', furigana: 'あたら', readingId: 'reading:新#あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
    ],
    romaji: 'ichiban atarashii hon',
    meaning: '最新的書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いちばん'),
      RubySegment(text: '高', furigana: 'たか', readingId: 'reading:高#たか'),
      RubySegment(text: 'い'),
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
    ],
    romaji: 'ichiban takai yama',
    meaning: '最高的山',
  ),
];
