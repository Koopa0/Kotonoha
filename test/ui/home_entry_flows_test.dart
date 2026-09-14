// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:kotonoha/ui/writing/writing_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

/// #10: home naming / navigation — three closed paths plus narrow / large-text
/// and return-state checks. In-session titles stay Japanese; home entries
/// expose the Chinese action first.
void main() {
  testWidgets('cold start: 學新假名 opens the first row and can finish it', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    expect(find.text(AppStrings.guidanceStartLessons), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsNothing);
    expect(find.text(AppStrings.meetWordsAction), findsNothing);
    expect(find.text(AppStrings.dictationAction), findsNothing);

    await tester.tap(find.text(AppStrings.learnNewKanaAction));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
    expect(find.text(AppStrings.lessonsTitle), findsOneWidget);

    await tester.tap(find.text('あ行'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(AppStrings.nextCard));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(AppStrings.testThisRow));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);

    for (var i = 0; i < 16; i++) {
      if (find.byType(QuizResultScreen).evaluate().isNotEmpty) break;
      await _answerCurrent(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.lessonPassed), findsOneWidget);

    await tester.tap(find.text(AppStrings.backToLessons));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
  });

  testWidgets('returning review: 假名複習 / 安靜練習 start and back restores home', (
    tester,
  ) async {
    await _pumpApp(tester, seedLearned: true);

    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    expect(find.text(AppStrings.dailySession), findsOneWidget);
    expect(find.text(AppStrings.dailyQuiet), findsOneWidget);

    await tester.tap(find.text(AppStrings.reviewKanaAction));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.text(AppStrings.dailySession), findsOneWidget);
    expect(find.textContaining(' / '), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.quietPracticeAction));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
  });

  testWidgets('listening: 學單字 then 聽寫單字 are the available ear-first doors', (
    tester,
  ) async {
    await _pumpApp(tester, seedLearned: true);
    expect(find.text(AppStrings.meetWordsAction), findsOneWidget);
    expect(find.text(AppStrings.ferryEntry), findsOneWidget);
    expect(find.text(AppStrings.ferrySubtitle), findsOneWidget);
    expect(find.text(AppStrings.dictationAction), findsNothing);

    await tester.tap(find.text(AppStrings.meetWordsAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text(AppStrings.ferryTitle), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.meetWordsAction), findsOneWidget);

    final heard = await _pumpApp(tester, seedLearned: true, seedSeenWord: true);
    expect(heard.words.statForItem('word:あい').isSeen, isTrue);
    expect(find.text(AppStrings.dictationAction), findsOneWidget);
    expect(find.text(AppStrings.dictationEntry), findsOneWidget);
    expect(find.text(AppStrings.dictationSubtitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.dictationAction));
    await tester.pumpAndSettle();
    expect(find.byType(DictationScreen), findsOneWidget);
    expect(find.text(AppStrings.dictationTitle), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.dictationAction), findsOneWidget);
  });

  testWidgets('分辨相似假名 / 紙上默寫假名 open rooms and return with progress', (
    tester,
  ) async {
    final repos = await _pumpApp(tester, seedLearned: true);
    expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
    expect(find.text(AppStrings.confusableAction), findsOneWidget);
    expect(find.text(AppStrings.confusableEntry), findsOneWidget);
    expect(find.text(AppStrings.confusableSubtitle), findsOneWidget);
    expect(find.text(AppStrings.writingAction), findsOneWidget);
    expect(find.text(AppStrings.writingEntry), findsOneWidget);
    expect(find.text(AppStrings.writingSubtitle), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.confusableAction));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.text(AppStrings.quizTitleConfusable), findsOneWidget);
    expect(find.textContaining(' / '), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
    expect(find.text(AppStrings.confusableAction), findsOneWidget);
    expect(find.text(AppStrings.writingAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.writingAction));
    await tester.pumpAndSettle();
    expect(find.byType(WritingScreen), findsOneWidget);
    expect(find.text(AppStrings.writingTitle), findsOneWidget);
    expect(find.text(AppStrings.writePrompt), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
    expect(find.text(AppStrings.confusableAction), findsOneWidget);
    expect(find.text(AppStrings.writingAction), findsOneWidget);
  });

  testWidgets('narrow 320 and 1.6x text keep home actions readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await _pumpApp(tester, seedLearned: true, seedSeenWord: true, wide: false);
    expect(tester.takeException(), isNull);

    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    expect(find.text(AppStrings.meetWordsAction), findsOneWidget);
    expect(find.text(AppStrings.dictationAction), findsOneWidget);
    expect(find.text(AppStrings.confusableAction), findsOneWidget);
    expect(find.text(AppStrings.confusableEntry), findsOneWidget);
    expect(find.text(AppStrings.writingAction), findsOneWidget);
    expect(find.text(AppStrings.writingEntry), findsOneWidget);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text(AppStrings.practicedGojuonScope), findsOneWidget);

    final handle = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel(RegExp('學新假名')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('假名複習')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('聽寫單字')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('分辨相似假名')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('紙上默寫假名')), findsWidgets);
      _expectNameAnnouncedOnce(tester, AppStrings.confusableEntry);
      _expectNameAnnouncedOnce(tester, AppStrings.writingEntry);
    } finally {
      handle.dispose();
    }
  });
}

Future<
  ({
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  })
>
_pumpApp(
  WidgetTester tester, {
  bool seedLearned = false,
  bool seedSeenWord = false,
  bool wide = true,
}) async {
  if (wide) {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  SharedPreferences.setMockInitialValues({});
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final words = await WordProgressRepository.load();
  if (seedLearned) {
    await kana.markUnitLearned('hira_row_0');
    for (final k in kana.gojuonForScript(KanaScript.hiragana).take(5)) {
      await kana.recordAnswer(
        k,
        correct: true,
        at: DateTime(2026),
        latencyMs: 300,
      );
    }
    await kana.markUnlockSeen(Unlock.words.id);
  }
  if (seedSeenWord) {
    await words.recordAnswer('word:あい', correct: true, at: DateTime(2026));
  }
  final recovery = await idleRestoreRecovery();
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
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
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

void _expectNameAnnouncedOnce(WidgetTester tester, String name) {
  final escaped = RegExp.escape(name);
  final repeated = RegExp('$escaped.+$escaped', dotAll: true);
  var found = false;
  void visit(SemanticsNode node) {
    final label = node.getSemanticsData().label;
    if (label.contains(name)) {
      found = true;
      expect(
        repeated.hasMatch(label),
        isFalse,
        reason: 'screen reader repeated "$name" in "$label"',
      );
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull);
  visit(root!);
  expect(found, isTrue, reason: 'expected "$name" in a semantics label');
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
