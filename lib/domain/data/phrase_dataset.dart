// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/season.dart';

/// Short readable phrases — the sentence layer. All hiragana (special moras
/// welcome — the `KanaTokenizer` gate understands them), layout spaces at word
/// boundaries. Original motif sentences (NOT copyrighted lyrics/lines): a few
/// flavoured to the learner's interests, most a calm, seasonal 物の哀れ / をかし
/// register — sky, rain, a cat, a small feeling — to carry the app's mood.
///
/// The list is organised as PATTERN FAMILIES following the early
/// 《大家的日本語》 arc (です/existence/〜たい/て-form/past/negative/こそあど),
/// a few natural variants per pattern so review meets the pattern, not a
/// memorised card face. The section comments name the pattern for the corpus
/// author; the app never shows or reads them — grammar as such is the
/// textbook's job, this corpus only makes its patterns familiar to the eye.
/// Romaji is a free reading, so the を particle reads `o`, は reads `wa` and
/// へ reads `e` (NOT the kana-table `wo`/`ha`/`he`).
///
/// Pure data: no `package:flutter/*` imports.
const List<Phrase> kPhrases = <Phrase>[
  Phrase(kana: 'そらが あおい', romaji: 'sora ga aoi', meaning: '天空是藍的'),
  Phrase(
    kana: 'なつの かぜ',
    romaji: 'natsu no kaze',
    meaning: '夏天的風',
    season: Season.summer,
  ),
  Phrase(kana: 'うみが みえる', romaji: 'umi ga mieru', meaning: '看得見海'),
  Phrase(kana: 'きみの こえ', romaji: 'kimi no koe', meaning: '你的聲音'),
  Phrase(kana: 'きみが すき', romaji: 'kimi ga suki', meaning: '喜歡你'),
  Phrase(kana: 'みずを ください', romaji: 'mizu o kudasai', meaning: '請給我水'),
  Phrase(kana: 'えきは どこ', romaji: 'eki wa doko', meaning: '車站在哪裡'),
  Phrase(kana: 'たたかうか もどるか', romaji: 'tatakau ka modoru ka', meaning: '戰鬥還是返回'),
  // 季節 — the seasonal / 物の哀れ register: sky, rain, snow, wind, flowers,
  // moon, stars. The quiet beauty of passing things.
  Phrase(kana: 'あさの ひかり', romaji: 'asa no hikari', meaning: '清晨的光'),
  Phrase(kana: 'あめが ふる', romaji: 'ame ga furu', meaning: '下起雨了'),
  Phrase(kana: 'あめが やむ', romaji: 'ame ga yamu', meaning: '雨停了'),
  Phrase(
    kana: 'ゆきが ふる',
    romaji: 'yuki ga furu',
    meaning: '雪落下',
    season: Season.winter,
  ),
  Phrase(
    kana: 'かぜが すずしい',
    romaji: 'kaze ga suzushii',
    meaning: '風涼涼的',
    season: Season.autumn,
  ),
  Phrase(
    kana: 'かぜが おどる',
    romaji: 'kaze ga odoru',
    meaning: '風在跳舞',
    season: Season.spring,
  ),
  Phrase(
    kana: 'はなが さいた',
    romaji: 'hana ga saita',
    meaning: '花開了',
    season: Season.spring,
  ),
  Phrase(
    kana: 'はなが ちる',
    romaji: 'hana ga chiru',
    meaning: '花謝了',
    season: Season.spring,
  ),
  Phrase(kana: 'くもが ながれる', romaji: 'kumo ga nagareru', meaning: '雲緩緩流動'),
  Phrase(kana: 'そらを みる', romaji: 'sora o miru', meaning: '抬頭望天'),
  Phrase(
    kana: 'つきが でる',
    romaji: 'tsuki ga deru',
    meaning: '月亮升起',
    season: Season.autumn,
  ),
  Phrase(
    kana: 'つきが まるい',
    romaji: 'tsuki ga marui',
    meaning: '月亮圓圓的',
    season: Season.autumn,
  ),
  Phrase(kana: 'ほしが ひかる', romaji: 'hoshi ga hikaru', meaning: '星星閃著光'),
  Phrase(kana: 'ほしが ながれる', romaji: 'hoshi ga nagareru', meaning: '流星劃過'),
  Phrase(kana: 'みずに うつる そら', romaji: 'mizu ni utsuru sora', meaning: '映在水面的天空'),
  Phrase(
    kana: 'ふゆの しずけさ',
    romaji: 'fuyu no shizukesa',
    meaning: '冬日的靜謐',
    season: Season.winter,
  ),
  // 日々 — small everyday moments and gentle feelings: home, a voice, a cat,
  // a little tiredness, a song. Warm and plain.
  Phrase(kana: 'ただいま', romaji: 'tadaima', meaning: '我回來了'),
  Phrase(kana: 'おかえり', romaji: 'okaeri', meaning: '你回來啦'),
  Phrase(kana: 'あなたに あいたい', romaji: 'anata ni aitai', meaning: '好想見你'),
  Phrase(kana: 'こえを ききたい', romaji: 'koe o kikitai', meaning: '好想聽你的聲音'),
  Phrase(kana: 'すこし つかれた', romaji: 'sukoshi tsukareta', meaning: '有點累了'),
  Phrase(kana: 'ねこが ねむる', romaji: 'neko ga nemuru', meaning: '貓兒睡著了'),
  Phrase(kana: 'こねこが ねむい', romaji: 'koneko ga nemui', meaning: '小貓睏了'),
  Phrase(kana: 'ねこが わらう', romaji: 'neko ga warau', meaning: '貓兒在笑'),
  Phrase(kana: 'おかしが すき', romaji: 'okashi ga suki', meaning: '喜歡甜點'),
  Phrase(kana: 'うたが きこえる', romaji: 'uta ga kikoeru', meaning: '聽見了歌聲'),
  Phrase(kana: 'あかい りんご', romaji: 'akai ringo', meaning: '紅紅的蘋果'),
  // 移動 — へ/で/に + 移動動詞 (行きます・帰ります・会います)
  Phrase(kana: 'がっこうへ いく', romaji: 'gakkou e iku', meaning: '去學校'),
  Phrase(kana: 'でんしゃで かえる', romaji: 'densha de kaeru', meaning: '搭電車回家'),
  Phrase(kana: 'ともだちに あう', romaji: 'tomodachi ni au', meaning: '和朋友見面'),
  Phrase(kana: 'どこへ いく', romaji: 'doko e iku', meaning: '要去哪裡'),
  // 存在 — に〜がいる/ある
  Phrase(kana: 'こうえんに いぬが いる', romaji: 'kouen ni inu ga iru', meaning: '公園裡有狗'),
  Phrase(
    kana: 'つくえの うえに ねこが いる',
    romaji: 'tsukue no ue ni neko ga iru',
    meaning: '桌上有貓',
  ),
  Phrase(kana: 'ここに ほんが ある', romaji: 'koko ni hon ga aru', meaning: '這裡有書'),
  // を + 動詞 — 日常的動作
  Phrase(kana: 'しゃしんを とる', romaji: 'shashin o toru', meaning: '拍照'),
  Phrase(kana: 'おちゃを のむ', romaji: 'ocha o nomu', meaning: '喝茶'),
  Phrase(kana: 'てがみを かく', romaji: 'tegami o kaku', meaning: '寫信'),
  Phrase(kana: 'ほんを よむ', romaji: 'hon o yomu', meaning: '讀書'),
  Phrase(kana: 'おんがくを きく', romaji: 'ongaku o kiku', meaning: '聽音樂'),
  // 〜たい — 想做的事
  Phrase(kana: 'もっと ききたい', romaji: 'motto kikitai', meaning: '想再多聽一點'),
  Phrase(kana: 'にほんへ いきたい', romaji: 'nihon e ikitai', meaning: '想去日本'),
  Phrase(kana: 'おんせんに はいりたい', romaji: 'onsen ni hairitai', meaning: '想泡溫泉'),
  // 〜てください — 溫柔的請求
  Phrase(
    kana: 'ちょっと まってください',
    romaji: 'chotto matte kudasai',
    meaning: '請稍等一下',
  ),
  Phrase(
    kana: 'もういちど いってください',
    romaji: 'mou ichido itte kudasai',
    meaning: '請再說一次',
  ),
  Phrase(
    kana: 'ゆっくり はなしてください',
    romaji: 'yukkuri hanashite kudasai',
    meaning: '請說慢一點',
  ),
  // 一日 — 時間詞 + 動詞
  Phrase(
    kana: 'けさは はやく おきた',
    romaji: 'kesa wa hayaku okita',
    meaning: '今天早上起得早',
  ),
  Phrase(kana: 'まいあさ おちゃを のむ', romaji: 'maiasa ocha o nomu', meaning: '每天早上喝茶'),
  Phrase(kana: 'よるに ほしを みる', romaji: 'yoru ni hoshi o miru', meaning: '夜裡看星星'),
  Phrase(kana: 'しゅうまつは やすみ', romaji: 'shuumatsu wa yasumi', meaning: '週末休息'),
  // 天氣與季節 — きょうは…
  Phrase(
    kana: 'きょうは あつい',
    romaji: 'kyou wa atsui',
    meaning: '今天很熱',
    season: Season.summer,
  ),
  Phrase(
    kana: 'きょうは さむい',
    romaji: 'kyou wa samui',
    meaning: '今天很冷',
    season: Season.winter,
  ),
  Phrase(
    kana: 'かぜが つめたい',
    romaji: 'kaze ga tsumetai',
    meaning: '風好冰',
    season: Season.winter,
  ),
  Phrase(kana: 'そとは あめ', romaji: 'soto wa ame', meaning: '外面在下雨'),
  Phrase(
    kana: 'はるが きた',
    romaji: 'haru ga kita',
    meaning: '春天來了',
    season: Season.spring,
  ),
  Phrase(
    kana: 'もうすぐ ふゆ',
    romaji: 'mousugu fuyu',
    meaning: '冬天快到了',
    season: Season.winter,
  ),
  Phrase(
    kana: 'あきの ゆうぐれ',
    romaji: 'aki no yuugure',
    meaning: '秋天的黃昏',
    season: Season.autumn,
  ),
  // 過去 — 〜た
  Phrase(kana: 'えいがを みた', romaji: 'eiga o mita', meaning: '看了電影'),
  Phrase(
    kana: 'ともだちと はなした',
    romaji: 'tomodachi to hanashita',
    meaning: '和朋友聊了天',
  ),
  Phrase(kana: 'ゆめを みた', romaji: 'yume o mita', meaning: '做了一個夢'),
  Phrase(
    kana: 'きれいな はなを みつけた',
    romaji: 'kirei na hana o mitsuketa',
    meaning: '發現了漂亮的花',
  ),
  // 否定 — 〜ない
  Phrase(kana: 'きょうは いかない', romaji: 'kyou wa ikanai', meaning: '今天不去'),
  Phrase(kana: 'まだ ねない', romaji: 'mada nenai', meaning: '還不睡'),
  Phrase(kana: 'なにも いらない', romaji: 'nani mo iranai', meaning: '什麼都不需要'),
  // こそあど — 指著問
  Phrase(kana: 'これは なに', romaji: 'kore wa nani', meaning: '這是什麼'),
  Phrase(kana: 'それは わたしの', romaji: 'sore wa watashi no', meaning: '那是我的'),
  Phrase(kana: 'いま なんじ', romaji: 'ima nanji', meaning: '現在幾點'),
  Phrase(kana: 'だれの かさ', romaji: 'dare no kasa', meaning: '誰的傘'),
  // 誘い — 〜よう/〜こう
  Phrase(kana: 'いっしょに いこう', romaji: 'issho ni ikou', meaning: '一起走吧'),
  Phrase(kana: 'いっしょに たべよう', romaji: 'issho ni tabeyou', meaning: '一起吃吧'),
  // 心のうち — 感受與餘韻
  Phrase(kana: 'きょうは たのしかった', romaji: 'kyou wa tanoshikatta', meaning: '今天很開心'),
  Phrase(kana: 'すこし かなしい', romaji: 'sukoshi kanashii', meaning: '有一點悲傷'),
  Phrase(kana: 'こころが しずか', romaji: 'kokoro ga shizuka', meaning: '心很平靜'),
  Phrase(kana: 'ことばに できない', romaji: 'kotoba ni dekinai', meaning: '無法用言語表達'),
  Phrase(
    kana: 'きみと あるいた みち',
    romaji: 'kimi to aruita michi',
    meaning: '和你走過的路',
  ),
  Phrase(
    kana: 'なつが おわる',
    romaji: 'natsu ga owaru',
    meaning: '夏天要結束了',
    season: Season.summer,
  ),
  Phrase(kana: 'つきが きれい', romaji: 'tsuki ga kirei', meaning: '月色真美'),
  Phrase(kana: 'ひとりの よる', romaji: 'hitori no yoru', meaning: '一個人的夜晚'),
  Phrase(kana: 'あめの おと', romaji: 'ame no oto', meaning: '雨聲'),
  Phrase(kana: 'かぜの うた', romaji: 'kaze no uta', meaning: '風之歌'),
  // 旅 — Kyoto / Osaka travel decode: shrine and castle signs, clothing
  // size, an entrance queue, luggage, and a plain ask-for-help. Original
  // short sentences (い／な adjectives and everyday verbs). No event dates.
  Phrase(kana: 'じんじゃは どこ', romaji: 'jinja wa doko', meaning: '神社在哪裡'),
  Phrase(
    kana: 'しずかな てらに はいる',
    romaji: 'shizuka na tera ni hairu',
    meaning: '走進安靜的寺院',
  ),
  Phrase(
    kana: 'ふるい おしろが みえる',
    romaji: 'furui oshiro ga mieru',
    meaning: '看得見古老的城',
  ),
  Phrase(
    kana: 'この ふくは ちいさい',
    romaji: 'kono fuku wa chiisai',
    meaning: '這件衣服太小',
  ),
  Phrase(kana: 'あかい ふくを かう', romaji: 'akai fuku o kau', meaning: '買紅色的衣服'),
  Phrase(kana: 'いりぐちで ならぶ', romaji: 'iriguchi de narabu', meaning: '在入口排隊'),
  Phrase(kana: 'にもつは だいじょうぶ', romaji: 'nimotsu wa daijoubu', meaning: '行李沒問題'),
  Phrase(kana: 'たすけて ください', romaji: 'tasukete kudasai', meaning: '請幫幫我'),
  // 餐廳／便利商店 — party size, order / bill, bag, heat, checkout.
  // Original short chunks. No prices, reservations, or live menus.
  Phrase(kana: 'なんにん ですか', romaji: 'nannin desu ka', meaning: '幾個人'),
  Phrase(kana: 'なにに しますか', romaji: 'nani ni shimasu ka', meaning: '要點什麼'),
  Phrase(
    kana: 'ほかに よろしいですか',
    romaji: 'hoka ni yoroshii desu ka',
    meaning: '還要別的嗎',
  ),
  Phrase(kana: 'ひとりで たべる', romaji: 'hitori de taberu', meaning: '一個人吃'),
  Phrase(kana: 'ふたりで たべる', romaji: 'futari de taberu', meaning: '兩個人吃'),
  Phrase(kana: 'ごはんを ください', romaji: 'gohan o kudasai', meaning: '請給我飯'),
  Phrase(kana: 'かいけいを おねがい', romaji: 'kaikei o onegai', meaning: '請結帳'),
  Phrase(kana: 'ふくろは いりますか', romaji: 'fukuro wa irimasu ka', meaning: '需要袋子嗎'),
  Phrase(kana: 'ふくろは いりません', romaji: 'fukuro wa irimasen', meaning: '不需要袋子'),
  Phrase(kana: 'あたためますか', romaji: 'atatamemasu ka', meaning: '要加熱嗎'),
  Phrase(kana: 'あたためて ください', romaji: 'atatamete kudasai', meaning: '請加熱'),
  Phrase(kana: 'これで おねがい', romaji: 'kore de onegai', meaning: '就這些、請結帳'),
  Phrase(
    kana: 'これで よろしいですか',
    romaji: 'kore de yoroshii desu ka',
    meaning: '就這些可以嗎',
  ),
];
