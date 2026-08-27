// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// Grammar-pattern sentences for 《大家的日本語》 I, lessons 13–19.
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
/// て形・ない形・辞書形・た形 (the four bare conjugation SHAPES named in the
/// L14/L17/L18/L19 grammar points) get no sentences of their own — a bare
/// conjugated form is not a complete utterance. Each shape is carried by
/// every sentence built on it below (て形 by てください/ています/ましょうか/
/// てもいい/てはいけない/てから/V1てV2; ない形 by ないでください/なければ/
/// なくてもいい; 辞書形 by ことができる/のが好き/まえに; た形 by たことがある/
/// たり〜たり), so each shape is met far more than three times in practice.
///
/// Pure data: no `package:flutter/*` imports.
const List<KanjiPhrase> kMinnaL13to19 = <KanjiPhrase>[
  // ── L13 ──────────────────────────────────────────────────────────────
  // 文型:Nがほしいです
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'が'),
      RubySegment(text: 'ほしいです'),
    ],
    romaji: 'atarashii hon ga hoshii desu',
    meaning: '想要一本新書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'もっと'),
      RubySegment(text: '時', furigana: 'じ'),
      RubySegment(text: '間', furigana: 'かん'),
      RubySegment(text: 'が'),
      RubySegment(text: 'ほしいです'),
    ],
    romaji: 'motto jikan ga hoshii desu',
    meaning: '想要多一點時間',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちが'),
      RubySegment(text: 'ほしいです'),
    ],
    romaji: 'tomodachi ga hoshii desu',
    meaning: '想要朋友',
  ),
  // 文型:Vたいです
  KanjiPhrase(
    segments: [
      RubySegment(text: '水', furigana: 'みず'),
      RubySegment(text: 'が'),
      RubySegment(text: '飲', furigana: 'の'),
      RubySegment(text: 'みたいです'),
    ],
    romaji: 'mizu ga nomitai desu',
    meaning: '想喝水',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'パンが'),
      RubySegment(text: '食', furigana: 'た'),
      RubySegment(text: 'べたいです'),
    ],
    romaji: 'pan ga tabetai desu',
    meaning: '想吃麵包',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'に'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'いたいです'),
    ],
    romaji: 'sensei ni aitai desu',
    meaning: '想見老師',
  ),
  // 文型:Placeへ Vに行きます(目的)
  KanjiPhrase(
    segments: [
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'いに'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'mise e hon o kai ni ikimasu',
    meaning: '去店裡買書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま'),
      RubySegment(text: 'へ'),
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み'),
      RubySegment(text: 'に'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'yama e hana o mi ni ikimasu',
    meaning: '去山上賞花',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'へ'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'いに'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'eki e tomodachi ni ai ni ikimasu',
    meaning: '去車站跟朋友見面',
  ),

  // ── L14 ──────────────────────────────────────────────────────────────
  // 文型:〜てください
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ちょっと'),
      RubySegment(text: '待', furigana: 'ま'),
      RubySegment(text: 'ってください'),
    ],
    romaji: 'chotto matte kudasai',
    meaning: '請稍等一下',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ここに'),
      RubySegment(text: '名', furigana: 'な'),
      RubySegment(text: 'まえを'),
      RubySegment(text: '書', furigana: 'か'),
      RubySegment(text: 'いてください'),
    ],
    romaji: 'koko ni namae o kaite kudasai',
    meaning: '請在這裡寫上名字',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ゆっくり'),
      RubySegment(text: '話', furigana: 'はな'),
      RubySegment(text: 'してください'),
    ],
    romaji: 'yukkuri hanashite kudasai',
    meaning: '請說慢一點',
  ),
  // 文型:〜ています(進行中)
  KanjiPhrase(
    segments: [
      RubySegment(text: '今', furigana: 'いま'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'んでいます'),
    ],
    romaji: 'ima hon o yonde imasu',
    meaning: '現在正在看書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちと'),
      RubySegment(text: '話', furigana: 'はな'),
      RubySegment(text: 'しています'),
    ],
    romaji: 'tomodachi to hanashite imasu',
    meaning: '正在跟朋友聊天',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '男', furigana: 'おとこ'),
      RubySegment(text: 'の'),
      RubySegment(text: '人', furigana: 'ひと'),
      RubySegment(text: 'が'),
      RubySegment(text: '道', furigana: 'みち'),
      RubySegment(text: 'を'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'いています'),
    ],
    romaji: 'otoko no hito ga michi o aruite imasu',
    meaning: '一位男士正走在路上',
  ),
  // 文型:〜ましょうか
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '持', furigana: 'も'),
      RubySegment(text: 'ちましょうか'),
    ],
    romaji: 'hon o mochimashou ka',
    meaning: '我來幫你拿書吧',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'すこし'),
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'みましょうか'),
    ],
    romaji: 'sukoshi yasumimashou ka',
    meaning: '要不要稍微休息一下',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'いっしょに'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'きましょうか'),
    ],
    romaji: 'issho ni arukimashou ka',
    meaning: '要不要一起走走',
  ),

  // ── L15 ──────────────────────────────────────────────────────────────
  // 文型:〜てもいいですか
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'んでもいいですか'),
    ],
    romaji: 'kono hon o yonde mo ii desu ka',
    meaning: '可以讀這本書嗎',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ここで'),
      RubySegment(text: 'すこし'),
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'んでもいいですか'),
    ],
    romaji: 'koko de sukoshi yasunde mo ii desu ka',
    meaning: '可以在這裡稍微休息一下嗎',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'その'),
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み'),
      RubySegment(text: 'てもいいですか'),
    ],
    romaji: 'sono hana o mite mo ii desu ka',
    meaning: '可以看那朵花嗎',
  ),
  // 文型:〜てはいけません
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ここで'),
      RubySegment(text: '大', furigana: 'おお'),
      RubySegment(text: 'きい'),
      RubySegment(text: '声', furigana: 'こえ'),
      RubySegment(text: 'で'),
      RubySegment(text: '話', furigana: 'はな'),
      RubySegment(text: 'してはいけません'),
    ],
    romaji: 'koko de ookii koe de hanashite wa ikemasen',
    meaning: '這裡不可以大聲說話',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ここに'),
      RubySegment(text: '入', furigana: 'はい'),
      RubySegment(text: 'ってはいけません'),
    ],
    romaji: 'koko ni haitte wa ikemasen',
    meaning: '不可以進入這裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ここで'),
      RubySegment(text: '食', furigana: 'た'),
      RubySegment(text: 'べてはいけません'),
    ],
    romaji: 'koko de tabete wa ikemasen',
    meaning: '這裡不可以吃東西',
  ),
  // 文型:〜ています(狀態・職業・居住)
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'をしています'),
    ],
    romaji: 'sensei o shite imasu',
    meaning: '在當老師',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'の'),
      RubySegment(text: '近', furigana: 'ちか'),
      RubySegment(text: 'くに'),
      RubySegment(text: '住', furigana: 'す'),
      RubySegment(text: 'んでいます'),
    ],
    romaji: 'eki no chikaku ni sunde imasu',
    meaning: '住在車站附近',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちの'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '持', furigana: 'も'),
      RubySegment(text: 'っています'),
    ],
    romaji: 'tomodachi no hon o motte imasu',
    meaning: '拿著朋友的書',
  ),

  // ── L16 ──────────────────────────────────────────────────────────────
  // 文型:V1て、V2(順序)
  KanjiPhrase(
    segments: [
      RubySegment(text: '朝', furigana: 'あさ'),
      RubySegment(text: '起', furigana: 'お'),
      RubySegment(text: 'きて'),
      RubySegment(text: '会', furigana: 'かい'),
      RubySegment(text: '社', furigana: 'しゃ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'asa okite kaisha e ikimasu',
    meaning: '早上起床後去公司',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'んで'),
      RubySegment(text: '寝', furigana: 'ね'),
      RubySegment(text: 'ます'),
    ],
    romaji: 'hon o yonde nemasu',
    meaning: '先看書再睡覺',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '駅', furigana: 'えき'),
      RubySegment(text: 'で'),
      RubySegment(text: '友', furigana: 'とも'),
      RubySegment(text: 'だちに'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'って'),
      RubySegment(text: '話', furigana: 'はな'),
      RubySegment(text: 'します'),
    ],
    romaji: 'eki de tomodachi ni atte hanashimasu',
    meaning: '在車站遇見朋友後聊天',
  ),
  // 文型:〜てから
  KanjiPhrase(
    segments: [
      RubySegment(text: 'すこし'),
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'んでから'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'sukoshi yasunde kara arukimasu',
    meaning: '稍微休息後再走',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み'),
      RubySegment(text: 'てから'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'に'),
      RubySegment(text: '入', furigana: 'はい'),
      RubySegment(text: 'ります'),
    ],
    romaji: 'hana o mite kara mise ni hairimasu',
    meaning: '看完花後進店裡',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'の'),
      RubySegment(text: '名', furigana: 'な'),
      RubySegment(text: 'まえを'),
      RubySegment(text: '聞', furigana: 'き'),
      RubySegment(text: 'いてから'),
      RubySegment(text: '書', furigana: 'か'),
      RubySegment(text: 'きます'),
    ],
    romaji: 'sensei no namae o kiite kara kakimasu',
    meaning: '問了老師的名字之後才寫',
  ),
  // 文型:Nは Nが 形容詞
  KanjiPhrase(
    segments: [
      RubySegment(text: 'この'),
      RubySegment(text: '町', furigana: 'まち'),
      RubySegment(text: 'は'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'が'),
      RubySegment(text: '多', furigana: 'おお'),
      RubySegment(text: 'いです'),
    ],
    romaji: 'kono machi wa mise ga ooi desu',
    meaning: '這個鎮上有很多店家',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あの'),
      RubySegment(text: '人', furigana: 'ひと'),
      RubySegment(text: 'は'),
      RubySegment(text: '声', furigana: 'こえ'),
      RubySegment(text: 'が'),
      RubySegment(text: '大', furigana: 'おお'),
      RubySegment(text: 'きいです'),
    ],
    romaji: 'ano hito wa koe ga ookii desu',
    meaning: '那個人聲音很大',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'あの'),
      RubySegment(text: '子', furigana: 'こ'),
      RubySegment(text: 'は'),
      RubySegment(text: '目', furigana: 'め'),
      RubySegment(text: 'が'),
      RubySegment(text: '小', furigana: 'ちい'),
      RubySegment(text: 'さいです'),
    ],
    romaji: 'ano ko wa me ga chiisai desu',
    meaning: '那孩子眼睛很小',
  ),

  // ── L17 ──────────────────────────────────────────────────────────────
  // 文型:〜ないでください
  KanjiPhrase(
    segments: [
      RubySegment(text: 'ここで'),
      RubySegment(text: '話', furigana: 'はな'),
      RubySegment(text: 'さないでください'),
    ],
    romaji: 'koko de hanasanai de kudasai',
    meaning: '這裡請不要說話',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'まだ'),
      RubySegment(text: '食', furigana: 'た'),
      RubySegment(text: 'べないでください'),
    ],
    romaji: 'mada tabenai de kudasai',
    meaning: '請先不要吃',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'その'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'まないでください'),
    ],
    romaji: 'sono hon o yomanai de kudasai',
    meaning: '請不要讀那本書',
  ),
  // 文型:〜なければなりません
  KanjiPhrase(
    segments: [
      RubySegment(text: '毎', furigana: 'まい'),
      RubySegment(text: '日', furigana: 'にち'),
      RubySegment(text: '会', furigana: 'かい'),
      RubySegment(text: '社', furigana: 'しゃ'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'かなければなりません'),
    ],
    romaji: 'mainichi kaisha e ikanakereba narimasen',
    meaning: '每天必須去公司',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '早', furigana: 'はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '起', furigana: 'お'),
      RubySegment(text: 'きなければなりません'),
    ],
    romaji: 'hayaku okinakereba narimasen',
    meaning: '必須早起',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'すこし'),
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'まなければなりません'),
    ],
    romaji: 'sukoshi yasumanakereba narimasen',
    meaning: '必須稍微休息一下',
  ),
  // 文型:〜なくてもいいです
  KanjiPhrase(
    segments: [
      RubySegment(text: 'もう'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'かなくてもいいです'),
    ],
    romaji: 'mou arukanakute mo ii desu',
    meaning: '不用再走也沒關係',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '早', furigana: 'はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '起', furigana: 'お'),
      RubySegment(text: 'きなくてもいいです'),
    ],
    romaji: 'hayaku okinakute mo ii desu',
    meaning: '不用早起也沒關係',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'その'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'まなくてもいいです'),
    ],
    romaji: 'sono hon o yomanakute mo ii desu',
    meaning: '不用讀那本書也沒關係',
  ),

  // ── L18 ──────────────────────────────────────────────────────────────
  // 文型:〜ことができます
  KanjiPhrase(
    segments: [
      RubySegment(text: '速', furigana: 'はや'),
      RubySegment(text: 'く'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'くことができます'),
    ],
    romaji: 'hayaku aruku koto ga dekimasu',
    meaning: '可以走得很快',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '新', furigana: 'あたら'),
      RubySegment(text: 'しい'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'を'),
      RubySegment(text: '作', furigana: 'つく'),
      RubySegment(text: 'ることができます'),
    ],
    romaji: 'atarashii mise o tsukuru koto ga dekimasu',
    meaning: '能開一家新店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '日', furigana: 'に'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: '語', furigana: 'ご'),
      RubySegment(text: 'を'),
      RubySegment(text: '話', furigana: 'はな'),
      RubySegment(text: 'すことができます'),
    ],
    romaji: 'nihongo o hanasu koto ga dekimasu',
    meaning: '會說日語',
  ),
  // 文型:Vるのが好きです
  KanjiPhrase(
    segments: [
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'むのがすきです'),
    ],
    romaji: 'hon o yomu no ga suki desu',
    meaning: '喜歡讀書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '山', furigana: 'やま'),
      RubySegment(text: 'を'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'くのがすきです'),
    ],
    romaji: 'yama o aruku no ga suki desu',
    meaning: '喜歡在山裡健行',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '花', furigana: 'はな'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み'),
      RubySegment(text: 'るのがすきです'),
    ],
    romaji: 'hana o miru no ga suki desu',
    meaning: '喜歡看花',
  ),
  // 文型:Nのまえに・Vるまえに
  KanjiPhrase(
    segments: [
      RubySegment(text: '寝', furigana: 'ね'),
      RubySegment(text: 'るまえに'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'みます'),
    ],
    romaji: 'neru mae ni hon o yomimasu',
    meaning: '睡前讀書',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'に'),
      RubySegment(text: '入', furigana: 'はい'),
      RubySegment(text: 'るまえに'),
      RubySegment(text: 'すこし'),
      RubySegment(text: '待', furigana: 'ま'),
      RubySegment(text: 'ちます'),
    ],
    romaji: 'mise ni hairu mae ni sukoshi machimasu',
    meaning: '進店之前先稍等一下',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'みのまえに'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'いものをします'),
    ],
    romaji: 'yasumi no mae ni kaimono o shimasu',
    meaning: '放假前先買東西',
  ),

  // ── L19 ──────────────────────────────────────────────────────────────
  // 文型:〜たことがあります
  KanjiPhrase(
    segments: [
      RubySegment(text: '海', furigana: 'うみ'),
      RubySegment(text: 'を'),
      RubySegment(text: '見', furigana: 'み'),
      RubySegment(text: 'たことがあります'),
    ],
    romaji: 'umi o mita koto ga arimasu',
    meaning: '曾經看過海',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: 'その'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'に'),
      RubySegment(text: '入', furigana: 'はい'),
      RubySegment(text: 'ったことがあります'),
    ],
    romaji: 'sono mise ni haitta koto ga arimasu',
    meaning: '曾經進過那家店',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'に'),
      RubySegment(text: '会', furigana: 'あ'),
      RubySegment(text: 'ったことがあります'),
    ],
    romaji: 'sensei ni atta koto ga arimasu',
    meaning: '曾經見過老師',
  ),
  // 文型:〜たり〜たりします
  KanjiPhrase(
    segments: [
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'みの'),
      RubySegment(text: '日', furigana: 'ひ'),
      RubySegment(text: 'は'),
      RubySegment(text: '本', furigana: 'ほん'),
      RubySegment(text: 'を'),
      RubySegment(text: '読', furigana: 'よ'),
      RubySegment(text: 'んだり'),
      RubySegment(text: '歩', furigana: 'ある'),
      RubySegment(text: 'いたりします'),
    ],
    romaji: 'yasumi no hi wa hon o yondari aruitari shimasu',
    meaning: '放假時會看看書、散散步之類的',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'みの'),
      RubySegment(text: '日', furigana: 'ひ'),
      RubySegment(text: 'は'),
      RubySegment(text: '店', furigana: 'みせ'),
      RubySegment(text: 'で'),
      RubySegment(text: '買', furigana: 'か'),
      RubySegment(text: 'いものをしたり'),
      RubySegment(text: '家', furigana: 'いえ'),
      RubySegment(text: 'で'),
      RubySegment(text: '休', furigana: 'やす'),
      RubySegment(text: 'んだりします'),
    ],
    romaji: 'yasumi no hi wa mise de kaimono o shitari ie de yasundari shimasu',
    meaning: '放假時會去店裡買東西、在家休息之類的',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '家', furigana: 'いえ'),
      RubySegment(text: 'で'),
      RubySegment(text: '食', furigana: 'た'),
      RubySegment(text: 'べたり'),
      RubySegment(text: '飲', furigana: 'の'),
      RubySegment(text: 'んだりします'),
    ],
    romaji: 'ie de tabetari nondari shimasu',
    meaning: '在家會吃點東西、喝點東西之類的',
  ),
  // 文型:〜くなります・〜になります
  KanjiPhrase(
    segments: [
      RubySegment(text: '声', furigana: 'こえ'),
      RubySegment(text: 'が'),
      RubySegment(text: '大', furigana: 'おお'),
      RubySegment(text: 'きくなります'),
    ],
    romaji: 'koe ga ookiku narimasu',
    meaning: '聲音會變大',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '空', furigana: 'そら'),
      RubySegment(text: 'が'),
      RubySegment(text: '明', furigana: 'あか'),
      RubySegment(text: 'るくなります'),
    ],
    romaji: 'sora ga akaruku narimasu',
    meaning: '天色會變亮',
  ),
  KanjiPhrase(
    segments: [
      RubySegment(text: '先', furigana: 'せん'),
      RubySegment(text: '生', furigana: 'せい'),
      RubySegment(text: 'になります'),
    ],
    romaji: 'sensei ni narimasu',
    meaning: '成為老師',
  ),
];
