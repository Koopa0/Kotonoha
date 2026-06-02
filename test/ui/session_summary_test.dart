// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/koten.dart';
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

  testWidgets(
    'a classical 余韻 leads (text + gloss + attribution); score recedes',
    (tester) async {
      const share = KotenLine(
        text: '古池や蛙飛びこむ水の音',
        reading: 'ふるいけやかわずとびこむみずのおと',
        gloss: '蛙躍入古池,一聲水響。',
        attribution: '松尾芭蕉『蛙合』',
        note: '芭蕉中年所詠的名句,蛙為春之季語。',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionSummary(
              headline: AppStrings.readingSummary(3, 3),
              share: share,
              onDone: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The line is READ first (text + furigana reading + gloss + provenance).
      expect(find.text(share.text), findsOneWidget);
      expect(find.text(share.reading), findsOneWidget);
      expect(find.text(share.gloss), findsOneWidget);
      expect(find.text(share.attribution), findsOneWidget);
      // The classical line sits above the (now-muted footnote) score.
      final lineY = tester.getTopLeft(find.text(share.text)).dy;
      final scoreY = tester
          .getTopLeft(find.text(AppStrings.readingSummary(3, 3)))
          .dy;
      expect(lineY, lessThan(scoreY));

      // The 釋 note is folded away until tapped — calm by default.
      expect(find.text(share.note!), findsNothing);
      await tester.tap(find.text(AppStrings.kotenNoteTrigger));
      await tester.pumpAndSettle();
      expect(find.text(share.note!), findsOneWidget);
    },
  );
}
