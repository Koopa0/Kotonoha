// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/false_friend.dart';

/// Time-of-day band for the 凪 close — its send-off softens once it's late.
enum ClosingBand {
  day,
  night;

  /// Dusk threshold: at or after 19:00 the close gives permission to stop.
  static const int _nightHour = 19;

  static ClosingBand forHour(int hour) =>
      hour >= _nightHour ? ClosingBand.night : ClosingBand.day;
}

/// All user-facing UI text, in Traditional Chinese (繁體中文).
///
/// Kana glyphs and romaji are learning *content*, not UI chrome, so they are
/// never translated. Keeping every string here means the interface language
/// lives in one place.
abstract final class AppStrings {
  // App / brand
  // Presentation always uses 言の葉; "kotonoha" stays a code-only identifier.
  static const String appTitle = '言の葉';

  // Home
  static const String dailySession = '今日の稽古';
  // A quiet, per-tap alternate door into 今日の稽古: a silent run with no
  // listening prompts — for practising without sound (e.g. on a commute).
  static const String dailyQuiet = '静かに';
  static const String continueLearning = '手解き';
  static const String learnHiragana = '五十音図';
  static const String learnHiraganaSubtitle = '瀏覽所有平假名';

  // Home entry actions — Chinese scan labels so a beginner can name the work
  // without first knowing the Japanese room names. Product names stay on the
  // second line (and as in-session titles); existing 繁中 hints stay as-is.
  static const String learnNewKanaAction = '學新假名';
  static const String reviewKanaAction = '假名複習';
  static const String quietPracticeAction = '安靜練習';
  static const String meetWordsAction = '學單字';
  static const String dictationAction = '聽寫單字';
  static const String readPhrasesAction = '讀短句';
  static const String readKanjiSentencesAction = '漢字句閱讀';

  // Guidance — the ambient one-line "next step" + the home card-path section
  // headers. The pure use_case returns only a target (+ a count); the 繁中 copy
  // lives here in the UI layer, so the domain stays Flutter-free.
  static const String coldStartCaption = '五十音,先一行一行學起';
  static const String guidanceStartLessons = '先從「手解き」開始,學會第一行假名 —— 它會一個一個帶你念。';
  static String guidanceReview(int n) => '今天先做「今日の稽古」—— 有 $n 個假名該複習了。';
  static const String guidanceLearnMore = '複習都跟上了 —— 繼續「手解き」,學新的一行。';
  static String guidanceWordsReview(int n) => '今天先做「文字起こし」—— 有 $n 個詞等著再會。';
  static String guidanceSentencesReview(int n) => '今天先讀「黙読」—— 有 $n 句想被再讀一次。';
  static String guidanceKanjiSentencesReview(int n) =>
      '今天先讀「名残の仮名」—— 有 $n 句等著再讀一次。';
  static const String guidanceMeetKanjiSentences = '到「名残の仮名」—— 讀幾句新的日語。';
  static String guidanceKanjiReview(int n) => '今天先做「漢字の声」—— 有 $n 個讀音該複習了。';
  static const String guidanceMeetWords = '假名都熟了 —— 坐「渡し舟」,去見新的詞。';
  static const String guidanceMeetSentences = '詞都見過了 —— 到「黙読」,讀新的句子。';
  static const String guidanceMeetKanji = '到「漢字の声」看看 —— 還有新的讀音等著見面。';
  static const String guidanceCaughtUp = '該複習的都熟了 —— 今天想讀什麼都好。';
  static const String sectionKana = '假名';
  static const String sectionWords = '詞と句';
  static const String sectionKanji = '漢字';
  static const String sectionLookBack = '回望';

  // 同形異義語 — a gentle, on-demand note in 渡し舟 when a word's kanji means
  // something different in Japanese than a Chinese reader would assume. Affirm
  // the Japanese meaning first; the contrast is a soft aside, never a warning.
  static const String falseFriendTrigger = '日文意思?';
  static String falseFriendNote(FalseFriend ff) =>
      '日文的「${ff.kanji}」,是「${ff.jaMeaning}」。${ff.zhNote}';

  // ④ これは? — a pull-not-push orientation line at the foot of home. Always
  // available, never auto-shown, never modal: tap to reveal how to learn.
  static const String aboutTrigger = 'これは?';
  static const String aboutBody =
      '先學五十音,讀得動了再慢慢往「詞と句」、漢字走。「手解き」一行一行帶你認字,'
      '「今日の稽古」幫你複習該複習的;其他的房間,等你讀得動了自然會開。';

