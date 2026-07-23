// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手解き teaches a row in two passes: an honest ENCODE (romaji always shown —
/// you cannot recall a kana you have never met) then an OPT-IN recall lap
/// (glyph only, romaji behind a tap). The lap is never graded; the default is
/// straight to the row test, unchanged.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpStudy(
    WidgetTester tester,
    KanaProgressRepository store,
    AnalyticsLog analytics,
    Lesson lesson,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: store.flushPending,
              kanjiFlush: () async {},
            ),
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: MaterialApp(home: StudyScreen(lesson: lesson)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Lesson twoKana() => Lesson(
    id: 'hira_row_0',
    title: 'あ行',
    kana: kHiraganaGojuon.take(2).toList(),
  );

  testWidgets('encode shows romaji; 再看一次 opens a romaji-gated recall lap', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    await pumpStudy(tester, store, InMemoryAnalyticsLog(), twoKana());

    // Encode card 1 (あ): romaji visible WITHOUT tapping (honest encode).
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text(AppStrings.tapToHear), findsOneWidget);

    // Advance to the last encode card (い).
    await tester.tap(find.text(AppStrings.nextCard));
    await tester.pumpAndSettle();
    expect(find.text('i'), findsOneWidget); // still an honest encode
    // The last encode card offers a choice: test now, or the optional lap.
    expect(find.text(AppStrings.testThisRow), findsOneWidget);
    expect(find.text(AppStrings.studyReviewOnce), findsOneWidget);

    // Take the recall lap → back to the top, romaji now hidden behind a tap.
    await tester.tap(find.text(AppStrings.studyReviewOnce));
    await tester.pumpAndSettle();
    expect(find.text('あ'), findsOneWidget); // glyph (the cue) still shown
    expect(find.text('a'), findsNothing); // answer withheld
    expect(find.text(AppStrings.readPrompt), findsOneWidget);
    expect(find.text(AppStrings.revealAnswer), findsOneWidget);

    // Reveal confirms this card.
    await tester.tap(find.text(AppStrings.revealAnswer));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);

    // Advancing resets the reveal; the last recap card leads to the test only.
    await tester.tap(find.text(AppStrings.nextCard));
    await tester.pumpAndSettle();
    expect(find.text('i'), findsNothing); // hidden again on the next card
    expect(find.text(AppStrings.testThisRow), findsOneWidget);
    expect(find.text(AppStrings.studyReviewOnce), findsNothing); // lap is over
  });

  testWidgets('default path: 測驗這一行 goes straight to the test, no recap', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final analytics = InMemoryAnalyticsLog();
    await pumpStudy(tester, store, analytics, twoKana());

    // Skip the lap: page to the last encode card and tap the test.
    await tester.tap(find.text(AppStrings.nextCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.testThisRow));
    await tester.pumpAndSettle();

    // The row test replaced study; nothing was recorded during study itself.
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.byType(StudyScreen), findsNothing);
    expect(await analytics.all(), isEmpty);
  });
}
