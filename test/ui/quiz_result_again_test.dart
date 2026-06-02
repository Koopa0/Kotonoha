// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';

void main() {
  // An empty answer list is a finished session with nothing missed — a "perfect"
  // result — enough to exercise the action set without composing questions.
  const perfect = QuizResult(answers: []);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: child));
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
}
