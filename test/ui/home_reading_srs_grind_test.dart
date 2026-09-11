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
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stationId = 'phrase:えきは どこ';

DateTime _noon() => DateTime(2026, 9, 11, 12);

Future<void> _learnAll(KanaProgressRepository kana) async {
  for (final lesson in Lessons.fromKana(kana.allKana)) {
    await kana.markUnitLearned(lesson.id);
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required KanaProgressRepository kana,
  required WordProgressRepository words,
}) async {
  final kanji = await KanjiReadingRepository.load();
  await tester.binding.setSurfaceSize(const Size(420, 2600));
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
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const MaterialApp(home: HomeScreen(clock: _noon)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<String> _confirmUnprompted(WidgetTester tester) async {
  final screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
  final shown = screen.items
      .firstWhere((item) => find.text(item.displayText).evaluate().isNotEmpty)
      .progressId;
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.iReadIt));
  await tester.pumpAndSettle();
  return shown;
}

Future<void> _confirmUntilMore(WidgetTester tester) async {
  while (find.text(AppStrings.practiceAgain).evaluate().isEmpty) {
    await _confirmUnprompted(tester);
  }
}

int _dueDays(WordProgressRepository words, String id, DateTime now) {
  final due = words.statForItem(id).dueAt;
  expect(due, isNotNull);
  return due!.difference(now).inDays;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Home 讀短句 もう一回: formal More keeps [2,2] after reload',
    (tester) async {
      final now = _noon();
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      await _learnAll(kana);
      await words.introduce(_stationId, at: now);
      expect(words.statForItem(_stationId).srsLevel, 1);
      await _pumpHome(tester, kana: kana, words: words);

      await tester.ensureVisible(find.text(AppStrings.readPhrasesAction));
      await tester.tap(find.text(AppStrings.readPhrasesAction));
      await tester.pumpAndSettle();
      var screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      expect(screen.alreadyTransferredIds, isEmpty);
      expect(screen.items.length, 4);
      expect(screen.items.map((i) => i.progressId), contains(_stationId));
      final firstIds = {for (final item in screen.items) item.progressId};

      final levels = <int>[];
      await _confirmUntilMore(tester);
      levels.add(words.statForItem(_stationId).srsLevel);
      expect(find.text(AppStrings.practiceAgain), findsOneWidget);

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      expect(screen.alreadyTransferredIds, firstIds);
      expect(screen.items.length, 7);
      expect(screen.items.map((i) => i.progressId), contains(_stationId));
      await _confirmUntilMore(tester);
      levels.add(words.statForItem(_stationId).srsLevel);

      expect(levels, [2, 2]);
      expect(words.statForItem(_stationId).correctCount, 2);
      expect(_dueDays(words, _stationId, now), 3);
      await words.flushPending();
      final reloaded = await WordProgressRepository.load();
      expect(reloaded.statForItem(_stationId).srsLevel, 2);
      expect(reloaded.statForItem(_stationId).dueAt!.difference(now).inDays, 3);
    },
  );

  testWidgets('Home 讀短句もう一回: leftover new id still climbs; wrap id does not', (
    tester,
  ) async {
    final now = _noon();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await _learnAll(kana);
    await words.introduce(_stationId, at: now);
    await _pumpHome(tester, kana: kana, words: words);

    await tester.ensureVisible(find.text(AppStrings.readPhrasesAction));
    await tester.tap(find.text(AppStrings.readPhrasesAction));
    await tester.pumpAndSettle();
    await _confirmUntilMore(tester);
    expect(words.statForItem(_stationId).srsLevel, 2);

    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    final screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
    expect(screen.alreadyTransferredIds, contains(_stationId));
    final fresh = screen.items
        .where((item) => !screen.alreadyTransferredIds.contains(item.progressId))
        .toList();
    expect(fresh, isNotEmpty);

    while (find.text(AppStrings.practiceAgain).evaluate().isEmpty) {
      await _confirmUnprompted(tester);
    }
    expect(words.statForItem(_stationId).srsLevel, 2);
    for (final item in fresh) {
      expect(words.statForItem(item.progressId).srsLevel, 1);
    }
  });
}
