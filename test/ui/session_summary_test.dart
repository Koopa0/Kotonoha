// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';

/// The 凪 close: 完成 is the primary action; the opt-in もう一回 appears only when
/// an onMore is given (home suppresses it at night) and sits BELOW 完成, low-emphasis.
void main() {
  testWidgets('もう一回 shows, muted and below 完成, only when onMore is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSummary(
            headline: AppStrings.readingSummary(2, 3),
            note: '雪,還在落著。今天就到這裡,好好休息。',
            onDone: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextButton, AppStrings.practiceAgain),
      findsOneWidget,
    );
    // 完成 leads (the primary FilledButton); もう一回 sits below it.
    final doneY = tester.getTopLeft(find.text(AppStrings.done)).dy;
    final moreY = tester.getTopLeft(find.text(AppStrings.practiceAgain)).dy;
    expect(doneY, lessThan(moreY));
  });

  testWidgets('もう一回 is hidden when onMore is null (e.g. at night)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSummary(headline: 'x', note: 'y', onDone: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.practiceAgain), findsNothing);
    expect(find.text(AppStrings.done), findsOneWidget);
  });
}
