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
/// Each writtenForm is the same utterance in everyday Japanese orthography.
/// It is revealed alongside the kana, never used as a new progress identity.
///
/// Pure data: no `package:flutter/*` imports.
const List<Phrase> kPhrases = <Phrase>[
  Phrase(
    kana: 'そらが あおい',
    writtenForm: '空が青い',
    romaji: 'sora ga aoi',
    meaning: '天空是藍的',
  ),
  Phrase(
    kana: 'なつの かぜ',
    writtenForm: '夏の風',
    romaji: 'natsu no kaze',
    meaning: '夏天的風',
    season: Season.summer,
  ),
  Phrase(
    kana: 'うみが みえる',
    writtenForm: '海が見える',
    romaji: 'umi ga mieru',
    meaning: '看得見海',
  ),
  Phrase(
    kana: 'きみの こえ',
    writtenForm: '君の声',
    romaji: 'kimi no koe',
    meaning: '你的聲音',
  ),
  Phrase(
    kana: 'きみが すき',
    writtenForm: '君が好き',
    romaji: 'kimi ga suki',
    meaning: '喜歡你',
  ),
  Phrase(
    kana: 'みずを ください',
    writtenForm: '水をください',
    romaji: 'mizu o kudasai',
    meaning: '請給我水',
  ),
  Phrase(
    kana: 'えきは どこ',
    writtenForm: '駅はどこ',
    romaji: 'eki wa doko',
    meaning: '車站在哪裡',
  ),
  Phrase(
    kana: 'たたかうか もどるか',
    writtenForm: '戦うか戻るか',
    romaji: 'tatakau ka modoru ka',
    meaning: '戰鬥還是返回',
  ),
  // 季節 — the seasonal / 物の哀れ register: sky, rain, snow, wind, flowers,
  // moon, stars. The quiet beauty of passing things.
  Phrase(
    kana: 'あさの ひかり',
    writtenForm: '朝の光',
    romaji: 'asa no hikari',
    meaning: '清晨的光',
  ),
  Phrase(
    kana: 'あめが ふる',
    writtenForm: '雨が降る',
    romaji: 'ame ga furu',
    meaning: '下起雨了',
  ),
  Phrase(
    kana: 'あめが やむ',
    writtenForm: '雨がやむ',
    romaji: 'ame ga yamu',
    meaning: '雨停了',
  ),
  Phrase(
    kana: 'ゆきが ふる',
    writtenForm: '雪が降る',
    romaji: 'yuki ga furu',
    meaning: '雪落下',
    season: Season.winter,
  ),
  Phrase(
    kana: 'かぜが すずしい',
    writtenForm: '風が涼しい',
    romaji: 'kaze ga suzushii',
    meaning: '風涼涼的',
    season: Season.autumn,
  ),
  Phrase(
    kana: 'かぜが おどる',
    writtenForm: '風が踊る',
    romaji: 'kaze ga odoru',
    meaning: '風在跳舞',
    season: Season.spring,
  ),
  Phrase(
    kana: 'はなが さいた',
    writtenForm: '花が咲いた',
    romaji: 'hana ga saita',
    meaning: '花開了',
    season: Season.spring,
  ),
  Phrase(
    kana: 'はなが ちる',
    writtenForm: '花が散る',
    romaji: 'hana ga chiru',
    meaning: '花謝了',
    season: Season.spring,
  ),
  Phrase(
    kana: 'くもが ながれる',
    writtenForm: '雲が流れる',
    romaji: 'kumo ga nagareru',
    meaning: '雲緩緩流動',
  ),
  Phrase(
    kana: 'そらを みる',
    writtenForm: '空を見る',
    romaji: 'sora o miru',
    meaning: '抬頭望天',
  ),
  Phrase(
    kana: 'つきが でる',
    writtenForm: '月が出る',
    romaji: 'tsuki ga deru',
    meaning: '月亮升起',
    season: Season.autumn,
  ),
  Phrase(
    kana: 'つきが まるい',
    writtenForm: '月が丸い',
    romaji: 'tsuki ga marui',
    meaning: '月亮圓圓的',
    season: Season.autumn,
  ),
  Phrase(
    kana: 'ほしが ひかる',
    writtenForm: '星が光る',
    romaji: 'hoshi ga hikaru',
    meaning: '星星閃著光',
  ),
  Phrase(
    kana: 'ほしが ながれる',
    writtenForm: '星が流れる',
    romaji: 'hoshi ga nagareru',
    meaning: '流星劃過',
  ),
  Phrase(
    kana: 'みずに うつる そら',
    writtenForm: '水に映る空',
    romaji: 'mizu ni utsuru sora',
    meaning: '映在水面的天空',
  ),
  Phrase(
    kana: 'ふゆの しずけさ',
    writtenForm: '冬の静けさ',
    romaji: 'fuyu no shizukesa',
    meaning: '冬日的靜謐',
    season: Season.winter,
  ),
  // 日々 — small everyday moments and gentle feelings: home, a voice, a cat,
  // a little tiredness, a song. Warm and plain.
  Phrase(kana: 'ただいま', writtenForm: 'ただいま', romaji: 'tadaima', meaning: '我回來了'),
  Phrase(kana: 'おかえり', writtenForm: 'おかえり', romaji: 'okaeri', meaning: '你回來啦'),
  Phrase(
    kana: 'あなたに あいたい',
    writtenForm: 'あなたに会いたい',
    romaji: 'anata ni aitai',
    meaning: '好想見你',
  ),
  Phrase(
    kana: 'こえを ききたい',
    writtenForm: '声を聞きたい',
    romaji: 'koe o kikitai',
    meaning: '好想聽你的聲音',
  ),
  Phrase(
    kana: 'すこし つかれた',
    writtenForm: '少し疲れた',
    romaji: 'sukoshi tsukareta',
    meaning: '有點累了',
  ),
  Phrase(
    kana: 'ねこが ねむる',
    writtenForm: '猫が眠る',
    romaji: 'neko ga nemuru',
    meaning: '貓兒睡著了',
  ),
  Phrase(
    kana: 'こねこが ねむい',
    writtenForm: '子猫が眠い',
    romaji: 'koneko ga nemui',
    meaning: '小貓睏了',
  ),
  Phrase(
    kana: 'ねこが わらう',
    writtenForm: '猫が笑う',
    romaji: 'neko ga warau',
    meaning: '貓兒在笑',
  ),
  Phrase(
    kana: 'おかしが すき',
    writtenForm: 'お菓子が好き',
    romaji: 'okashi ga suki',
    meaning: '喜歡甜點',
  ),
  Phrase(
    kana: 'うたが きこえる',
    writtenForm: '歌が聞こえる',
    romaji: 'uta ga kikoeru',
    meaning: '聽見了歌聲',
  ),
  Phrase(
    kana: 'あかい りんご',
    writtenForm: '赤いりんご',
    romaji: 'akai ringo',
    meaning: '紅紅的蘋果',
  ),
  // 移動 — へ/で/に + 移動動詞 (行きます・帰ります・会います)
  Phrase(
    kana: 'がっこうへ いく',
    writtenForm: '学校へ行く',
    romaji: 'gakkou e iku',
    meaning: '去學校',
  ),
  Phrase(
    kana: 'でんしゃで かえる',
    writtenForm: '電車で帰る',
    romaji: 'densha de kaeru',
    meaning: '搭電車回家',
  ),
  Phrase(
    kana: 'ともだちに あう',
    writtenForm: '友達に会う',
    romaji: 'tomodachi ni au',
    meaning: '和朋友見面',
  ),
  Phrase(
    kana: 'どこへ いく',
    writtenForm: 'どこへ行く',
    romaji: 'doko e iku',
    meaning: '要去哪裡',
  ),
  // 存在 — に〜がいる/ある
  Phrase(
    kana: 'こうえんに いぬが いる',
    writtenForm: '公園に犬がいる',
    romaji: 'kouen ni inu ga iru',
    meaning: '公園裡有狗',
  ),
  Phrase(
    kana: 'つくえの うえに ねこが いる',
    writtenForm: '机の上に猫がいる',
    romaji: 'tsukue no ue ni neko ga iru',
    meaning: '桌上有貓',
  ),
  Phrase(
    kana: 'ここに ほんが ある',
    writtenForm: 'ここに本がある',
    romaji: 'koko ni hon ga aru',
    meaning: '這裡有書',
  ),
  // を + 動詞 — 日常的動作
  Phrase(
    kana: 'しゃしんを とる',
    writtenForm: '写真を撮る',
    romaji: 'shashin o toru',
    meaning: '拍照',
  ),
  Phrase(
    kana: 'おちゃを のむ',
    writtenForm: 'お茶を飲む',
    romaji: 'ocha o nomu',
    meaning: '喝茶',
  ),
  Phrase(
    kana: 'てがみを かく',
    writtenForm: '手紙を書く',
    romaji: 'tegami o kaku',
    meaning: '寫信',
  ),
  Phrase(
    kana: 'ほんを よむ',
    writtenForm: '本を読む',
    romaji: 'hon o yomu',
    meaning: '讀書',
  ),
  Phrase(
    kana: 'おんがくを きく',
    writtenForm: '音楽を聞く',
    romaji: 'ongaku o kiku',
    meaning: '聽音樂',
  ),
  // 〜たい — 想做的事
  Phrase(
    kana: 'もっと ききたい',
    writtenForm: 'もっと聞きたい',
    romaji: 'motto kikitai',
    meaning: '想再多聽一點',
  ),
  Phrase(
    kana: 'にほんへ いきたい',
    writtenForm: '日本へ行きたい',
    romaji: 'nihon e ikitai',
    meaning: '想去日本',
  ),
  Phrase(
    kana: 'おんせんに はいりたい',
    writtenForm: '温泉に入りたい',
    romaji: 'onsen ni hairitai',
    meaning: '想泡溫泉',
  ),
  // 〜てください — 溫柔的請求
  Phrase(
    kana: 'ちょっと まってください',
    writtenForm: 'ちょっと待ってください',
    romaji: 'chotto matte kudasai',
    meaning: '請稍等一下',
  ),
  Phrase(
    kana: 'もういちど いってください',
    writtenForm: 'もう一度言ってください',
    romaji: 'mou ichido itte kudasai',
    meaning: '請再說一次',
  ),
  Phrase(
    kana: 'ゆっくり はなしてください',
    writtenForm: 'ゆっくり話してください',
    romaji: 'yukkuri hanashite kudasai',
    meaning: '請說慢一點',
  ),
  // 一日 — 時間詞 + 動詞
  Phrase(
    kana: 'けさは はやく おきた',
    writtenForm: '今朝は早く起きた',
    romaji: 'kesa wa hayaku okita',
    meaning: '今天早上起得早',
  ),
  Phrase(
    kana: 'まいあさ おちゃを のむ',
    writtenForm: '毎朝お茶を飲む',
    romaji: 'maiasa ocha o nomu',
    meaning: '每天早上喝茶',
  ),
  Phrase(
    kana: 'よるに ほしを みる',
    writtenForm: '夜に星を見る',
    romaji: 'yoru ni hoshi o miru',
    meaning: '夜裡看星星',
  ),
  Phrase(
    kana: 'しゅうまつは やすみ',
    writtenForm: '週末は休み',
    romaji: 'shuumatsu wa yasumi',
    meaning: '週末休息',
  ),
  // 天氣與季節 — きょうは…
  Phrase(
    kana: 'きょうは あつい',
    writtenForm: '今日は暑い',
    romaji: 'kyou wa atsui',
    meaning: '今天很熱',
    season: Season.summer,
  ),
  Phrase(
    kana: 'きょうは さむい',
    writtenForm: '今日は寒い',
    romaji: 'kyou wa samui',
    meaning: '今天很冷',
    season: Season.winter,
  ),
  Phrase(
    kana: 'かぜが つめたい',
    writtenForm: '風が冷たい',
    romaji: 'kaze ga tsumetai',
    meaning: '風好冰',
    season: Season.winter,
  ),
  Phrase(
    kana: 'そとは あめ',
    writtenForm: '外は雨',
    romaji: 'soto wa ame',
    meaning: '外面在下雨',
  ),
  Phrase(
    kana: 'はるが きた',
    writtenForm: '春が来た',
    romaji: 'haru ga kita',
    meaning: '春天來了',
    season: Season.spring,
  ),
  Phrase(
    kana: 'もうすぐ ふゆ',
    writtenForm: 'もうすぐ冬',
    romaji: 'mousugu fuyu',
    meaning: '冬天快到了',
    season: Season.winter,
  ),
  Phrase(
    kana: 'あきの ゆうぐれ',
    writtenForm: '秋の夕暮れ',
    romaji: 'aki no yuugure',
    meaning: '秋天的黃昏',
    season: Season.autumn,
  ),
  // 過去 — 〜た
  Phrase(
    kana: 'えいがを みた',
    writtenForm: '映画を見た',
    romaji: 'eiga o mita',
    meaning: '看了電影',
  ),
  Phrase(
    kana: 'ともだちと はなした',
    writtenForm: '友達と話した',
    romaji: 'tomodachi to hanashita',
    meaning: '和朋友聊了天',
  ),
  Phrase(
    kana: 'ゆめを みた',
    writtenForm: '夢を見た',
    romaji: 'yume o mita',
    meaning: '做了一個夢',
  ),
  Phrase(
    kana: 'きれいな はなを みつけた',
    writtenForm: 'きれいな花を見つけた',
    romaji: 'kirei na hana o mitsuketa',
    meaning: '發現了漂亮的花',
  ),
  // 否定 — 〜ない
  Phrase(
    kana: 'きょうは いかない',
    writtenForm: '今日は行かない',
    romaji: 'kyou wa ikanai',
    meaning: '今天不去',
  ),
  Phrase(
    kana: 'まだ ねない',
    writtenForm: 'まだ寝ない',
    romaji: 'mada nenai',
    meaning: '還不睡',
  ),
  Phrase(
    kana: 'なにも いらない',
    writtenForm: '何もいらない',
    romaji: 'nani mo iranai',
    meaning: '什麼都不需要',
  ),
  // こそあど — 指著問
  Phrase(
    kana: 'これは なに',
    writtenForm: 'これは何',
    romaji: 'kore wa nani',
    meaning: '這是什麼',
  ),
  Phrase(
    kana: 'それは わたしの',
    writtenForm: 'それは私の',
    romaji: 'sore wa watashi no',
    meaning: '那是我的',
  ),
  Phrase(
    kana: 'いま なんじ',
    writtenForm: '今何時',
    romaji: 'ima nanji',
    meaning: '現在幾點',
  ),
  Phrase(
    kana: 'だれの かさ',
    writtenForm: '誰の傘',
    romaji: 'dare no kasa',
    meaning: '誰的傘',
  ),
  // 誘い — 〜よう/〜こう
  Phrase(
    kana: 'いっしょに いこう',
    writtenForm: '一緒に行こう',
    romaji: 'issho ni ikou',
    meaning: '一起走吧',
  ),
  Phrase(
    kana: 'いっしょに たべよう',
    writtenForm: '一緒に食べよう',
    romaji: 'issho ni tabeyou',
    meaning: '一起吃吧',
  ),
  // 心のうち — 感受與餘韻
  Phrase(
    kana: 'きょうは たのしかった',
    writtenForm: '今日は楽しかった',
    romaji: 'kyou wa tanoshikatta',
    meaning: '今天很開心',
  ),
  Phrase(
    kana: 'すこし かなしい',
    writtenForm: '少し悲しい',
    romaji: 'sukoshi kanashii',
    meaning: '有一點悲傷',
  ),
  Phrase(
    kana: 'こころが しずか',
    writtenForm: '心が静か',
    romaji: 'kokoro ga shizuka',
    meaning: '心很平靜',
  ),
  Phrase(
    kana: 'ことばに できない',
    writtenForm: '言葉にできない',
    romaji: 'kotoba ni dekinai',
    meaning: '無法用言語表達',
  ),
  Phrase(
    kana: 'きみと あるいた みち',
    writtenForm: '君と歩いた道',
    romaji: 'kimi to aruita michi',
    meaning: '和你走過的路',
  ),
  Phrase(
    kana: 'なつが おわる',
    writtenForm: '夏が終わる',
    romaji: 'natsu ga owaru',
    meaning: '夏天要結束了',
    season: Season.summer,
  ),
  Phrase(
    kana: 'つきが きれい',
    writtenForm: '月がきれい',
    romaji: 'tsuki ga kirei',
    meaning: '月色真美',
  ),
  Phrase(
    kana: 'ひとりの よる',
    writtenForm: '一人の夜',
    romaji: 'hitori no yoru',
    meaning: '一個人的夜晚',
  ),
  Phrase(
    kana: 'あめの おと',
    writtenForm: '雨の音',
    romaji: 'ame no oto',
    meaning: '雨聲',
  ),
  Phrase(
    kana: 'かぜの うた',
    writtenForm: '風の歌',
    romaji: 'kaze no uta',
    meaning: '風之歌',
  ),
  // 旅 — Kyoto / Osaka travel decode: shrine and castle signs, clothing
  // size / try-on / fitting-room / cash checkout, an entrance queue,
  // luggage, and a plain ask-for-help. Original short sentences
  // (い／な adjectives and everyday verbs). Most lines stay hiragana;
  // the card-availability pair keeps カード as the heard shop chunk.
  // No event dates or yen amounts.
  Phrase(
    kana: 'じんじゃは どこ',
    writtenForm: '神社はどこ',
    romaji: 'jinja wa doko',
    meaning: '神社在哪裡',
  ),
  Phrase(
    kana: 'しずかな てらに はいる',
    writtenForm: '静かな寺に入る',
    romaji: 'shizuka na tera ni hairu',
    meaning: '走進安靜的寺院',
  ),
  Phrase(
    kana: 'ふるい おしろが みえる',
    writtenForm: '古いお城が見える',
    romaji: 'furui oshiro ga mieru',
    meaning: '看得見古老的城',
  ),
  Phrase(
    kana: 'この ふくは ちいさい',
    writtenForm: 'この服は小さい',
    romaji: 'kono fuku wa chiisai',
    meaning: '這件衣服太小',
  ),
  Phrase(
    kana: 'あかい ふくを かう',
    writtenForm: '赤い服を買う',
    romaji: 'akai fuku o kau',
    meaning: '買紅色的衣服',
  ),
  Phrase(
    kana: 'しちゃくして いいですか',
    writtenForm: '試着していいですか',
    romaji: 'shichaku shite ii desu ka',
    meaning: '可以試穿嗎',
  ),
  Phrase(
    kana: 'しちゃくしつは どこ',
    writtenForm: '試着室はどこ',
    romaji: 'shichakushitsu wa doko',
    meaning: '試衣間在哪裡',
  ),
  Phrase(
    kana: 'げんきんは いいですか',
    writtenForm: '現金はいいですか',
    romaji: 'genkin wa ii desu ka',
    meaning: '可以用現金嗎',
  ),
  Phrase(
    kana: 'げんきんで かいけい',
    writtenForm: '現金で会計',
    romaji: 'genkin de kaikei',
    meaning: '用現金結帳',
  ),
  Phrase(
    kana: 'カードは つかえます',
    writtenForm: 'カードは使えます',
    romaji: 'kaado wa tsukaemasu',
    meaning: '可以用卡',
  ),
  Phrase(
    kana: 'カードは つかえません',
    writtenForm: 'カードは使えません',
    romaji: 'kaado wa tsukaemasen',
    meaning: '不能用卡',
  ),
  Phrase(
    kana: 'いりぐちで ならぶ',
    writtenForm: '入口で並ぶ',
    romaji: 'iriguchi de narabu',
    meaning: '在入口排隊',
  ),
  Phrase(
    kana: 'にもつは だいじょうぶ',
    writtenForm: '荷物は大丈夫',
    romaji: 'nimotsu wa daijoubu',
    meaning: '行李沒問題',
  ),
  Phrase(
    kana: 'たすけて ください',
    writtenForm: '助けてください',
    romaji: 'tasukete kudasai',
    meaning: '請幫幫我',
  ),
  // 餐廳／便利商店 — party size, order / bill, bag, heat, checkout.
  // Original short chunks. No prices, reservations, or live menus.
  Phrase(
    kana: 'なんにん ですか',
    writtenForm: '何人ですか',
    romaji: 'nannin desu ka',
    meaning: '幾個人',
  ),
  Phrase(
    kana: 'なにに しますか',
    writtenForm: '何にしますか',
    romaji: 'nani ni shimasu ka',
    meaning: '要點什麼',
  ),
  Phrase(
    kana: 'ほかに よろしいですか',
    writtenForm: 'ほかによろしいですか',
    romaji: 'hoka ni yoroshii desu ka',
    meaning: '還要別的嗎',
  ),
  Phrase(
    kana: 'ひとりで たべる',
    writtenForm: '一人で食べる',
    romaji: 'hitori de taberu',
    meaning: '一個人吃',
  ),
  Phrase(
    kana: 'ふたりで たべる',
    writtenForm: '二人で食べる',
    romaji: 'futari de taberu',
    meaning: '兩個人吃',
  ),
  Phrase(
    kana: 'ごはんを ください',
    writtenForm: 'ご飯をください',
    romaji: 'gohan o kudasai',
    meaning: '請給我飯',
  ),
  Phrase(
    kana: 'かいけいを おねがい',
    writtenForm: '会計をお願い',
    romaji: 'kaikei o onegai',
    meaning: '請結帳',
  ),
  Phrase(
    kana: 'ふくろは いりますか',
    writtenForm: '袋はいりますか',
    romaji: 'fukuro wa irimasu ka',
    meaning: '需要袋子嗎',
  ),
  Phrase(
    kana: 'ふくろは いりません',
    writtenForm: '袋はいりません',
    romaji: 'fukuro wa irimasen',
    meaning: '不需要袋子',
  ),
  Phrase(
    kana: 'あたためますか',
    writtenForm: '温めますか',
    romaji: 'atatamemasu ka',
    meaning: '要加熱嗎',
  ),
  Phrase(
    kana: 'あたためて ください',
    writtenForm: '温めてください',
    romaji: 'atatamete kudasai',
    meaning: '請加熱',
  ),
  Phrase(
    kana: 'これで おねがい',
    writtenForm: 'これでお願い',
    romaji: 'kore de onegai',
    meaning: '就這些、請結帳',
  ),
  Phrase(
    kana: 'これで よろしいですか',
    writtenForm: 'これでよろしいですか',
    romaji: 'kore de yoroshii desu ka',
    meaning: '就這些可以嗎',
  ),
  // 旅館 — name a reservation, ask to check in, ask about breakfast, say
  // you leave tomorrow. Original short chunks. No booking, prices, or
  // clock times. とまる is "to stay" (JF); check-in is チェックイン.
  Phrase(
    kana: 'よやくが あります',
    writtenForm: '予約があります',
    romaji: 'yoyaku ga arimasu',
    meaning: '我有預約',
  ),
  Phrase(
    kana: 'チェックインを おねがい',
    writtenForm: 'チェックインをお願い',
    romaji: 'chekkuin o onegai',
    meaning: '請辦理入住',
  ),
  Phrase(
    kana: 'あさごはんは ありますか',
    writtenForm: '朝ご飯はありますか',
    romaji: 'asagohan wa arimasu ka',
    meaning: '有早餐嗎',
  ),
  Phrase(
    kana: 'あした でます',
    writtenForm: '明日出ます',
    romaji: 'ashita demasu',
    meaning: '明天退房離開',
  ),
  // Airport and onward transport: original practical travel utterances.
  Phrase(
    kana: 'この バスは くうこうに いきますか',
    writtenForm: 'このバスは空港に行きますか',
    romaji: 'kono basu wa kuukou ni ikimasu ka',
    meaning: '這班公車有到機場嗎',
  ),
  Phrase(
    kana: 'くうこうまで おねがいします',
    writtenForm: '空港までお願いします',
    romaji: 'kuukou made onegai shimasu',
    meaning: '請到機場',
  ),
  Phrase(
    kana: 'ひこうきに のります',
    writtenForm: '飛行機に乗ります',
    romaji: 'hikouki ni norimasu',
    meaning: '搭飛機',
  ),
  Phrase(
    kana: 'りょうがえは どこで できますか',
    writtenForm: '両替はどこでできますか',
    romaji: 'ryougae wa doko de dekimasu ka',
    meaning: '哪裡可以換錢',
  ),
  Phrase(
    kana: 'かいさつは どこですか',
    writtenForm: '改札はどこですか',
    romaji: 'kaisatsu wa doko desu ka',
    meaning: '驗票閘門在哪裡',
  ),
  Phrase(
    kana: 'のりかえは どこですか',
    writtenForm: '乗り換えはどこですか',
    romaji: 'norikae wa doko desu ka',
    meaning: '在哪裡轉乘',
  ),
];
