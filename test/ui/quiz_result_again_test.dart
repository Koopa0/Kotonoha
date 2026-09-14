// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // An empty answer list is a finished session with nothing missed — a "perfect"
  // result — enough to exercise the action set without composing questions.
  const perfect = QuizResult(answers: []);

  QuizQuestion q(String character) {
    final target = kHiraganaGojuon.firstWhere((k) => k.character == character);
    return QuizQuestion(
      target: target,
      direction: QuizDirection.kanaToRomaji,
      options: [target.romaji, 'xx', 'yy', 'zz'],
      correctIndex: 0,
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final store = await KanaProgressRepository.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: store.flushPending,
              kanjiFlush: () async {},
              wordFlush: () async {},
            ),
          ),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('再来一回 shows on a non-lesson result, low-emphasis and last', (
    tester,
  ) async {
    await pump(tester, QuizResultScreen(result: perfect, onAgain: () {}));

    expect(find.text(AppStrings.practiceAgain), findsOneWidget);
    // Low-emphasis: an OutlinedButton, never the primary FilledButton.
    expect(
      find.widgetWithText(OutlinedButton, AppStrings.practiceAgain),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing); // perfect ⇒ no review CTA
    // 完成 reads first; 再来一回 sits last, so leaving stays the default.
    final doneY = tester.getTopLeft(find.text(AppStrings.done)).dy;
    final againY = tester.getTopLeft(find.text(AppStrings.practiceAgain)).dy;
    expect(doneY, lessThan(againY));
  });

  testWidgets('再来一回 is hidden when there is no onAgain', (tester) async {
    await pump(tester, const QuizResultScreen(result: perfect));
    expect(find.text(AppStrings.practiceAgain), findsNothing);
    expect(find.text(AppStrings.done), findsOneWidget);
  });

  testWidgets('再来一回 never appears on a lesson result', (tester) async {
    final lesson = Lesson(
      id: 'hira_row_0',
      title: 'あ行',
      kana: [kHiraganaGojuon.first],
    );
    await pump(
      tester,
      QuizResultScreen(result: perfect, lesson: lesson, onAgain: () {}),
    );
    expect(find.text(AppStrings.practiceAgain), findsNothing);
    expect(find.text(AppStrings.backToLessons), findsOneWidget);
  });

  // RULER guard (retention-ruler #1): the 凪 close shows the score ONLY as a raw,
  // muted footnote — never an accuracy %, never a headline. The screen's only test
  // used to assert button placement, so promoting the footnote to a big accuracy %
  // would have left the suite green. This pins it.
  testWidgets('the score is a muted N/M footnote — never a % or a headline', (
    tester,
  ) async {
    final twoOfThree = QuizResult(
      answers: [
        AnsweredQuestion(question: q('あ'), selectedIndex: 0), // correct
        AnsweredQuestion(question: q('い'), selectedIndex: 1), // wrong
        AnsweredQuestion(question: q('う'), selectedIndex: 0), // correct
      ],
    );
    await pump(tester, QuizResultScreen(result: twoOfThree, onAgain: () {}));

    // No accuracy leaks anywhere on the close.
    expect(find.textContaining('%'), findsNothing);
    // The score is a raw count, and it is the muted footnote (14px, inkMuted) —
    // not a headline-sized or accent-coloured reward.
    expect(find.text('2/3'), findsOneWidget);
    final score = tester.widget<Text>(find.text('2/3'));
    expect(score.style?.fontSize, 14);
    expect(score.style?.color, AppColors.inkMuted);
  });
}
