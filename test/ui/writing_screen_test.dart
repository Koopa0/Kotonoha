// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/writing/writing_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget test for the paper handwriting recall flow: each item is
/// prompt → reveal → self-grade, and the session ends on a summary. Verifies
/// the View drives the repository and the analytics stream correctly.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'reveal → self-grade twice reaches the summary and records both',
    (tester) async {
      final store = await KanaProgressRepository.load();
      final analytics = InMemoryAnalyticsLog();
      final targets = kHiraganaGojuon.take(2).toList(); // あ, い

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
          child: MaterialApp(
            home: WritingScreen(
              targets: targets,
              title: AppStrings.writingTitle,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Q1: prompt is the romaji, answer hidden until revealed.
      expect(find.text('a'), findsOneWidget);
      expect(find.text(AppStrings.writePrompt), findsOneWidget);
      expect(find.text('あ'), findsNothing);

      await tester.tap(find.text(AppStrings.revealAnswer));
      await tester.pumpAndSettle();
      expect(find.text('あ'), findsOneWidget); // glyph now shown
      await tester.tap(find.text(AppStrings.iGotIt)); // grade correct
      await tester.pumpAndSettle();

      // Q2.
      expect(find.text('i'), findsOneWidget);
      await tester.tap(find.text(AppStrings.revealAnswer));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iMissed)); // grade wrong
      await tester.pumpAndSettle();

      // Summary: 1 of 2.
      expect(find.text(AppStrings.writingSummary(1, 2)), findsOneWidget);
      expect(find.text(AppStrings.done), findsOneWidget);

      // Both answers persisted to stats and to the analytics stream as writing.
      expect(store.statFor(targets[0]).correctCount, 1);
      expect(store.statFor(targets[1]).wrongCount, 1);
      final logged = await analytics.all();
      expect(logged.length, 2);
      expect(logged.every((a) => a.mode == PracticeMode.writing.name), isTrue);
    },
  );
}
