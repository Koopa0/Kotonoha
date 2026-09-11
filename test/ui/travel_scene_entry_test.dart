// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/info/info_hub_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_screen.dart';
import 'package:kotonoha/ui/reply/reply_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({KanaProgressRepository kana, WordProgressRepository words})>
  pumpHome(WidgetTester tester) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await tester.binding.setSurfaceSize(const Size(420, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return (kana: kana, words: words);
  }

  Future<void> learnRows(
    KanaProgressRepository kana,
    Iterable<int> rows,
  ) async {
    for (final row in rows) {
      await kana.markUnitLearned('hira_row_$row');
    }
  }

  Future<void> openScene(WidgetTester tester, String scene) async {
    await tester.ensureVisible(find.text(AppStrings.travelSceneAction));
    await tester.tap(find.text(AppStrings.travelSceneAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneScreen), findsOneWidget);
    await tester.tap(find.text(scene));
    await tester.pumpAndSettle();
  }

  testWidgets('home keeps both 換句 and 選旅遊場景 after main merge', (tester) async {
    await pumpHome(tester);
    expect(find.text(AppStrings.shiftAction), findsOneWidget);
    expect(find.text(AppStrings.shiftEntry), findsOneWidget);
    expect(find.text(AppStrings.travelSceneAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneEntry), findsOneWidget);

    await tester.ensureVisible(find.text(AppStrings.shiftAction));
    await tester.tap(find.text(AppStrings.shiftAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftPickerLead), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.travelSceneAction));
    await tester.tap(find.text(AppStrings.travelSceneAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneScreen), findsOneWidget);
    expect(find.text(AppStrings.travelSceneTransport), findsOneWidget);
  });

  testWidgets('newbie: travel entry is present and only offers 先學假名', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    expect(find.text(AppStrings.travelSceneAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneEntry), findsOneWidget);

    await openScene(tester, AppStrings.travelSceneTransport);
    expect(find.text(AppStrings.travelScenePurposeTransport), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
    expect(find.text(AppStrings.travelSceneRecallAction), findsNothing);
    expect(find.text(AppStrings.travelSceneListenAction), findsNothing);
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.text(AppStrings.travelSceneLearnAction));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
    expect(repos.words.seenItemCount, 0);
  });

  testWidgets('partial あ行・か行: two scenes stay distinct and can meet', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [0, 1]);
    await tester.pumpAndSettle();

    await openScene(tester, AppStrings.travelSceneTransport);
    expect(find.text(AppStrings.travelScenePurposeTransport), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneRecallAction), findsNothing);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneMeetTitle(AppStrings.travelSceneTransport),
      ),
      findsOneWidget,
    );
    expect(find.text('えき'), findsNothing); // ferry hides kana on hear beat
    expect(find.text('ふく'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneClothing));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelScenePurposeClothing), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeTransport), findsNothing);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneMeetTitle(AppStrings.travelSceneClothing),
      ),
      findsOneWidget,
    );
    expect(find.text('えき'), findsNothing);
  });

  testWidgets('returning: seen transport can recall and reuse 聞き取り', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [0, 1]);
    await repos.words.markIntroduced('word:えき', at: DateTime(2026, 9, 10, 12));
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('word:えき').isSeen, isTrue);
    expect(repos.words.statForItem('word:えき').srsLevel, 0);

    await openScene(tester, AppStrings.travelSceneTransport);
    expect(find.text(AppStrings.travelSceneRecallAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneListenAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelSceneRecallAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text('えき'), findsOneWidget);
    expect(find.text('ふく'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.travelSceneListenAction));
    await tester.pumpAndSettle();
    expect(find.byType(ListeningScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneListenTitle(AppStrings.travelSceneTransport),
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.listeningPrompt), findsOneWidget);
    await tester.tap(find.text(AppStrings.listeningReveal));
    await tester.pumpAndSettle();
    expect(find.text('えき'), findsOneWidget);
    expect(find.text('ふく'), findsNothing);

    expect(repos.words.statForItem('word:ふく').isSeen, isFalse);
    expect(repos.words.statForItem('word:えき').srsLevel, 0);
  });

  testWidgets('newbie: shrine and park only offer 先學假名 and write nothing', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await tester.ensureVisible(find.text(AppStrings.travelSceneAction));
    await tester.tap(find.text(AppStrings.travelSceneAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelSceneShrine), findsOneWidget);
    expect(find.text(AppStrings.travelSceneParkQueue), findsOneWidget);
    await tester.ensureVisible(find.text(AppStrings.travelSceneRestaurant));
    expect(find.text(AppStrings.travelSceneRestaurant), findsOneWidget);
    expect(find.text(AppStrings.travelSceneConvenience), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeShrine), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeParkQueue), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeRestaurant), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeConvenience), findsOneWidget);
    expect(find.text('芙莉蓮'), findsNothing);
    expect(find.text('USJ'), findsNothing);

    await tester.tap(find.text(AppStrings.travelSceneShrine));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneHub), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeShrine), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
    expect(find.text(AppStrings.travelSceneRecallAction), findsNothing);
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneParkQueue));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelScenePurposeParkQueue), findsOneWidget);
    expect(find.text(AppStrings.travelScenePurposeShrine), findsNothing);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
    expect(repos.words.seenItemCount, 0);
  });

  Future<void> finishLessonRow(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(AppStrings.nextCard));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(AppStrings.testThisRow));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    for (var i = 0; i < 24; i++) {
      if (find.byType(QuizResultScreen).evaluate().isNotEmpty) break;
      await _answerCurrent(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.lessonPassed), findsOneWidget);
    await tester.tap(find.text(AppStrings.backToLessons));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
  }

  Future<void> finishFerryWord(WidgetTester tester) async {
    expect(find.text(AppStrings.ferryHear), findsOneWidget);
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
  }

  DateTime noon() => DateTime(2026, 9, 10, 12);

  Future<({KanaProgressRepository kana, WordProgressRepository words})> pumpHub(
    WidgetTester tester, {
    required TravelSceneId scene,
  }) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await tester.binding.setSurfaceSize(const Size(420, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: MaterialApp(
          home: TravelSceneHub(scene: scene, clock: noon),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (kana: kana, words: words);
  }

  testWidgets(
    'route return: 先學假名 → あ行／か行 quiz → 回交通 shows 先見面 without reopening',
    (tester) async {
      final repos = await pumpHome(tester);
      await openScene(tester, AppStrings.travelSceneTransport);
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
      expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);

      await tester.tap(find.text(AppStrings.travelSceneLearnAction));
      await tester.pumpAndSettle();
      expect(find.byType(LessonsScreen), findsOneWidget);

      await finishLessonRow(tester, 'あ行');
      expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);

      await tester.tap(find.text(AppStrings.travelSceneLearnAction));
      await tester.pumpAndSettle();
      await finishLessonRow(tester, 'か行');
      expect(repos.kana.isUnitLearned('hira_row_1'), isTrue);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelScenePurposeTransport), findsOneWidget);
      expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
      expect(repos.words.seenItemCount, 0);
    },
  );

  testWidgets(
    'small pool: ferry えき／ここ then もう一回 returns to hub recall／listen',
    (tester) async {
      final repos = await pumpHub(tester, scene: TravelSceneId.transport);
      await learnRows(repos.kana, const [0, 1]);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);

      await tester.tap(find.text(AppStrings.travelSceneMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      await finishFerryWord(tester);
      await finishFerryWord(tester);
      expect(find.text(AppStrings.practiceAgain), findsOneWidget);
      expect(find.text(AppStrings.done), findsOneWidget);

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsNothing);
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelSceneRecallAction), findsOneWidget);
      expect(find.text(AppStrings.travelSceneListenAction), findsOneWidget);
      expect(repos.words.statForItem('word:えき').isSeen, isTrue);
      expect(repos.words.statForItem('word:ここ').isSeen, isTrue);
      expect(repos.words.statForItem('word:ふく').isSeen, isFalse);
    },
  );

  testWidgets('leftover intro: もう一回 keeps the same scene and does not pad', (
    tester,
  ) async {
    final repos = await pumpHub(tester, scene: TravelSceneId.transport);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      if (lesson.id.startsWith('hira')) {
        await repos.kana.markUnitLearned(lesson.id);
      }
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text('1 / 8'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await finishFerryWord(tester);
    }
    expect(find.text(AppStrings.practiceAgain), findsOneWidget);
    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneMeetTitle(AppStrings.travelSceneTransport),
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.ferryHear), findsOneWidget);
    expect(find.text('ふく'), findsNothing);
  });

  testWidgets('partial あ行・さ行: shrine meets いし; park stays 先學假名', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [0, 2]);
    await tester.pumpAndSettle();

    await openScene(tester, AppStrings.travelSceneShrine);
    expect(find.text(AppStrings.travelScenePurposeShrine), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneRecallAction), findsNothing);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(AppStrings.travelSceneMeetTitle(AppStrings.travelSceneShrine)),
      findsOneWidget,
    );
    expect(find.text('まつ'), findsNothing);
    expect(find.text('えき'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneParkQueue));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelScenePurposeParkQueue), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
  });

  testWidgets('partial た行・ま行: park meets まつ; shrine stays 先學假名', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [3, 6]);
    await tester.pumpAndSettle();

    await openScene(tester, AppStrings.travelSceneParkQueue);
    expect(find.text(AppStrings.travelScenePurposeParkQueue), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneMeetTitle(AppStrings.travelSceneParkQueue),
      ),
      findsOneWidget,
    );
    expect(find.text('いし'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneShrine));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelScenePurposeShrine), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
  });

  testWidgets('returning: seen shrine いし can recall and reuse 聞き取り', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [0, 2]);
    await repos.words.markIntroduced('word:いし', at: DateTime(2026, 9, 10, 12));
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('word:いし').srsLevel, 0);

    await openScene(tester, AppStrings.travelSceneShrine);
    expect(find.text(AppStrings.travelSceneRecallAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneListenAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelSceneRecallAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text('いし'), findsOneWidget);
    expect(find.text('まつ'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.travelSceneListenAction));
    await tester.pumpAndSettle();
    expect(find.byType(ListeningScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneListenTitle(AppStrings.travelSceneShrine),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(AppStrings.listeningReveal));
    await tester.pumpAndSettle();
    expect(find.text('いし'), findsOneWidget);
    expect(find.text('まつ'), findsNothing);
    expect(repos.words.statForItem('word:まつ').isSeen, isFalse);
    expect(repos.words.statForItem('word:いし').srsLevel, 0);
  });

  testWidgets(
    'route return: 先學假名 → あ行／さ行 quiz → 回神社 shows 先見面 without reopening',
    (tester) async {
      final repos = await pumpHome(tester);
      await openScene(tester, AppStrings.travelSceneShrine);
      expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
      expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);

      await tester.tap(find.text(AppStrings.travelSceneLearnAction));
      await tester.pumpAndSettle();
      await finishLessonRow(tester, 'あ行');
      expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);

      await tester.tap(find.text(AppStrings.travelSceneLearnAction));
      await tester.pumpAndSettle();
      await finishLessonRow(tester, 'さ行');
      expect(repos.kana.isUnitLearned('hira_row_2'), isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelScenePurposeShrine), findsOneWidget);
      expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
      expect(repos.words.seenItemCount, 0);
    },
  );

  testWidgets(
    'small shrine pool: ferry いし then もう一回 returns to hub recall／listen',
    (tester) async {
      final repos = await pumpHub(tester, scene: TravelSceneId.shrine);
      await learnRows(repos.kana, const [0, 2]);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.travelSceneMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      await finishFerryWord(tester);
      expect(find.text(AppStrings.practiceAgain), findsOneWidget);

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsNothing);
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelSceneRecallAction), findsOneWidget);
      expect(find.text(AppStrings.travelSceneListenAction), findsOneWidget);
      expect(repos.words.statForItem('word:いし').isSeen, isTrue);
      expect(repos.words.statForItem('word:まつ').isSeen, isFalse);
      expect(repos.words.statForItem('word:えき').isSeen, isFalse);
    },
  );

  testWidgets(
    'small park pool: ferry まつ then もう一回 returns to hub recall／listen',
    (tester) async {
      final repos = await pumpHub(tester, scene: TravelSceneId.parkQueue);
      await learnRows(repos.kana, const [3, 6]);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.travelSceneMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      await finishFerryWord(tester);
      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.byType(TravelSceneHub), findsOneWidget);
      expect(find.text(AppStrings.travelSceneRecallAction), findsOneWidget);
      expect(repos.words.statForItem('word:まつ').isSeen, isTrue);
      expect(repos.words.statForItem('word:いし').isSeen, isFalse);
    },
  );

  testWidgets('leftover shrine intro: もう一回 stays shrine and does not pad', (
    tester,
  ) async {
    final repos = await pumpHub(tester, scene: TravelSceneId.shrine);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      if (lesson.id.startsWith('hira')) {
        await repos.kana.markUnitLearned(lesson.id);
      }
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text('1 / 8'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await finishFerryWord(tester);
    }
    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(AppStrings.travelSceneMeetTitle(AppStrings.travelSceneShrine)),
      findsOneWidget,
    );
    expect(find.text('まつ'), findsNothing);
    expect(find.text('ふく'), findsNothing);
  });

  testWidgets('聞き取り home entry still waits for a T01 meeting', (tester) async {
    final repos = await pumpHome(tester);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.listenFirstAction), findsNothing);
    expect(find.text(AppStrings.travelSceneAction), findsOneWidget);
  });

  testWidgets('transport hub does not surface the clothing reply door', (
    tester,
  ) async {
    await pumpHub(tester, scene: TravelSceneId.transport);
    expect(find.text(AppStrings.replyAction), findsNothing);
  });

  testWidgets('clothing hub opens the scoped reply room, not station copy', (
    tester,
  ) async {
    await pumpHub(tester, scene: TravelSceneId.clothing);
    expect(find.text(AppStrings.replyAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.replyAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyHubScreen), findsOneWidget);
    expect(find.text(AppStrings.replyClothingPurpose), findsOneWidget);
    expect(find.text(AppStrings.replyPurpose), findsNothing);
    expect(find.text('えきは どこ'), findsNothing);
  });

  testWidgets('partial さ行: restaurant meets すし; convenience stays 先學假名', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [0, 2]);
    await tester.pumpAndSettle();

    await openScene(tester, AppStrings.travelSceneRestaurant);
    expect(find.text(AppStrings.travelScenePurposeRestaurant), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneRecallAction), findsNothing);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneMeetTitle(AppStrings.travelSceneRestaurant),
      ),
      findsOneWidget,
    );
    expect(find.text('ふくろ'), findsNothing);
    expect(find.text('えき'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneConvenience));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelScenePurposeConvenience), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
  });

  testWidgets(
    'partial か行・は行・ら行: convenience meets ふくろ; restaurant stays 先學假名',
    (tester) async {
      final repos = await pumpHome(tester);
      await learnRows(repos.kana, const [1, 5, 8]);
      await tester.pumpAndSettle();

      await openScene(tester, AppStrings.travelSceneConvenience);
      expect(
        find.text(AppStrings.travelScenePurposeConvenience),
        findsOneWidget,
      );
      expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
      await tester.tap(find.text(AppStrings.travelSceneMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(
        find.text(
          AppStrings.travelSceneMeetTitle(AppStrings.travelSceneConvenience),
        ),
        findsOneWidget,
      );
      expect(find.text('すし'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repos.words.seenItemCount, 0);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.travelSceneRestaurant));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.travelScenePurposeRestaurant),
        findsOneWidget,
      );
      expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
      expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
    },
  );

  testWidgets('returning: seen restaurant すし can recall and reuse 聞き取り', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [0, 2]);
    await repos.words.markIntroduced('word:すし', at: DateTime(2026, 9, 10, 12));
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('word:すし').srsLevel, 0);

    await openScene(tester, AppStrings.travelSceneRestaurant);
    expect(find.text(AppStrings.travelSceneRecallAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneListenAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneRecallAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text('ふくろ'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.travelSceneListenAction));
    await tester.pumpAndSettle();
    expect(find.byType(ListeningScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneListenTitle(AppStrings.travelSceneRestaurant),
      ),
      findsOneWidget,
    );
    expect(repos.words.statForItem('word:すし').srsLevel, 0);
  });

  testWidgets('restaurant hub opens the scoped reply room, not clothing copy', (
    tester,
  ) async {
    await pumpHub(tester, scene: TravelSceneId.restaurant);
    expect(find.text(AppStrings.replyAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.replyAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyHubScreen), findsOneWidget);
    expect(find.text(AppStrings.replyRestaurantPurpose), findsOneWidget);
    expect(find.text(AppStrings.replyClothingPurpose), findsNothing);
    expect(find.text(AppStrings.replyPurpose), findsNothing);
  });

  testWidgets(
    'convenience hub opens the scoped reply room, not restaurant copy',
    (tester) async {
      await pumpHub(tester, scene: TravelSceneId.convenience);
      expect(find.text(AppStrings.replyAction), findsOneWidget);
      await tester.tap(find.text(AppStrings.replyAction));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyHubScreen), findsOneWidget);
      expect(find.text(AppStrings.replyConveniencePurpose), findsOneWidget);
      expect(find.text(AppStrings.replyRestaurantPurpose), findsNothing);
      expect(find.text('なんにん ですか'), findsNothing);
    },
  );

  testWidgets('hotel hub does not surface a reply door', (tester) async {
    await pumpHub(tester, scene: TravelSceneId.hotel);
    expect(find.text(AppStrings.travelScenePurposeHotel), findsOneWidget);
    expect(find.text(AppStrings.replyAction), findsNothing);
  });

  testWidgets('partial は行・や行: hotel meets へや; restaurant stays 先學假名', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnRows(repos.kana, const [5, 7]);
    await tester.pumpAndSettle();

    await openScene(tester, AppStrings.travelSceneHotel);
    expect(find.text(AppStrings.travelScenePurposeHotel), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(AppStrings.travelSceneMeetTitle(AppStrings.travelSceneHotel)),
      findsOneWidget,
    );
    expect(find.text('すし'), findsNothing);
    expect(find.text('ふくろ'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.travelSceneRestaurant));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelScenePurposeRestaurant), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
  });

  testWidgets('Home→旅行→旅館→先見面 Reading 教チェックイン，不教泊まる當入住', (tester) async {
    final repos = await pumpHome(tester);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    for (final id in TravelScene.progressIds[TravelSceneId.hotel]!) {
      if (id.startsWith('word:')) {
        await repos.words.markIntroduced(id, at: noon());
      }
    }
    await tester.pumpAndSettle();

    await openScene(tester, AppStrings.travelSceneHotel);
    expect(find.text(AppStrings.travelScenePurposeHotel), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(
      find.text(AppStrings.travelSceneMeetTitle(AppStrings.travelSceneHotel)),
      findsOneWidget,
    );
    final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
    expect(reading.items.map((i) => i.displayText), contains('チェックインを おねがい'));
    expect(
      reading.items.map((i) => i.displayText),
      isNot(contains('うけつけで とまる')),
    );
    expect(reading.items.map((i) => i.meaning), contains('請辦理入住'));
    expect(reading.items.map((i) => i.meaning), isNot(contains('在櫃檯入住')));

    var found = find.text('チェックインを おねがい').evaluate().isNotEmpty;
    for (var i = 0; i < reading.items.length && !found; i++) {
      await tester.tap(find.text(AppStrings.recallHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      found = find.text('チェックインを おねがい').evaluate().isNotEmpty;
    }
    expect(find.text('チェックインを おねがい'), findsOneWidget);
    expect(find.text('請辦理入住'), findsNothing);
    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pumpAndSettle();
    expect(find.text('chekkuin o onegai'), findsOneWidget);
    expect(find.text('請辦理入住'), findsOneWidget);
    expect(find.text('在櫃檯入住'), findsNothing);
    expect(find.text('うけつけで とまる'), findsNothing);
    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('phrase:チェックインを おねがい').isSeen, isTrue);
  });

  testWidgets('旅館入住 320×640／2× Reading 須看見請辦理入住才能記 seen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repos = await pumpHub(tester, scene: TravelSceneId.hotel);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    for (final id in TravelScene.progressIds[TravelSceneId.hotel]!) {
      if (id == 'phrase:チェックインを おねがい') continue;
      await repos.words.markIntroduced(id, at: noon());
    }
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('phrase:チェックインを おねがい').isSeen, isFalse);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text('チェックインを おねがい'), findsOneWidget);
    await tester.ensureVisible(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iReadUnprompted).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('reading-meaning')),
    );
    await tester.pumpAndSettle();
    expect(find.text('請辦理入住').hitTestable(), findsOneWidget);
    final meaning = tester.getRect(
      find.byKey(const ValueKey<String>('reading-meaning')),
    );
    expect(meaning.bottom, lessThanOrEqualTo(641));
    expect(meaning.top, greaterThanOrEqualTo(-1));
    expect(repos.words.statForItem('phrase:チェックインを おねがい').isSeen, isFalse);
    await tester.ensureVisible(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iReadIt).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('phrase:チェックインを おねがい').isSeen, isTrue);
  });

  testWidgets('travel picker surfaces info extraction entry', (tester) async {
    await pumpHome(tester);
    await tester.ensureVisible(find.text(AppStrings.travelSceneAction));
    await tester.tap(find.text(AppStrings.travelSceneAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneScreen), findsOneWidget);
    expect(find.text(AppStrings.infoAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.infoAction));
    await tester.pumpAndSettle();
    expect(find.byType(InfoHubScreen), findsOneWidget);
    expect(find.text(AppStrings.infoPurpose), findsOneWidget);
  });

  testWidgets('Home→旅行→購衣 states try-on and pay, then meets in-scene', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    await tester.pumpAndSettle();
    await openScene(tester, AppStrings.travelSceneClothing);
    expect(find.text(AppStrings.travelScenePurposeClothing), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    expect(find.text(AppStrings.replyAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneMeetTitle(AppStrings.travelSceneClothing),
      ),
      findsOneWidget,
    );
    expect(find.text('えき'), findsNothing);
    expect(repos.words.seenItemCount, 0);
  });

  testWidgets('clothing reply starts try-on after the request phrase is met', (
    tester,
  ) async {
    final repos = await pumpHub(tester, scene: TravelSceneId.clothing);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    await repos.words.markIntroduced('word:しちゃく', at: noon());
    await repos.words.markIntroduced('phrase:しちゃくして いいですか', at: noon());
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.replyAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyHubScreen), findsOneWidget);
    expect(find.text(AppStrings.replyClothingPurpose), findsOneWidget);
    expect(find.text(AppStrings.replyStartAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.replyStartAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyScreen), findsOneWidget);
    expect(find.text('你停在外套衣架前。店員從架上取下那一件，看著你。'), findsOneWidget);
    expect(find.text('問要不要試穿'), findsOneWidget);
    expect(find.text('要試穿嗎'), findsNothing);
    expect(find.text('しちゃくしますか'), findsNothing);
    expect(find.text(AppStrings.replyNotSpeaking), findsOneWidget);
  });

  testWidgets('Home→旅行→購衣：つかう 不夠，先教 つかえます／ません 才進可否用卡', (tester) async {
    final repos = await pumpHome(tester);
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    final at = DateTime(2026, 9, 10, 12);
    for (final id in const [
      'phrase:この ふくは ちいさい',
      'phrase:あかい ふくを かう',
      'phrase:しちゃくして いいですか',
      'phrase:しちゃくしつは どこ',
      'phrase:げんきんは いいですか',
      'phrase:げんきんで かいけい',
      'word:おおきい',
      'word:おねがい',
      'word:かう',
      'word:たかい',
      'word:やすい',
      'word:しちゃく',
      'word:しちゃくしつ',
      'word:みぎ',
      'word:ひだり',
      'word:サイズ',
      'word:エル',
      'word:エム',
      'word:カード',
      'word:げんきん',
      'word:つかう',
    ]) {
      await repos.words.markIntroduced(id, at: at);
    }
    await tester.pumpAndSettle();
    await openScene(tester, AppStrings.travelSceneClothing);
    await tester.tap(find.text(AppStrings.replyAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyHubScreen), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    expect(find.text(AppStrings.replyStartAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text(AppStrings.replyClothingMeetTitle), findsOneWidget);
    expect(
      find.text('カードは つかえます').evaluate().isNotEmpty ||
          find.text('カードは つかえません').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('使用'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.replyStartAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyScreen), findsOneWidget);
    expect(find.text('結帳臺。臺上放著你的卡，錢包裡還有現金。'), findsNothing);
    expect(find.text('結帳臺。你只帶了卡，現金不夠付這件。'), findsNothing);
    expect(find.text('搖頭'), findsNothing);
    expect(find.text('カードは つかえません'), findsNothing);
    expect(find.text('カードは つかえます'), findsNothing);
  });

  testWidgets('Home→旅行→購衣：320×640／2x 先見面 つかえません 須看見不能用才能記 seen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repos = await pumpHub(tester, scene: TravelSceneId.clothing);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    for (final lesson in Lessons.fromKana(repos.kana.allKana)) {
      await repos.kana.markUnitLearned(lesson.id);
    }
    for (final id in TravelScene.progressIds[TravelSceneId.clothing]!) {
      if (id == 'word:つかえません') continue;
      await repos.words.markIntroduced(id, at: noon());
    }
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('word:つかえません').isSeen, isFalse);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    expect(find.text('つかえません'), findsOneWidget);
    expect(find.text('不能用'), findsOneWidget);
    expect(
      find.text(AppStrings.ferryReadSelf).hitTestable(),
      findsNothing,
      reason: '未捲到否定意思前不能完成',
    );
    expect(repos.words.statForItem('word:つかえません').isSeen, isFalse);
    await tester.ensureVisible(find.text('不能用'));
    await tester.pumpAndSettle();
    expect(find.text('不能用').hitTestable(), findsOneWidget);
    final meaning = tester.getRect(find.text('不能用'));
    expect(meaning.top, greaterThanOrEqualTo(-1));
    expect(meaning.bottom, lessThanOrEqualTo(641));
    final kana = tester.getRect(find.text('つかえません'));
    expect(kana.bottom, greaterThan(0));
    expect(kana.bottom, lessThanOrEqualTo(641));
    expect(repos.words.statForItem('word:つかえません').isSeen, isFalse);
    await tester.ensureVisible(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iReadIt).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('word:つかえません').isSeen, isTrue);
  });
}

Future<void> _answerCurrent(WidgetTester tester) async {
  final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
  final labels = tester
      .widgetList<AnswerOptionButton>(find.byType(AnswerOptionButton))
      .map((b) => b.label)
      .toList();
  final question = quiz.items.map((item) => item.question).firstWhere((q) {
    if (!listEquals(q.options, labels)) return false;
    if (q.direction == QuizDirection.soundToKana) {
      return find.text(AppStrings.chooseBySound).evaluate().isNotEmpty;
    }
    return find.text(q.prompt).evaluate().isNotEmpty;
  });
  await tester.tap(
    find.widgetWithText(AnswerOptionButton, question.correctAnswer),
  );
  await tester.pump();
  final next = find.text(AppStrings.continueLabel);
  if (next.evaluate().isNotEmpty) {
    await tester.tap(next);
  } else {
    await tester.tap(find.text(AppStrings.seeResults));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
