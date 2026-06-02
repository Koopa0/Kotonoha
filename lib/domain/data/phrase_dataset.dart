// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';

/// Short readable phrases — the sentence layer. All hiragana, no yōon, no
/// sokuon, layout spaces at word boundaries. Original motif sentences (NOT
/// copyrighted lyrics/lines): a few flavoured to the learner's interests, most a
/// calm, seasonal 物の哀れ / をかし register — sky, rain, a cat, a small feeling —
/// to carry the app's mood. Grammar follows the early 《大家的日本語》 lessons
/// (は/が/を/の/に particles); romaji is a free reading, so the を particle reads
/// `o` and は reads `wa` (NOT the kana-table `wo`/`ha`).
///
/// Pure data: no `package:flutter/*` imports.
const List<Phrase> kPhrases = <Phrase>[
  Phrase(
    kana: 'そらが あおい',
    romaji: 'sora ga aoi',
    meaning: '天空是藍的',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'なつの かぜ',
    romaji: 'natsu no kaze',
    meaning: '夏天的風',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'うみが みえる',
    romaji: 'umi ga mieru',
    meaning: '看得見海',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'きみの こえ',
    romaji: 'kimi no koe',
    meaning: '你的聲音',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'きみが すき',
    romaji: 'kimi ga suki',
    meaning: '喜歡你',
    theme: ContentTheme.anime,
  ),
  Phrase(
    kana: 'みずを ください',
    romaji: 'mizu o kudasai',
    meaning: '請給我水',
    theme: ContentTheme.travel,
  ),
  Phrase(
    kana: 'えきは どこ',
    romaji: 'eki wa doko',
    meaning: '車站在哪裡',
    theme: ContentTheme.travel,
  ),
  Phrase(
    kana: 'たたかうか もどるか',
    romaji: 'tatakau ka modoru ka',
    meaning: '戰鬥還是返回',
    theme: ContentTheme.game,
  ),
  // 季節 — the seasonal / 物の哀れ register: sky, rain, snow, wind, flowers,
  // moon, stars. The quiet beauty of passing things.
  Phrase(
    kana: 'あさの ひかり',
    romaji: 'asa no hikari',
    meaning: '清晨的光',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'あめが ふる',
    romaji: 'ame ga furu',
    meaning: '下起雨了',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'あめが やむ',
    romaji: 'ame ga yamu',
    meaning: '雨停了',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'ゆきが ふる',
    romaji: 'yuki ga furu',
    meaning: '雪落下',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'かぜが すずしい',
    romaji: 'kaze ga suzushii',
    meaning: '風涼涼的',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'かぜが おどる',
    romaji: 'kaze ga odoru',
    meaning: '風在跳舞',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'はなが さいた',
    romaji: 'hana ga saita',
    meaning: '花開了',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'はなが ちる',
    romaji: 'hana ga chiru',
    meaning: '花謝了',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'くもが ながれる',
    romaji: 'kumo ga nagareru',
    meaning: '雲緩緩流動',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'そらを みる',
    romaji: 'sora o miru',
    meaning: '抬頭望天',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'つきが でる',
    romaji: 'tsuki ga deru',
    meaning: '月亮升起',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'つきが まるい',
    romaji: 'tsuki ga marui',
    meaning: '月亮圓圓的',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'ほしが ひかる',
    romaji: 'hoshi ga hikaru',
    meaning: '星星閃著光',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'ほしが ながれる',
    romaji: 'hoshi ga nagareru',
    meaning: '流星劃過',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'みずに うつる そら',
    romaji: 'mizu ni utsuru sora',
    meaning: '映在水面的天空',
    theme: ContentTheme.season,
  ),
  Phrase(
    kana: 'ふゆの しずけさ',
    romaji: 'fuyu no shizukesa',
    meaning: '冬日的靜謐',
    theme: ContentTheme.season,
  ),
  // 日々 — small everyday moments and gentle feelings: home, a voice, a cat,
  // a little tiredness, a song. Warm and plain.
  Phrase(
    kana: 'ただいま',
    romaji: 'tadaima',
    meaning: '我回來了',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'おかえり',
    romaji: 'okaeri',
    meaning: '你回來啦',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'あなたに あいたい',
    romaji: 'anata ni aitai',
    meaning: '好想見你',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'こえを ききたい',
    romaji: 'koe o kikitai',
    meaning: '好想聽你的聲音',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'すこし つかれた',
    romaji: 'sukoshi tsukareta',
    meaning: '有點累了',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'ねこが ねむる',
    romaji: 'neko ga nemuru',
    meaning: '貓兒睡著了',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'こねこが ねむい',
    romaji: 'koneko ga nemui',
    meaning: '小貓睏了',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'ねこが わらう',
    romaji: 'neko ga warau',
    meaning: '貓兒在笑',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'おかしが すき',
    romaji: 'okashi ga suki',
    meaning: '喜歡甜點',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'うたが きこえる',
    romaji: 'uta ga kikoeru',
    meaning: '聽見了歌聲',
    theme: ContentTheme.daily,
  ),
  Phrase(
    kana: 'あかい りんご',
    romaji: 'akai ringo',
    meaning: '紅紅的蘋果',
    theme: ContentTheme.daily,
  ),
];
