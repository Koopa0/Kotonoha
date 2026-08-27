// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/data/phrases/minna_l01_06.dart';
import 'package:kotonoha/kanji/domain/data/phrases/minna_l07_12.dart';
import 'package:kotonoha/kanji/domain/data/phrases/minna_l13_19.dart';
import 'package:kotonoha/kanji/domain/data/phrases/minna_l20_25.dart';
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
  // ── Second expansion: daily-life register for the 週/毎/昼/駅/道/店/社/町/
  // 買/売/帰/待/持/使/作/住/起/寝/会/歩/早/明/国/外/近/声/語/曜 batch. Every
  // multi-kanji compound below concatenates each kanji's own registered
  // reading with NO rendaku/gemination shift (e.g. 帰国=きこく, not a voiced
  // or geminated variant) — furigana always renders in hiragana even over an
  // on'yomi reading (katakana in kKanji is a dictionary-convention display
  // choice, not the furigana surface form). ──
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'う'),
    ],
    romaji: 'hon o kau',
    meaning: '買書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな', readingId: 'reading:花#はな'),
      RubySegment(text: 'を'),
      RubySegment(text: '売', furigana: 'う', readingId: 'reading:売#う'),
      RubySegment(text: 'る'),
    ],
    romaji: 'hana o uru',
    meaning: '賣花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'に'),
      RubySegment(text: '帰', furigana: 'かえ', readingId: 'reading:帰#かえ'),
      RubySegment(text: 'る'),
    ],
    romaji: 'ie ni kaeru',
    meaning: '回家',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'で'),
      RubySegment(text: '待', furigana: 'ま', readingId: 'reading:待#ま'),
      RubySegment(text: 'つ'),
    ],
    romaji: 'eki de matsu',
    meaning: '在車站等待',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: '持', furigana: 'も', readingId: 'reading:持#も'),
      RubySegment(text: 'つ'),
    ],
    romaji: 'hon o motsu',
    meaning: '拿著書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '手', furigana: 'て', readingId: 'reading:手#て'),
      RubySegment(text: 'を'),
      RubySegment(text: '使', furigana: 'つか', readingId: 'reading:使#つか'),
      RubySegment(text: 'う'),
    ],
    romaji: 'te o tsukau',
    meaning: '用手',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ', readingId: 'reading:家#いえ'),
      RubySegment(text: 'を'),
      RubySegment(text: '作', furigana: 'つく', readingId: 'reading:作#つく'),
      RubySegment(text: 'る'),
    ],
    romaji: 'ie o tsukuru',
    meaning: '蓋房子',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'に'),
      RubySegment(text: '住', furigana: 'す', readingId: 'reading:住#す'),
      RubySegment(text: 'む'),
    ],
    romaji: 'machi ni sumu',
    meaning: '住在城鎮裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '朝', furigana: 'あさ', readingId: 'reading:朝#あさ'),
      RubySegment(text: '早', furigana: 'はや', readingId: 'reading:早#はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '起', furigana: 'お', readingId: 'reading:起#お'),
      RubySegment(text: 'きる'),
    ],
    romaji: 'asa hayaku okiru',
    meaning: '一早起床',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '早', furigana: 'はや', readingId: 'reading:早#はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '寝', furigana: 'ね', readingId: 'reading:寝#ね'),
      RubySegment(text: 'る'),
    ],
    romaji: 'hayaku neru',
    meaning: '早點睡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: 'に'),
      RubySegment(text: '会', furigana: 'あ', readingId: 'reading:会#あ'),
      RubySegment(text: 'う'),
    ],
    romaji: 'tomo ni au',
    meaning: '與朋友見面',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'を'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'く'),
    ],
    romaji: 'machi o aruku',
    meaning: '在鎮上走走',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: 'と'),
      RubySegment(text: '語', furigana: 'かた', readingId: 'reading:語#かた'),
      RubySegment(text: 'る'),
    ],
    romaji: 'tomo to kataru',
    meaning: '與朋友暢談',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'あたら', readingId: 'reading:新#あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '言', furigana: 'げん', readingId: 'reading:言#ゲン'),
      RubySegment(text: '語', furigana: 'ご', readingId: 'reading:語#ゴ'),
    ],
    romaji: 'atarashii gengo',
    meaning: '新的語言',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'あたら', readingId: 'reading:新#あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'atarashii mise',
    meaning: '新的店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'まで'),
      RubySegment(text: 'の'),
      RubySegment(text: '道', furigana: 'みち', readingId: 'reading:道#みち'),
    ],
    romaji: 'eki made no michi',
    meaning: '到車站的路',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '明', furigana: 'あか', readingId: 'reading:明#あか'),
      RubySegment(text: 'るい'),
      RubySegment(text: '声', furigana: 'こえ', readingId: 'reading:声#こえ'),
    ],
    romaji: 'akarui koe',
    meaning: '開朗的嗓音',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '外', furigana: 'そと', readingId: 'reading:外#そと'),
      RubySegment(text: 'に'),
      RubySegment(text: '出', furigana: 'で', readingId: 'reading:出#で'),
      RubySegment(text: 'る'),
    ],
    romaji: 'soto ni deru',
    meaning: '到外面去',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '国', furigana: 'くに', readingId: 'reading:国#くに'),
      RubySegment(text: 'に'),
      RubySegment(text: '帰', furigana: 'かえ', readingId: 'reading:帰#かえ'),
      RubySegment(text: 'る'),
    ],
    romaji: 'kuni ni kaeru',
    meaning: '回國',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '会', furigana: 'かい', readingId: 'reading:会#カイ'),
      RubySegment(text: '社', furigana: 'しゃ', readingId: 'reading:社#シャ'),
      RubySegment(text: 'に'),
      RubySegment(text: '行', furigana: 'い', readingId: 'reading:行#い'),
      RubySegment(text: 'く'),
    ],
    romaji: 'kaisha ni iku',
    meaning: '去公司',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '帰', furigana: 'き', readingId: 'reading:帰#キ'),
      RubySegment(text: '国', furigana: 'こく', readingId: 'reading:国#コク'),
      RubySegment(text: 'の'),
      RubySegment(text: '日', furigana: 'ひ', readingId: 'reading:日#ひ'),
    ],
    romaji: 'kikoku no hi',
    meaning: '歸國的日子',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '早', furigana: 'そう', readingId: 'reading:早#ソウ'),
      RubySegment(text: '朝', furigana: 'ちょう', readingId: 'reading:朝#チョウ'),
      RubySegment(text: 'の'),
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
    ],
    romaji: 'souchou no umi',
    meaning: '清晨的海',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '歩', furigana: 'ほ', readingId: 'reading:歩#ホ'),
      RubySegment(text: '道', furigana: 'どう', readingId: 'reading:道#ドウ'),
      RubySegment(text: 'を'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'く'),
    ],
    romaji: 'hodou o aruku',
    meaning: '走在人行道上',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '書', furigana: 'しょ', readingId: 'reading:書#ショ'),
      RubySegment(text: '店', furigana: 'てん', readingId: 'reading:店#テン'),
      RubySegment(text: 'で'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'う'),
    ],
    romaji: 'shoten de kau',
    meaning: '在書店買',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '売', furigana: 'ばい', readingId: 'reading:売#バイ'),
      RubySegment(text: '店', furigana: 'てん', readingId: 'reading:店#テン'),
      RubySegment(text: 'で'),
      RubySegment(text: '買', furigana: 'か', readingId: 'reading:買#か'),
      RubySegment(text: 'う'),
    ],
    romaji: 'baiten de kau',
    meaning: '在販賣部買',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'で'),
      RubySegment(text: '本', furigana: 'ほん', readingId: 'reading:本#ホン'),
      RubySegment(text: 'を'),
      RubySegment(text: '売', furigana: 'ばい', readingId: 'reading:売#バイ'),
      RubySegment(text: '買', furigana: 'ばい', readingId: 'reading:買#バイ'),
      RubySegment(text: 'する'),
    ],
    romaji: 'mise de hon o baibai suru',
    meaning: '在店裡買賣書籍',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '天', furigana: 'てん', readingId: 'reading:天#テン'),
      RubySegment(text: '使', furigana: 'し', readingId: 'reading:使#シ'),
      RubySegment(text: 'の'),
      RubySegment(text: '声', furigana: 'こえ', readingId: 'reading:声#こえ'),
    ],
    romaji: 'tenshi no koe',
    meaning: '天使的聲音',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '手', furigana: 'しゅ', readingId: 'reading:手#シュ'),
      RubySegment(text: '話', furigana: 'わ', readingId: 'reading:話#ワ'),
      RubySegment(text: 'で'),
      RubySegment(text: '話', furigana: 'はな', readingId: 'reading:話#はな'),
      RubySegment(text: 'す'),
    ],
    romaji: 'shuwa de hanasu',
    meaning: '用手語說話',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '毎', furigana: 'まい', readingId: 'reading:毎#マイ'),
      RubySegment(text: '日', furigana: 'にち', readingId: 'reading:日#ニチ'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'く'),
    ],
    romaji: 'mainichi aruku',
    meaning: '每天走路',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '昼', furigana: 'ひる', readingId: 'reading:昼#ひる'),
      RubySegment(text: 'に'),
      RubySegment(text: '会', furigana: 'あ', readingId: 'reading:会#あ'),
      RubySegment(text: 'う'),
    ],
    romaji: 'hiru ni au',
    meaning: '中午見面',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '昼', furigana: 'ちゅう', readingId: 'reading:昼#チュウ'),
      RubySegment(text: '食', furigana: 'しょく', readingId: 'reading:食#ショク'),
      RubySegment(text: 'を'),
      RubySegment(text: '作', furigana: 'つく', readingId: 'reading:作#つく'),
      RubySegment(text: 'る'),
    ],
    romaji: 'chuushoku o tsukuru',
    meaning: '做午餐',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '来', furigana: 'らい', readingId: 'reading:来#ライ'),
      RubySegment(text: '週', furigana: 'しゅう', readingId: 'reading:週#シュウ'),
      RubySegment(text: 'まで'),
    ],
    romaji: 'raishuu made',
    meaning: '到下週為止',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '毎', furigana: 'まい', readingId: 'reading:毎#マイ'),
      RubySegment(text: '年', furigana: 'とし', readingId: 'reading:年#とし'),
      RubySegment(text: 'の'),
      RubySegment(text: '秋', furigana: 'あき', readingId: 'reading:秋#あき'),
    ],
    romaji: 'maitoshi no aki',
    meaning: '每年的秋天',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '春', furigana: 'はる', readingId: 'reading:春#はる'),
      RubySegment(text: 'が'),
      RubySegment(text: '早', furigana: 'はや', readingId: 'reading:早#はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '来', furigana: 'く', readingId: 'reading:来#く'),
      RubySegment(text: 'る'),
    ],
    romaji: 'haru ga hayaku kuru',
    meaning: '春天來得早',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '声', furigana: 'こえ', readingId: 'reading:声#こえ'),
      RubySegment(text: 'を'),
      RubySegment(text: '聞', furigana: 'き', readingId: 'reading:聞#き'),
      RubySegment(text: 'く'),
    ],
    romaji: 'koe o kiku',
    meaning: '聽聲音',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '明', furigana: 'あか', readingId: 'reading:明#あか'),
      RubySegment(text: 'るい'),
      RubySegment(text: '朝', furigana: 'あさ', readingId: 'reading:朝#あさ'),
    ],
    romaji: 'akarui asa',
    meaning: '明亮的早晨',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '外', furigana: 'がい', readingId: 'reading:外#ガイ'),
      RubySegment(text: '国', furigana: 'こく', readingId: 'reading:国#コク'),
      RubySegment(text: 'の'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'gaikoku no mise',
    meaning: '外國的店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '外', furigana: 'そと', readingId: 'reading:外#そと'),
      RubySegment(text: 'を'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'く'),
    ],
    romaji: 'soto o aruku',
    meaning: '在外面走路',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'く'),
      RubySegment(text: 'の'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'chikaku no mise',
    meaning: '附近的店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '冬', furigana: 'ふゆ', readingId: 'reading:冬#ふゆ'),
      RubySegment(text: 'の'),
      RubySegment(text: '早', furigana: 'そう', readingId: 'reading:早#ソウ'),
      RubySegment(text: '朝', furigana: 'ちょう', readingId: 'reading:朝#チョウ'),
    ],
    romaji: 'fuyu no souchou',
    meaning: '冬天的清晨',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'の'),
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'く'),
    ],
    romaji: 'umi no chikaku',
    meaning: '海附近',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま', readingId: 'reading:山#やま'),
      RubySegment(text: 'の'),
      RubySegment(text: '道', furigana: 'みち', readingId: 'reading:道#みち'),
    ],
    romaji: 'yama no michi',
    meaning: '山路',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '雨', furigana: 'あめ', readingId: 'reading:雨#あめ'),
      RubySegment(text: 'の'),
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
    ],
    romaji: 'ame no eki',
    meaning: '雨中的車站',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'の'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'eki no mise',
    meaning: '車站的店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '声', furigana: 'こえ', readingId: 'reading:声#こえ'),
      RubySegment(text: 'で'),
      RubySegment(text: '語', furigana: 'かた', readingId: 'reading:語#かた'),
      RubySegment(text: 'る'),
    ],
    romaji: 'koe de kataru',
    meaning: '用聲音訴說',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'は'),
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'い'),
    ],
    romaji: 'umi wa chikai',
    meaning: '海很近',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '秋', furigana: 'あき', readingId: 'reading:秋#あき'),
      RubySegment(text: 'の'),
      RubySegment(text: '声', furigana: 'こえ', readingId: 'reading:声#こえ'),
    ],
    romaji: 'aki no koe',
    meaning: '秋天的聲音（秋意）',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '早', furigana: 'そう', readingId: 'reading:早#ソウ'),
      RubySegment(text: '朝', furigana: 'ちょう', readingId: 'reading:朝#チョウ'),
      RubySegment(text: 'の'),
      RubySegment(text: '雪', furigana: 'ゆき', readingId: 'reading:雪#ゆき'),
    ],
    romaji: 'souchou no yuki',
    meaning: '清晨的雪',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
      RubySegment(text: 'の'),
      RubySegment(text: '名', furigana: 'な', readingId: 'reading:名#な'),
    ],
    romaji: 'mise no na',
    meaning: '店名',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '近', furigana: 'ちか', readingId: 'reading:近#ちか'),
      RubySegment(text: 'くの'),
      RubySegment(text: '海', furigana: 'うみ', readingId: 'reading:海#うみ'),
      RubySegment(text: 'へ'),
    ],
    romaji: 'chikaku no umi e',
    meaning: '前往附近的海邊',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '町', furigana: 'まち', readingId: 'reading:町#まち'),
      RubySegment(text: 'の'),
      RubySegment(text: '店', furigana: 'みせ', readingId: 'reading:店#みせ'),
    ],
    romaji: 'machi no mise',
    meaning: '鎮上的店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも', readingId: 'reading:友#とも'),
      RubySegment(text: 'と'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'く'),
      RubySegment(text: '道', furigana: 'みち', readingId: 'reading:道#みち'),
    ],
    romaji: 'tomo to aruku michi',
    meaning: '與朋友同行的路',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき', readingId: 'reading:駅#エキ'),
      RubySegment(text: 'から'),
      RubySegment(text: '歩', furigana: 'ある', readingId: 'reading:歩#ある'),
      RubySegment(text: 'く'),
    ],
    romaji: 'eki kara aruku',
    meaning: '從車站步行',
  ),
  // The N5 grammar-pattern spine (《大家的日本語》 I), one file per lesson
  // range so the corpus can grow a batch at a time.
  ...kMinnaL01to06,
  ...kMinnaL07to12,
  ...kMinnaL13to19,
  ...kMinnaL20to25,
];