  // ④ 言の葉 とは — the name's meaning, woven into the same fold (pull, never
  // pushed). The 仮名序 line is public domain (Ki no Tsurayuki, c. 905); the
  // gloss is our own. Presented by restraint — a quiet epigraph, not a lecture.
  static const String nameMeaningHeading = '言の葉 とは';
  static const String nameMeaningLine = 'やまとうたは、人の心を種として、よろづの言の葉とぞなれりける';
  static const String nameMeaningGloss =
      '「言葉的葉子」。歌以人的心為種子,長成萬片言の葉 —— 語言不是被操練出來的,'
      '是像花開一樣,慢慢長出來的。這個 app 想做的,就是陪你長出幾片。';
  static const String nameMeaningAttribution = '紀貫之・古今和歌集 仮名序(約 905 年)';

  // Unlock lines (guidance ③) — a quiet word the first time a new KIND of
  // practice opens, instead of a card silently appearing. Warm, observational,
  // never a trophy. Japanese feature names stay verbatim (learning content).
  static const String unlockWords = '你學會的假名,已經拼得出一個詞了 —— 「詞と句」開了。';
  static const String unlockPhrases = '假名夠多了,短句也讀得動了 —— 「黙読」開了。';
  static const String unlockKanjiPhrases =
      '帶漢字的句子,假名的部分你已經讀得出來了 —— 「名残の仮名」開了,讀音會慢慢淡出。';
  static const String unlockDismiss = '知道了';

  // Lessons (sequential learning)
  static const String lessonsTitle = '手解き';
  static const String hiraganaSection = '平假名';
  static const String katakanaSection = '片假名';
  static const String extendedSection = '濁音・半濁音・拗音';
  static const String testThisRow = '測驗這一行';
  static const String nextCard = '下一個';

  /// The "n / m" position counter shared by every paged practice (手解き study,
  /// 黙読, 渡し舟, 文字起こし, 漢字の声, 名残の仮名) — one source so the format
  /// never drifts between screens.
  static String itemProgress(int current, int total) => '$current / $total';

  // Study card / TTS
  static const String playSound = '發音';
  static const String tapToHear = '點假名可以聽發音';

  // The optional recall lap on the last 手解き encode card — a calm second pass
  // (glyph only, romaji behind a tap) before the row test. Opt-in: the default
  // is to go straight to 測驗這一行. Never graded, never scored.
  static const String studyReviewOnce = '再看一次';

  // Lesson result
  static const String lessonPassed = '這一行學會了!';
  static const String lessonNotPassed = '再多練幾次就好,不急。';
  static const String retryLesson = '再測一次';
  static const String backToLessons = '回課程';
  static const String progress = '歩み';
  static const String progressSubtitle = '目前的學習狀況';
  static const String practiced = '已練習';

  // Quiz
  static const String quizTitleMissed = '複習答錯的假名';
  static const String chooseRomaji = '選擇羅馬音';
  static const String chooseKana = '選擇假名';
  static const String chooseBySound = '聽發音,選假名';
  static const String replaySound = '再播一次';
  static const String continueLabel = '繼續';
  static const String seeResults = '查看結果';

  // Confusable-pair drill
  static const String confusableEntry = '目利き';
  static const String confusableSubtitle = '專練長得像、容易看錯的假名';
  static const String quizTitleConfusable = '目利き';

  // Handwriting recall (with paper practice book)
  static const String writingEntry = '手習い';
  static const String writingSubtitle = '看題目,在習字本上寫';
  static const String writingTitle = '手習い';
  static const String writePrompt = '在習字本上寫出這個音';
  static const String revealAnswer = '看答案';
  static const String iGotIt = '我寫對了';
  static const String iMissed = '寫錯了';
  static String writingSummary(int correct, int total) =>
      '寫對 $correct / $total';

  // Shared reading-screen strings (讀句 + the 渡し舟 grade buttons). The
  // word-reading entry was folded into 渡し舟 — the ear-first word reader.
  static const String readPrompt = '心裡讀讀看';
  static const String iReadIt = '讀對了';
  static const String iReadUnprompted = '讀得出來';
  static const String iReadAfterHint = '現在讀對了';
  static const String iCouldnt = '讀不出';
  static String readingSummary(int correct, int total) =>
      '讀對 $correct / $total';

  // Unprompted kana recall inside 今日の稽古 — same quiet self-grade as 黙読,
  // never a second score table. 看答案 is shared with 手習い.
  static const String recallHint = '看讀音';

  // 文字を起こす Dictation (hear → assemble the kana)
  static const String dictationEntry = '文字起こし';
  static const String dictationSubtitle = '聽發音,自己拼出假名';
  static const String dictationTitle = '文字起こし';
  static const String dictationPrompt = '聽聽看,拼出這個詞';
  static const String dictationClear = '清除';
  static const String dictationNext = '下一個';

