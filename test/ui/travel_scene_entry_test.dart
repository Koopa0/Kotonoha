// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
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
    await tester.binding.setSurfaceSize(const Size(420, 2600));
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

  testWidgets('later scenes stay listed but are not walkable', (tester) async {
    await pumpHome(tester);
    await tester.ensureVisible(find.text(AppStrings.travelSceneAction));
    await tester.tap(find.text(AppStrings.travelSceneAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelSceneShrine), findsOneWidget);
    expect(find.text(AppStrings.travelSceneParkQueue), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneShrine));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneHub), findsNothing);
    expect(find.byType(TravelSceneScreen), findsOneWidget);
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
}
