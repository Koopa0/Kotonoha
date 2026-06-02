// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real app (with seeded progress, so screens are populated) to each
/// key screen and captures a screenshot. Not a test of behaviour — a capture
/// run for the README. Produces `screenshots/01-home` … `04-progress`.
///
/// ```sh
/// flutter drive --driver=test_driver/screenshot.dart \
///   --target=integration_test/screenshot_capture.dart -d emulator-5554
/// ```
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture product screenshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    SharedPreferences.setMockInitialValues({});
    final store = await KanaProgressRepository.load();
    // Learn all hiragana and record a spread of answers, so every track (words,
    // phrases, kanji, confusable, insights) is unlocked and populated.
    for (final l in Lessons.fromKana(store.allKana)) {
      if (l.script == KanaScript.hiragana) await store.markUnitLearned(l.id);
    }
    final learned = StudySet.learned(store);
    for (var i = 0; i < learned.length; i++) {
      await store.recordAnswer(
        learned[i],
        correct: i % 5 != 0,
        at: DateTime(2026, 6),
        latencyMs: 250 + i * 20,
      );
    }

    final kanji = await KanjiReadingRepository.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const KanaLoopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    // Pop the top route via the root navigator (robust — no back-button finder).
    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }

    await shot('01-home');

    // The Ferry — the binding beat: kana inked in over the (still) audio.
    await tester.tap(find.text(AppStrings.ferryEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    await shot('08-ferry');
    await back();

    // Dictation — hear the word, then assemble it from the kana tile board.
    await tester.tap(find.text(AppStrings.dictationEntry));
    await tester.pumpAndSettle();
    await shot('03-dictation');
    await back();

    // A question inside today's adaptive session (the primary CTA, near the top).
    await tester.tap(find.text(AppStrings.dailySession));
    await shot('02-session');
    await back();

    // Progress — below the fold, so scroll it into view first (last, so the
    // scroll offset doesn't disturb the earlier taps).
    await tester.scrollUntilVisible(
      find.text(AppStrings.progress),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.progress));
    await shot('04-progress');
    await back();

    // Kanji reading — scroll to the tile, enter; a never-seen reading is taught
    // ear-first, so the reading + meaning are shown without any reveal tap.
    await tester.scrollUntilVisible(
      find.text(AppStrings.kanjiEntry),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.kanjiEntry));
    await tester.pumpAndSettle();
    await shot('05-kanji');
    await back();

    // Sentence reading — a themed mini-phrase, revealed.
    await tester.scrollUntilVisible(
      find.text(AppStrings.sentenceEntry),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.sentenceEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.revealAnswer));
    await shot('06-sentence');
    await back();

    // Kanji sentence — the furigana-fade prompt (furigana visible, unmastered).
    await tester.scrollUntilVisible(
      find.text(AppStrings.kanjiSentenceEntry),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.kanjiSentenceEntry));
    await tester.pumpAndSettle();
    await shot('07-kanji-sentence');
  });
}