  // 聞き取り — listen first, recall, reveal, rehear. #10 may rename the card;
  // this slice only adds an entry, it does not relabel neighbouring rooms.
  static const String listeningEntry = '聞き取り';
  static const String listeningSubtitle = '先聽對方在問什麼,再揭曉';
  static const String listeningTitle = '聞き取り';
  static const String listeningPrompt = '先聽聽看,對方在問什麼';
  static const String listeningRecall = '在心裡回想剛才聽到的';
  static const String listeningReveal = '揭曉';
  static const String listeningRehear = '再聽一次,對照看';
  static const String listeningHeard = '聽懂了';
  static const String listeningMissed = '沒聽懂';
  static const String listeningSkip = '這一題先跳過';
  static const String listeningUnavailable = '現在播不出聲音,這一題不算作答。';
  static const String listeningFailed = '剛才沒播出來,這一題不算作答。';
  static const String listeningInterrupted = '播放中斷了,這一題還不能算聽過。';
  static String listeningSummary(int correct, int total) =>
      '聽懂 $correct / $total';

  // 渡し舟 The Ferry (hear → see → read back)
  static const String ferryEntry = '渡し舟';
  static const String ferrySubtitle = '先聽,再讓文字浮現,然後自己讀';
  static const String ferryTitle = '渡し舟';
  static const String ferryHear = '先聽聽看';
  static const String ferrySee = '聽到的,就是這個';
  static const String ferryReadback = '現在,自己讀出聲';
  static const String ferryShowText = '看文字';
  static const String ferryReadSelf = '自己讀';

  // 助詞 gloss — a quiet on-tap in the 黙読 reveal for the particles that are READ
  // differently than they're spelled (は→wa, を→o, へ→e). A reading aid, never a
  // grammar lesson; が・の・に read as spelled, so they carry no gloss.
  static const String particleGlossTrigger = '助詞?';
  static String? particleGloss(String particle) => switch (particle) {
    'は' => 'は — 主題,讀作 wa(不是 ha)。',
    'を' => 'を — 受詞,讀作 o(不是 wo)。',
    'へ' => 'へ — 方向,讀作 e(不是 he)。',
    _ => null,
  };

  // Sentence reading (the phrase track)
  static const String sentenceEntry = '黙読';
  static const String sentenceSubtitle = '讀短句,心裡默讀,再用耳朵確認';
  static const String sentenceTitle = '黙読';

  // Kanji reading (漢字の声) — ear-first teach, then a cold choose-the-reading.
  static const String kanjiEntry = '漢字の声';
  static const String kanjiSubtitle = '讀出漢字的音読・訓読';
  static const String kanjiTitle = '漢字の声';
  static const String kanjiOnyomi = '音読み';
  static const String kanjiKunyomi = '訓読み';
  static const String kanjiTeachHint = '先聽它的音,記下來';
  static const String kanjiChooseReading = '這個字,怎麼讀?';

  /// Accessible stem: the sentence plus which local word holds the target
  /// run — never the reading itself. 手話 vs 話す tells two 話 apart.
  static String kanjiAccessibleStem({
    required String sentence,
    required String localWord,
    required String written,
  }) {
    if (localWord == written) {
      return '$sentence。問的是「$written」。';
    }
    return '$sentence。問的是「$localWord」裡的「$written」。';
  }

  static const String kanjiNext = '次へ';

  // Kanji sentence reading (furigana fades as readings mature)
  static const String kanjiSentenceEntry = '名残の仮名';
  // Honest promise: only readings the learner has actually met in 漢字の声 can
  // fade. A kanji the curriculum hasn't reached keeps its furigana for good.
  static const String kanjiSentenceSubtitle = '讀日語的句子;學過的漢字,讀音會慢慢淡出';
  static const String kanjiSentenceTitle = '名残の仮名';
  static const String kanjiSentencePrompt = '在心裡讀出整句';

  // 回望 observation — the one quiet, hard-gated notebook line in 歩み, mined from
  // real misclicks. It carries no number: a present-tense STATE, being seen not
  // scored. Several sibling phrasings, picked DETERMINISTICALLY per pair (the same
  // confusion always reads the same), so the notebook feels observed, not templated.
  // Every sibling must stay number-free and present-tense — never praise/progress.
  static String confusionLine(String target, String mistakenFor) {
    final i = (target.hashCode ^ mistakenFor.hashCode).abs() % 3;
    return switch (i) {
      0 => '最近,常把「$target」看成「$mistakenFor」。',
      1 => '「$target」和「$mistakenFor」,還沒完全分開。',
      _ => '「$target」這陣子,還容易和「$mistakenFor」靠在一起。',
    };
  }

