// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// All user-facing UI text, in Traditional Chinese (繁體中文).
///
/// Kana glyphs and romaji are learning *content*, not UI chrome, so they are
/// never translated. Keeping every string here means the interface language
/// lives in one place.
abstract final class AppStrings {
  // App / brand
  static const String appTitle = 'Kotonoha';

  // Home
  static const String dailySession = '今天的練習';
  static const String continueLearning = '開始學習';
  static const String learnHiragana = '五十音表';
  static const String learnHiraganaSubtitle = '瀏覽所有平假名';

  // Lessons (sequential learning)
  static const String lessonsTitle = '循序學習';
  static const String hiraganaSection = '平假名';
  static const String katakanaSection = '片假名';
  static const String extendedSection = '濁音・半濁音・拗音';
  static const String learned = '已學';
  static const String studyThisRow = '學這一行';
  static const String testThisRow = '測驗這一行';
  static const String nextCard = '下一個';
  static const String startTest = '開始測驗';
  static String lessonProgress(int current, int total) => '$current / $total';

  // Study card / TTS
  static const String playSound = '發音';
  static const String tapToHear = '點假名可以聽發音';

  // Lesson result
  static const String lessonPassed = '這一行學會了!';
  static const String lessonNotPassed = '再多練幾次就好,不急。';
  static const String retryLesson = '再測一次';
  static const String backToLessons = '回課程';
  static const String progress = '學習進度';
  static const String progressSubtitle = '目前的學習狀況';
  static const String practiced = '已練習';
  static const String startFirstReview = '開始你的第一次複習';
  static String overallAccuracy(int percent) => '整體正確率 $percent%';

  // Quiz
  static const String quizTitleMissed = '複習答錯的假名';
  static const String chooseRomaji = '選擇羅馬音';
  static const String chooseKana = '選擇假名';
  static const String chooseBySound = '聽發音,選假名';
  static const String replaySound = '再播一次';
  static const String continueLabel = '繼續';
  static const String seeResults = '查看結果';

  // Confusable-pair drill
  static const String confusableEntry = '易混淆練習';
  static const String confusableSubtitle = '專練長得像的假名';
  static const String quizTitleConfusable = '易混淆練習';

  // Handwriting recall (with paper practice book)
  static const String writingEntry = '手寫默寫';
  static const String writingSubtitle = '看題目,在習字本上寫';
  static const String writingTitle = '手寫默寫';
  static const String writePrompt = '在習字本上寫出這個音';
  static const String revealAnswer = '看答案';
  static const String iGotIt = '我寫對了';
  static const String iMissed = '寫錯了';
  static String writingSummary(int correct, int total) =>
      '寫對 $correct / $total';

  // Contextual word reading
  static const String readingEntry = '讀詞練習';
  static const String readingSubtitle = '用學過的假名讀出小詞';
  static const String readingTitle = '讀詞練習';
  static const String readPrompt = '心裡讀讀看這個詞';
  static const String iReadIt = '讀對了';
  static const String iCouldnt = '讀不出';
  static String readingSummary(int correct, int total) =>
      '讀對 $correct / $total';

  // Sentence reading (the phrase track)
  static const String sentenceEntry = '讀句練習';
  static const String sentenceSubtitle = '讀短句,用耳朵確認';
  static const String sentenceTitle = '讀句練習';

  // Kanji reading
  static const String kanjiEntry = '漢字讀音';
  static const String kanjiSubtitle = '讀出漢字的音読・訓読';
  static const String kanjiTitle = '漢字讀音';
  static const String kanjiPrompt = '在心裡讀出這個漢字的音';
  static const String kanjiReveal = '顯示讀音';
  static const String kanjiOnyomi = '音読み';
  static const String kanjiKunyomi = '訓読み';
  static String kanjiAlsoReads(String others) => '也讀:$others';

  // Insights (reads the analytics event stream)
  static const String insightsEntry = '學習洞察';
  static const String insightsSubtitle = '你的練習數據';
  static const String insightsTitle = '學習洞察';
  static const String insightsTotal = '總練習次數';
  static const String insightsAccuracy = '整體正確率';
  static const String insightsAvgRt = '平均反應時間';
  static const String insightsDistinct = '練習過的假名・詞';
  static const String insightsByMode = '各模式練習次數';
  static const String insightsEmpty = '還沒有練習紀錄,先做一次「今天的練習」吧。';
  static String insightsMs(int ms) => '$ms 毫秒';
  static String insightsCount(int n) => '$n 次';

  /// Human label for a [PracticeMode] name in the analytics stream.
  static String modeLabel(String mode) => switch (mode) {
    'daily' => '今天的練習',
    'lessonTest' => '課程測驗',
    'missed' => '複習答錯',
    'confusable' => '易混淆',
    'writing' => '手寫默寫',
    'reading' => '讀詞',
    'quickReview' => '快速複習',
    'kanjiReading' => '漢字讀音',
    _ => mode,
  };

  // Result
  static const String sessionComplete = '本次完成';
  static const String correct = '答對';
  static const String missedKana = '答錯的假名';
  static String reviewMissedKana(int n) => '複習答錯的假名（$n）';
  static const String done = '完成';
  static const String resultPerfect = '全部答對，做得很好。';
  static const String resultStrong = '表現不錯，還有幾個要再複習。';
  static const String resultGood = '做得好，複習一下下面答錯的假名。';
  static const String resultKeepGoing = '這些需要多練習，放輕鬆來。';

  // Learn — status legend & detail sheet
  static const String statusNew = '未學';
  static const String statusLearning = '學習中';
  static const String statusWeak = '待加強';
  static const String statusStrong = '熟練';
  static const String notPracticedYet = '尚未練習';
  static const String statSeen = '練習次數';
  static const String statCorrect = '答對';
  static const String statMissed = '答錯';
  static const String statAccuracy = '正確率';

  // Progress
  static const String accuracy = '正確率';
  static String practicedOfTotal(int seen, int total) =>
      '已練習 $total 個假名中的 $seen 個';
}
