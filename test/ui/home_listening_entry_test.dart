// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(
    WidgetTester tester, {
    required KanaProgressRepository kana,
    required WordProgressRepository words,
  }) async {
    final kanji = await KanjiReadingRepository.load();
    final recovery = await idleRestoreRecovery();
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('聞き取り stays hidden until a T01 item has been met', (
    tester,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
    await pumpHome(tester, kana: kana, words: words);
    expect(find.text(AppStrings.listenFirstAction), findsNothing);
    expect(find.text(AppStrings.listeningEntry), findsNothing);
    expect(find.text(AppStrings.dictationAction), findsNothing);
  });

  testWidgets(
    '聞き取り opens after a T01 word is met, without renaming neighbours',
    (tester) async {
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      for (final lesson in Lessons.fromKana(kana.allKana)) {
        await kana.markUnitLearned(lesson.id);
      }
      await words.introduce('word:えき', at: DateTime(2026, 9, 10, 12));
      await pumpHome(tester, kana: kana, words: words);

      expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
      expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
      expect(find.text(AppStrings.listenFirstAction), findsOneWidget);
      expect(find.text(AppStrings.listeningEntry), findsOneWidget);
      expect(find.text(AppStrings.listeningSubtitle), findsOneWidget);
      expect(find.text(AppStrings.meetWordsAction), findsOneWidget);
      expect(find.text(AppStrings.ferryEntry), findsOneWidget);
      expect(find.text(AppStrings.dictationAction), findsOneWidget);
      expect(find.text(AppStrings.dictationEntry), findsOneWidget);
      expect(find.text(AppStrings.readPhrasesAction), findsOneWidget);
      expect(find.text(AppStrings.sentenceEntry), findsOneWidget);
    },
  );
}
