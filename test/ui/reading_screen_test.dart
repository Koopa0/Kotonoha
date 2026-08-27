// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget test for contextual reading: kana shown, reveal exposes romaji +
/// meaning, self-grade advances, and each answer is logged as a word-level
/// reading Attempt (and NOT as a kana stat).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reveal → self-grade twice reaches summary and logs words', (
    tester,
  ) async {
    // A fresh store (seenCount 0) keeps the occasional 凪 余韻 out of this flow
    // test — the classical-line gate is covered in session_summary_test.
    final store = await KanaProgressRepository.load();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: store.flushPending,
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    final analytics = InMemoryAnalyticsLog();
    const words = [
      Word(kana: 'いぬ', romaji: 'inu', meaning: '狗'),
      Word(kana: 'やま', romaji: 'yama', meaning: '山'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persistence,
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: ReadingScreen(items: words, title: AppStrings.sentenceTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Q1: the word shows; romaji/meaning hidden until revealed.
    expect(find.text('いぬ'), findsOneWidget);
    expect(find.text(AppStrings.readPrompt), findsOneWidget);
    expect(find.text('inu'), findsNothing);

    await tester.tap(find.text(AppStrings.revealAnswer));
    await tester.pumpAndSettle();
    expect(find.text('inu'), findsOneWidget);
    expect(find.text('狗'), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();

    // Q2.
    expect(find.text('やま'), findsOneWidget);
    await tester.tap(find.text(AppStrings.revealAnswer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iCouldnt));
    await tester.pumpAndSettle();

    // Summary 1/2.
    expect(find.text(AppStrings.readingSummary(1, 2)), findsOneWidget);

    final logged = await analytics.all();
    expect(logged.length, 2);
    expect(logged.every((a) => a.mode == PracticeMode.reading.name), isTrue);
    expect(logged.every((a) => a.itemType == ItemType.word), isTrue);
    expect(logged.first.itemId, 'いぬ');
  });
}
