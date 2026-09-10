// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #36 acceptance: real 手解き → row quiz pass → Home → Daily for the
/// tiny rows. ん／ン hide the review door; わ／や still open with 2／3
/// options and never cold-quiz an unlearned target.
void main() {
  testWidgets('ん row pass hides Daily; a forced tap would not be reachable', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    await _passRow(tester, title: 'ん', encodeCards: 1);
    expect(repos.kana.isUnitLearned('hira_row_10'), isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsNothing);
    expect(find.text(AppStrings.quietPracticeAction), findsNothing);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.writingEntry), findsOneWidget);
  });

  testWidgets('ン row pass hides Daily the same way', (tester) async {
    final repos = await _pumpApp(tester);
    await _passRow(tester, title: 'ン', encodeCards: 1);
    expect(repos.kana.isUnitLearned('kata_row_10'), isTrue);
    expect(find.text(AppStrings.reviewKanaAction), findsNothing);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
  });

  testWidgets('わ行 pass opens Daily as a 2-option review, all learned', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    await _passRow(tester, title: 'わ行', encodeCards: 2);
    expect(repos.kana.isUnitLearned('hira_row_9'), isTrue);
    await _openDailyAndExpectOptions(tester, optionCount: 2);
    _expectDailyTargetsLearned(tester, repos.kana);
  });

  testWidgets('や行 pass opens Daily as a 3-option review, all learned', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    await _passRow(tester, title: 'や行', encodeCards: 3);
    expect(repos.kana.isUnitLearned('hira_row_7'), isTrue);
    await _openDailyAndExpectOptions(tester, optionCount: 3);
    _expectDailyTargetsLearned(tester, repos.kana);
  });

  testWidgets('ワ行 / ヤ行 katakana counterparts match the hiragana doors', (
    tester,
  ) async {
    final wa = await _pumpApp(tester);
    await _passRow(tester, title: 'ワ行', encodeCards: 2);
    expect(wa.kana.isUnitLearned('kata_row_9'), isTrue);
    await _openDailyAndExpectOptions(tester, optionCount: 2);

    final ya = await _pumpApp(tester);
    await _passRow(tester, title: 'ヤ行', encodeCards: 3);
    expect(ya.kana.isUnitLearned('kata_row_7'), isTrue);
    await _openDailyAndExpectOptions(tester, optionCount: 3);
  });

  testWidgets('あ行 pass still opens a 4-option Daily', (tester) async {
    final repos = await _pumpApp(tester);
    await _passRow(tester, title: 'あ行', encodeCards: 5);
    expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
    await _openDailyAndExpectOptions(tester, optionCount: 4);
    _expectDailyTargetsLearned(tester, repos.kana);
  });
}

Future<
  ({
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  })
>
_pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final words = await WordProgressRepository.load();
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
            health: [
              kana.statsHealth,
              kana.learnedUnitsHealth,
              kana.seenUnlocksHealth,
              kanji.statsHealth,
              words.statsHealth,
            ],
          ),
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (kana: kana, kanji: kanji, words: words);
}

Future<void> _passRow(
  WidgetTester tester, {
  required String title,
  required int encodeCards,
}) async {
  await tester.tap(find.text(AppStrings.learnNewKanaAction));
  await tester.pumpAndSettle();
  expect(find.byType(LessonsScreen), findsOneWidget);

  final tile = find.widgetWithText(ListTile, title);
  await tester.scrollUntilVisible(
    tile,
    400,
    scrollable: find.descendant(
      of: find.byType(LessonsScreen),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();

  for (var i = 0; i < encodeCards - 1; i++) {
    await tester.tap(find.text(AppStrings.nextCard));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(AppStrings.testThisRow));
  await tester.pumpAndSettle();
  expect(find.byType(QuizScreen), findsOneWidget);

  for (var i = 0; i < 20; i++) {
    if (find.byType(QuizResultScreen).evaluate().isNotEmpty) break;
    await _answerCurrent(tester);
  }
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.lessonPassed), findsOneWidget);

  await tester.tap(find.text(AppStrings.backToLessons));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.byType(HomeScreen), findsOneWidget);
}

Future<void> _openDailyAndExpectOptions(
  WidgetTester tester, {
  required int optionCount,
}) async {
  expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
  await tester.tap(find.text(AppStrings.reviewKanaAction));
  await tester.pumpAndSettle();
  expect(find.byType(QuizScreen), findsOneWidget);
  expect(find.byType(AnswerOptionButton), findsNWidgets(optionCount));
}

void _expectDailyTargetsLearned(
  WidgetTester tester,
  KanaProgressRepository store,
) {
  final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
  final learnedIds = StudySet.learned(store).map((k) => k.id).toSet();
  for (final item in quiz.items) {
    expect(learnedIds.contains(item.question.target.id), isTrue);
    expect(item.question.hasDiscrimination, isTrue);
  }
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
