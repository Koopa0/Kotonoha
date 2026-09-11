// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

Future<({KanaProgressRepository kana, WordProgressRepository words})>
_loadRepos() async {
  final kana = await KanaProgressRepository.load();
  final words = await WordProgressRepository.load();
  return (kana: kana, words: words);
}

Future<void> _learnAll(KanaProgressRepository kana) async {
  for (final lesson in Lessons.fromKana(kana.allKana)) {
    await kana.markUnitLearned(lesson.id);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required KanaProgressRepository kana,
  required WordProgressRepository words,
  required Widget home,
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
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _gradeHeard(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
  await tester.pump();
  await tester.tap(find.text(AppStrings.listeningHeard));
  await tester.pump();
  await tester.pump();
}

Future<void> _gradeHeardExpecting(
  WidgetTester tester,
  WordProgressRepository words,
  Set<String> already,
) async {
  await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
  await tester.pump();
  final kana = tester
      .widget<Text>(find.byKey(const ValueKey<String>('listening-answer')))
      .data!;
  final id = kana.contains(' ') ? 'phrase:$kana' : 'word:$kana';
  final before = words.statForItem(id).srsLevel;
  await tester.tap(find.text(AppStrings.listeningHeard));
  await tester.pump();
  await tester.pump();
  if (already.contains(id)) {
    expect(words.statForItem(id).srsLevel, before);
  } else {
    expect(words.statForItem(id).srsLevel, before + 1);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    '聞き取り もう一回: first blind climb, wrap same id does not, new id still does',
    (tester) async {
      final now = DateTime(2026, 9, 10, 12);
      final repos = await _loadRepos();
      await _learnAll(repos.kana);
      await repos.words.markIntroduced('word:えき', at: now);
      await _pump(
        tester,
        kana: repos.kana,
        words: repos.words,
        home: HomeScreen(clock: () => now),
      );

      await tester.ensureVisible(find.text(AppStrings.listenFirstAction));
      await tester.tap(find.text(AppStrings.listenFirstAction));
      await tester.pumpAndSettle();
      var screen = tester.widget<ListeningScreen>(find.byType(ListeningScreen));
      expect(screen.alreadyTransferredIds, isEmpty);
      expect(screen.items.map((i) => i.progressId), contains('word:えき'));
      expect(screen.onMore, isNotNull);

      await _gradeHeard(tester);
      expect(repos.words.statForItem('word:えき').srsLevel, 1);

      await repos.words.markIntroduced('word:ここ', at: now);
      screen.onMore!();
      await tester.pumpAndSettle();
      screen = tester.widget<ListeningScreen>(find.byType(ListeningScreen));
      expect(screen.alreadyTransferredIds, contains('word:えき'));
      final already = screen.alreadyTransferredIds;

      while (find.text(AppStrings.listeningReveal).evaluate().isNotEmpty) {
        await _gradeHeardExpecting(tester, repos.words, already);
      }
      expect(repos.words.statForItem('word:えき').srsLevel, 1);
      expect(repos.words.statForItem('word:ここ').srsLevel, 1);
    },
  );

  testWidgets(
    '旅遊聽力 もう一回: first blind climb, wrap same id does not, leftover id still does',
    (tester) async {
      final now = DateTime(2026, 9, 10, 12);
      final repos = await _loadRepos();
      await repos.kana.markUnitLearned('hira_row_0');
      await repos.kana.markUnitLearned('hira_row_1');
      await repos.words.markIntroduced('word:えき', at: now);
      await _pump(
        tester,
        kana: repos.kana,
        words: repos.words,
        home: TravelSceneHub(scene: TravelSceneId.transport, clock: () => now),
      );

      await tester.tap(find.text(AppStrings.travelSceneListenAction));
      await tester.pumpAndSettle();
      var screen = tester.widget<ListeningScreen>(find.byType(ListeningScreen));
      expect(screen.alreadyTransferredIds, isEmpty);
      expect(screen.items.map((i) => i.progressId), contains('word:えき'));
      expect(screen.onMore, isNotNull);

      await _gradeHeard(tester);
      expect(repos.words.statForItem('word:えき').srsLevel, 1);

      await repos.words.markIntroduced('word:ここ', at: now);
      screen.onMore!();
      await tester.pumpAndSettle();
      screen = tester.widget<ListeningScreen>(find.byType(ListeningScreen));
      expect(screen.alreadyTransferredIds, contains('word:えき'));
      expect(screen.alreadyTransferredIds.contains('word:ここ'), isFalse);

      await _gradeHeard(tester);
      expect(repos.words.statForItem('word:えき').srsLevel, 1);
      expect(repos.words.statForItem('word:ここ').srsLevel, 1);
    },
  );
}
