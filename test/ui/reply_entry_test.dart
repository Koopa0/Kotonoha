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
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_screen.dart';
import 'package:kotonoha/ui/reply/reply_screen.dart';
import 'package:kotonoha/ui/shift/shift_focus_screen.dart';
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
    await tester.binding.setSurfaceSize(const Size(420, 2800));
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

  Future<void> learnAll(KanaProgressRepository kana) async {
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
  }

  Future<void> openReply(WidgetTester tester) async {
    await tester.ensureVisible(find.text(AppStrings.replyAction));
    await tester.tap(find.text(AppStrings.replyAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyHubScreen), findsOneWidget);
  }

  testWidgets('home keeps 換句、旅の場面 and 短く返す', (tester) async {
    await pumpHome(tester);
    expect(find.text(AppStrings.shiftAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneAction), findsOneWidget);
    expect(find.text(AppStrings.replyAction), findsOneWidget);
    expect(find.text(AppStrings.replyEntry), findsOneWidget);

    await tester.ensureVisible(find.text(AppStrings.shiftAction));
    await tester.tap(find.text(AppStrings.shiftAction));
    await tester.pumpAndSettle();
    expect(find.byType(ShiftFocusScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.travelSceneAction));
    await tester.tap(find.text(AppStrings.travelSceneAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneScreen), findsOneWidget);
    expect(find.text(AppStrings.travelSceneTransport), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openReply(tester);
    expect(find.text(AppStrings.replyPurpose), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.replyStartAction), findsNothing);
  });

  testWidgets('newbie: hub only offers 先學假名 and writes nothing', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await openReply(tester);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
    expect(find.text(AppStrings.replyStartAction), findsNothing);
    await tester.tap(find.text(AppStrings.travelSceneLearnAction));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
    expect(repos.words.seenItemCount, 0);
  });

  testWidgets('all kana unmet: 先見面 is station material, not clothing', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnAll(repos.kana);
    await tester.pumpAndSettle();
    await openReply(tester);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    expect(find.text(AppStrings.replyStartAction), findsNothing);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text(AppStrings.replyMeetTitle), findsOneWidget);
    expect(find.text('ふく'), findsNothing);
    expect(repos.words.seenItemCount, 0);
  });

  testWidgets('seen えきは どこ can start; clothing stays out', (tester) async {
    final repos = await pumpHome(tester);
    await learnAll(repos.kana);
    await repos.words.markIntroduced(
      'phrase:えきは どこ',
      at: DateTime(2026, 9, 10, 12),
    );
    await tester.pumpAndSettle();
    expect(repos.words.statForItem('phrase:えきは どこ').srsLevel, 0);

    await openReply(tester);
    expect(find.text(AppStrings.replyStartAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.replyStartAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReplyScreen), findsOneWidget);
    expect(find.text(AppStrings.replyIntentPrompt), findsOneWidget);
    expect(find.text('問車站在哪裡'), findsOneWidget);
    expect(find.text('この ふくは ちいさい'), findsNothing);
    expect(find.text('えきは どこ'), findsNothing);
    expect(repos.words.statForItem('phrase:えきは どこ').srsLevel, 0);
  });

  testWidgets('unmet phrases after words still meet via 黙読, not start', (
    tester,
  ) async {
    final repos = await pumpHome(tester);
    await learnAll(repos.kana);
    await repos.words.markIntroduced('word:えき', at: DateTime(2026, 9, 10, 12));
    await repos.words.markIntroduced('word:ここ', at: DateTime(2026, 9, 10, 12));
    await tester.pumpAndSettle();
    await openReply(tester);
    expect(find.text(AppStrings.replyStartAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelSceneMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text(AppStrings.replyMeetTitle), findsOneWidget);
    expect(find.text('ふく'), findsNothing);
  });
}
