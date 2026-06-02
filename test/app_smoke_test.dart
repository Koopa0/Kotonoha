// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpApp(WidgetTester tester, {bool seedLearned = false}) async {
  // Use a phone-sized surface so lazily-built list items are all present.
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final store = await KanaProgressRepository.load();
  if (seedLearned) {
    // Learn あ行 so review entries (gated on learnedUnitCount) appear.
    await store.markUnitLearned('hira_row_0');
    for (final k in store.gojuonForScript(KanaScript.hiragana).take(5)) {
      await store.recordAnswer(
        k,
        correct: true,
        at: DateTime(2026),
        latencyMs: 300,
      );
    }
  }
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home shows the primary actions', (tester) async {
    await pumpApp(tester);
    expect(find.text(AppStrings.appTitle), findsOneWidget);
    // Cold start: primary CTA is "start learning"; review entries are gated.
    expect(find.text(AppStrings.continueLearning), findsOneWidget);
    expect(find.text(AppStrings.learnHiragana), findsOneWidget);
    expect(find.text(AppStrings.progress), findsOneWidget);
    expect(find.text('0/92'), findsOneWidget); // ring tracks the 92 gojūon
    // The confusable drill and paper handwriting are both gated until at least
    // one lesson is learned (feature honesty: nothing to recall yet).
    expect(find.text(AppStrings.confusableEntry), findsNothing);
    expect(find.text(AppStrings.writingEntry), findsNothing);
  });

  testWidgets('confusable drill launches once a lesson is learned', (
    tester,
  ) async {
    await pumpApp(tester, seedLearned: true);

    await tester.tap(find.text(AppStrings.confusableEntry));
    await tester.pumpAndSettle();

    expect(find.textContaining(' / '), findsOneWidget); // quiz progress
    expect(find.textContaining('選擇'), findsOneWidget);
  });

  testWidgets('lesson flow: open a row, study it, reach its test', (
    tester,
  ) async {
    await pumpApp(tester);

    // Home → 手解き (the sequential-learning path)
    await tester.tap(find.text(AppStrings.continueLearning));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.lessonsTitle), findsOneWidget);

    // Open あ行 → study screen, first card あ / a
    await tester.tap(find.text('あ行'));
    await tester.pumpAndSettle();
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);

    // Advance through all 5 cards, then the button becomes the lesson test.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(AppStrings.nextCard));
      await tester.pumpAndSettle();
    }
    expect(find.text(AppStrings.testThisRow), findsOneWidget);

    // Enter the lesson test — AppBar shows the row title.
    await tester.tap(find.text(AppStrings.testThisRow));
    await tester.pumpAndSettle();
    expect(find.text('あ行'), findsOneWidget);
    expect(find.textContaining('選擇'), findsOneWidget);
  });

  testWidgets('handwriting recall: prompt → reveal → self-grade', (
    tester,
  ) async {
    // 手習い is gated on a learned lesson, so seed one (the review pool is then
    // kana the learner actually knows).
    await pumpApp(tester, seedLearned: true);
    await tester.tap(find.text(AppStrings.writingEntry));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.writePrompt), findsOneWidget);
    expect(find.text(AppStrings.revealAnswer), findsOneWidget);

    await tester.tap(find.text(AppStrings.revealAnswer));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iGotIt), findsOneWidget);
    expect(find.text(AppStrings.iMissed), findsOneWidget);
  });

  testWidgets('adaptive daily session launches from the primary CTA', (
    tester,
  ) async {
    await pumpApp(tester, seedLearned: true);
    await tester.tap(find.text(AppStrings.dailySession));
    await tester.pumpAndSettle();
    // A quiz question is showing (progress "N / M").
    expect(find.textContaining(' / '), findsOneWidget);
  });

  testWidgets('unlock line: shows for a new capability, then 知道了 clears it', (
    tester,
  ) async {
    // Learning あ行 makes words like あい/あお readable → the 詞と句 track opens.
    await pumpApp(tester, seedLearned: true);
    // The unlock line takes the slot, replacing the steady-state next-step line.
    expect(find.text(AppStrings.unlockWords), findsOneWidget);
    expect(find.textContaining('該複習'), findsNothing);

    // 知道了 marks it seen → it never returns; the next-step line resumes.
    await tester.tap(find.text(AppStrings.unlockDismiss));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.unlockWords), findsNothing);
    expect(find.textContaining('該複習'), findsOneWidget);
  });

  testWidgets('これは?: orientation reveals on demand and folds away', (
    tester,
  ) async {
    await pumpApp(tester); // cold start — it must be there with the least app
    expect(find.text(AppStrings.aboutTrigger), findsOneWidget);
    expect(find.text(AppStrings.aboutBody), findsNothing); // pull, not pushed
    expect(find.byType(Dialog), findsNothing); // never modal

    await tester.tap(find.text(AppStrings.aboutTrigger));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.aboutBody), findsOneWidget);

    await tester.tap(find.text(AppStrings.aboutTrigger));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.aboutBody), findsNothing); // self-dismisses
  });

  testWidgets('learn screen renders the gojūon grid', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text(AppStrings.learnHiragana));
    await tester.pumpAndSettle();
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('ん'), findsOneWidget);
    expect(find.text(AppStrings.statusStrong), findsOneWidget);
  });
}