  // Result
  static const String sessionCloseLine = '今天就到這裡,辛苦了。';

  /// The shared send-off clause: the same all day, softening at night where it
  /// gives permission to stop (余韻). One source for both close variants below.
  static String _sendOff(ClosingBand band) => switch (band) {
    ClosingBand.day => '去過你的一天吧。',
    ClosingBand.night => '今天就到這裡,好好休息。',
  };

  /// The 凪 close's quiet fact. The competence clause is identical all day; only
  /// the send-off softens at night — where it gives permission to stop (余韻).
  static String closingNote(String item, {required ClosingBand band}) =>
      '今天,和「$item」更熟了一點。${_sendOff(band)}';

  /// The 凪 close can echo the IMAGE just read (黙読 etc.) instead of the
  /// glyph-familiarity line — 余韻 at the emotional peak. Keyed ONLY on the item
  /// + band, never the score (performance-invariant). Curated for the strongest
  /// images; null for everything else so the caller falls back to [closingNote].
  static const Map<String, String> _closingImages = {
    'ゆきが ふる': '雪,還在落著。',
    'あめが ふる': '雨,還在下。',
    'あめが やむ': '雨,停了。',
    'はなが ちる': '花,正落著。',
    'はなが さいた': '花,開了。',
    'つきが でる': '月亮,出來了。',
    'ほしが ながれる': '一顆星,劃過去了。',
    'くもが ながれる': '雲,慢慢流過。',
    'かぜが すずしい': '風,涼涼的。',
    'ふゆの しずけさ': '冬日,靜了下來。',
  };

  static String? closingEcho(String item, {required ClosingBand band}) {
    final image = _closingImages[item];
    if (image == null) return null;
    return '$image${_sendOff(band)}';
  }

  /// The 凪 close note: echo the image if it's a curated one (余韻), else the
  /// quiet glyph-familiarity line. Both are performance-invariant.
  static String closing(String item, {required ClosingBand band}) =>
      closingEcho(item, band: band) ?? closingNote(item, band: band);

  // The opt-in 「釋」 pull under a classical 余韻 line at the close: tap to unfold a
  // slightly deeper background / 季語 / 詩境 note. Default stays one calm line.
  static const String kotenNoteTrigger = '釋';

  static const String sessionComplete = '本次完成';
  static const String missedKana = '答錯的假名';
  static String reviewMissedKana(int n) => '複習答錯的假名（$n）';
  static const String done = '完成';
  // One calm, low-emphasis "one more round" on the 今日の稽古 / 目利き result —
  // opt-in volume for those who want it, never the primary action.
  static const String practiceAgain = 'もう一回';

  // Learn — status legend & detail sheet
  static const String statusNew = '未學';
  static const String statusLearning = '學習中';
  static const String statusWeak = '待加強';
  static const String statusStrong = '熟練';
  static const String notPracticedYet = '尚未練習';

  // Progress persistence — the one calm, cross-route surface. Normal saving is
  // silent; these speak only when a write failed (offering a retry) or when a
  // damaged store recovered at startup (an honest, session-dismissible notice).
  // 歩み = the learner's progress. No number, no alarm — the same quiet voice.
  static const String persistFailedLine = '這次的歩み還沒寫進裝置。';
  static const String persistFailedDetail = '內容仍留在這次開啟中,可以再試一次。';
  static const String persistRetry = '再試一次';
  // Shown on the retry action while a retry is in flight — the button is not a
  // live target, so a second tap can't be silently swallowed.
  static const String persistRetrying = '正在再試…';
  static const String persistAck = '知道了';

  // One honest recovery line per StoreHealth outcome — each says exactly what
  // happened to the old data, never claiming more safety than is true and never
  // calling a recovery a fresh start. Most-severe wins when stores coalesce.
  // salvaged names no proportion (the count is unknown); it only affirms the
  // readable rest and the raw were both kept.
  static const String persistRecoverySalvaged = '有些舊的歩み讀不回來,其餘可讀的都保住了,原始資料也留著。';
  static const String persistRecoveryRestored = '這次的歩み是從上一次完好的存檔接回來的,原始資料留著。';
  // A startup-time fact (not a present claim a later successful write would
  // silently falsify): at this launch the damaged raw was not yet confirmed
  // set aside, while the progress itself was recovered.
  static const String persistRecoveryPreservationPending =
      '這次啟動時,損壞的原始資料還沒能確認另存;歩み已先接回來了。';
  static const String persistRecoveryRecoveryRequired =
      '先前的歩み一時讀不回來,現在可能是空的;原始資料還留著,沒有被蓋掉。';
}
