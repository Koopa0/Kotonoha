// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #100 P2: empty progress → ん／ン row test must not mint forced-correct MCQs.
/// Singleton rows use kanaRecall on the first attempt and on retry.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Lessons → ん: test uses recall, not a one-option MCQ', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    await _openLesson(tester, title: 'ん', encodeCards: 1);
    await _tapTest(tester);

    final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
    expect(quiz.items, isNotEmpty);
    expect(
      quiz.items.every((i) => i.question.direction == QuizDirection.kanaRecall),
      isTrue,
    );
    expect(find.byType(AnswerOptionButton), findsNothing);

    await _gradeRecallCorrect(tester);
    await _gradeRecallCorrect(tester);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.lessonPassed), findsOneWidget);
    expect(repos.kana.isUnitLearned('hira_row_10'), isTrue);
  });

  testWidgets('Lessons → ン: retry stays on recall, not forced-correct MCQ', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openLesson(tester, title: 'ン', encodeCards: 1);
    await _tapTest(tester);

    await _gradeRecallWrong(tester);
    await _gradeRecallWrong(tester);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.lessonNotPassed), findsOneWidget);

    await tester.tap(find.text(AppStrings.retryLesson));
    await tester.pumpAndSettle();

    final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
    expect(
      quiz.items.every((i) => i.question.direction == QuizDirection.kanaRecall),
      isTrue,
    );
    expect(find.byType(AnswerOptionButton), findsNothing);
    expect(quiz.items.every((i) => !i.question.isForcedCorrect), isTrue);
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

Future<void> _openLesson(
  WidgetTester tester, {
  required String title,
  required int encodeCards,
}) async {
  await tester.tap(find.text(AppStrings.learnNewKanaAction));
  await tester.pumpAndSettle();
  expect(find.byType(LessonsScreen), findsOneWidget);

  final tile = find.byWidgetPredicate((widget) {
    if (widget is! ListTile) return false;
    final label = widget.title;
    return label is Text && label.data == title;
  }, description: 'ListTile titled $title');
  await tester.scrollUntilVisible(
    tile,
    400,
    scrollable: find
        .descendant(
          of: find.byType(LessonsScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();

  for (var i = 0; i < encodeCards - 1; i++) {
    await tester.tap(find.text(AppStrings.nextCard));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapTest(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.testThisRow));
  await tester.pumpAndSettle();
  expect(find.byType(QuizScreen), findsOneWidget);
}

Future<void> _gradeRecallCorrect(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await tester.pump();
  await tester.tap(find.text(AppStrings.iReadIt));
  await tester.pump();
  await _advanceQuiz(tester);
}

Future<void> _gradeRecallWrong(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await tester.pump();
  await tester.tap(find.text(AppStrings.iCouldnt));
  await tester.pump();
  await _advanceQuiz(tester);
}

Future<void> _advanceQuiz(WidgetTester tester) async {
  final next = find.text(AppStrings.continueLabel);
  if (next.evaluate().isNotEmpty) {
    await tester.tap(next);
  } else {
    await tester.tap(find.text(AppStrings.seeResults));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
