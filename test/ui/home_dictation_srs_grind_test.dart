// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

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
        Provider<SpeechService>.value(
          value: ScriptedSpeechService(const [SpeechPlaybackResult.played]),
        ),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: MaterialApp(home: HomeScreen(clock: _noon)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<String> _assembleCurrent(WidgetTester tester) async {
  final speak = tester.widget<SpeakButton>(
    find.byKey(const ValueKey<String>('dictation-replay')),
  );
  for (final unit in KanaTokenizer.tokenize(speak.text)) {
    await tester.tap(find.text(unit).first);
    await tester.pumpAndSettle();
  }
  expect(find.text(AppStrings.dictationNext), findsOneWidget);
  await tester.tap(find.text(AppStrings.dictationNext));
  await tester.pumpAndSettle();
  return speak.text;
}

int _dueDays(WordProgressRepository words, String id, DateTime now) {
  final due = words.statForItem(id).dueAt;
  expect(due, isNotNull);
  return due!.difference(now).inDays;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Home 聽寫單字 もう一回: three formal rounds stay [2,2,2] after reload', (
    tester,
  ) async {
    final now = _noon();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await _learnAll(kana);
    await words.introduce('word:えき', at: now);
    expect(words.statForItem('word:えき').srsLevel, 1);
    await _pumpHome(tester, kana: kana, words: words);

    await tester.ensureVisible(find.text(AppStrings.dictationAction));
    await tester.tap(find.text(AppStrings.dictationAction));
    await tester.pumpAndSettle();
    var screen = tester.widget<DictationScreen>(find.byType(DictationScreen));
    expect(screen.alreadyTransferredIds, isEmpty);
    expect(screen.words.map((w) => w.progressId), ['word:えき']);

    final levels = <int>[];
    await _assembleCurrent(tester);
    levels.add(words.statForItem('word:えき').srsLevel);
    expect(find.text(AppStrings.practiceAgain), findsOneWidget);

    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    screen = tester.widget<DictationScreen>(find.byType(DictationScreen));
    expect(screen.alreadyTransferredIds, contains('word:えき'));
    expect(screen.words.map((w) => w.progressId), ['word:えき']);
    await _assembleCurrent(tester);
    levels.add(words.statForItem('word:えき').srsLevel);

    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    screen = tester.widget<DictationScreen>(find.byType(DictationScreen));
    expect(screen.alreadyTransferredIds, contains('word:えき'));
    await _assembleCurrent(tester);
    levels.add(words.statForItem('word:えき').srsLevel);

    expect(levels, [2, 2, 2]);
    expect(_dueDays(words, 'word:えき', now), 3);
    await words.flushPending();
    final reloaded = await WordProgressRepository.load();
    expect(reloaded.statForItem('word:えき').srsLevel, 2);
    expect(reloaded.statForItem('word:えき').dueAt!.difference(now).inDays, 3);
  });

  testWidgets('Home 聽寫もう一回: leftover new id still climbs; wrap id does not', (
    tester,
  ) async {
    final now = _noon();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await _learnAll(kana);
    await words.introduce('word:えき', at: now);
    await _pumpHome(tester, kana: kana, words: words);

    await tester.ensureVisible(find.text(AppStrings.dictationAction));
    await tester.tap(find.text(AppStrings.dictationAction));
    await tester.pumpAndSettle();
    await _assembleCurrent(tester);
    expect(words.statForItem('word:えき').srsLevel, 2);

    await words.introduce('word:ここ', at: now);
    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    final screen = tester.widget<DictationScreen>(find.byType(DictationScreen));
    expect(screen.alreadyTransferredIds, contains('word:えき'));
    expect(screen.alreadyTransferredIds.contains('word:ここ'), isFalse);
    expect(
      screen.words.map((w) => w.progressId).toSet(),
      containsAll({'word:えき', 'word:ここ'}),
    );

    while (find.text(AppStrings.practiceAgain).evaluate().isEmpty) {
      await _assembleCurrent(tester);
    }
    expect(words.statForItem('word:えき').srsLevel, 2);
    expect(words.statForItem('word:ここ').srsLevel, 2);
  });
}
