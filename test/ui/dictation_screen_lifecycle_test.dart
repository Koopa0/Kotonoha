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
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

const _kimi = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');
const _ame = Word(kana: 'あめ', romaji: 'ame', meaning: '雨');

void pauseApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void resumeApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> assembleKimi(WidgetTester tester) async {
  await tester.tap(find.text('き'));
  await tester.pump();
  await tester.tap(find.text('み'));
  await tester.pump();
}

Future<void> assembleAme(WidgetTester tester) async {
  await tester.tap(find.text('あ'));
  await tester.pump();
  await tester.tap(find.text('め'));
  await tester.pump();
}

Future<void> pumpDictationLifecycle(
  WidgetTester tester, {
  required SpeechService speech,
  required InMemoryAnalyticsLog analytics,
  required WordProgressRepository words,
  required DateTime Function() clock,
  required int Function() elapsed,
  List<Word> items = const [_kimi],
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(
          value: await KanaProgressRepository.load(),
        ),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: () async {},
            kanjiFlush: () async {},
            wordFlush: words.flushPending,
          ),
        ),
        Provider<AnalyticsLog>.value(value: analytics),
        Provider<SpeechService>.value(value: speech),
      ],
      child: MaterialApp(
        home: DictationScreen(
          words: items,
          title: AppStrings.dictationTitle,
          clock: clock,
          monotonicMs: elapsed,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('uninterrupted 1200ms through DictationScreen stays timed', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    await pumpDictationLifecycle(
      tester,
      speech: ScriptedSpeechService(const [SpeechPlaybackResult.played]),
      analytics: analytics,
      words: words,
      clock: () => now,
      elapsed: () => elapsed,
    );

    elapsed = 1200;
    now = now.add(const Duration(milliseconds: 1200));
    await assembleKimi(tester);

    final logged = await analytics.all();
    expect(logged.single.rtMs, 1200);
    expect(logged.single.correct, isTrue);
    expect(logged.single.meta[AttemptMeta.heard], isTrue);
    expect(logged.single.meta[AttemptMeta.scored], isTrue);
    expect(logged.single.meta[AttemptMeta.prompted], isFalse);
    expect(words.statForItem('word:きみ').srsLevel, 1);
  });

  testWidgets('10-minute background after hear does not pollute dictation RT', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    await pumpDictationLifecycle(
      tester,
      speech: ScriptedSpeechService(const [SpeechPlaybackResult.played]),
      analytics: analytics,
      words: words,
      clock: () => now,
      elapsed: () => elapsed,
    );

    pauseApp(tester);
    await tester.pump();
    now = now.add(const Duration(minutes: 10, milliseconds: 1200));
    elapsed = 601200;
    resumeApp(tester);
    await tester.pump();
    await assembleKimi(tester);

    final logged = await analytics.all();
    expect(logged.single.rtMs, 0);
    expect(logged.single.correct, isTrue);
    expect(logged.single.meta[AttemptMeta.heard], isTrue);
    expect(logged.single.meta[AttemptMeta.scored], isTrue);
    expect(logged.single.meta[AttemptMeta.prompted], isFalse);
    expect(words.statForItem('word:きみ').srsLevel, 1);
  });

  testWidgets('interrupt before first play then replay stays untimed', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final speech = ControllableSpeechService();
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    await pumpDictationLifecycle(
      tester,
      speech: speech,
      analytics: analytics,
      words: words,
      clock: () => now,
      elapsed: () => elapsed,
    );
    expect(speech.isPending, isTrue);

    pauseApp(tester);
    await tester.pump();
    resumeApp(tester);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('dictation-replay')));
    await tester.pump();
    speech.complete(SpeechPlaybackResult.played);
    await tester.pump();
    elapsed = 1200;
    now = now.add(const Duration(milliseconds: 1200));
    await assembleKimi(tester);

    final logged = await analytics.all();
    expect(logged.single.rtMs, 0);
    expect(logged.single.meta[AttemptMeta.heard], isTrue);
    expect(logged.single.meta[AttemptMeta.scored], isTrue);
    expect(words.statForItem('word:きみ').srsLevel, 1);
  });

  testWidgets('interrupt during play then replay stays untimed', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final speech = ControllableSpeechService();
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    await pumpDictationLifecycle(
      tester,
      speech: speech,
      analytics: analytics,
      words: words,
      clock: () => now,
      elapsed: () => elapsed,
    );
    elapsed = 200;
    now = now.add(const Duration(milliseconds: 200));
    expect(speech.isPending, isTrue);

    pauseApp(tester);
    await tester.pump();
    resumeApp(tester);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('dictation-replay')));
    await tester.pump();
    speech.complete(SpeechPlaybackResult.played);
    await tester.pump();
    elapsed = 800;
    now = now.add(const Duration(milliseconds: 600));
    await assembleKimi(tester);

    expect((await analytics.all()).single.rtMs, 0);
    expect((await analytics.all()).single.meta[AttemptMeta.heard], isTrue);
  });

  testWidgets('same-item replay after hear+interrupt cannot wash a valid RT', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final speech = ScriptedSpeechService(const [
      SpeechPlaybackResult.played,
      SpeechPlaybackResult.played,
    ]);
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    await pumpDictationLifecycle(
      tester,
      speech: speech,
      analytics: analytics,
      words: words,
      clock: () => now,
      elapsed: () => elapsed,
    );

    pauseApp(tester);
    await tester.pump();
    resumeApp(tester);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('dictation-replay')));
    await tester.pump();
    elapsed = 500;
    now = now.add(const Duration(milliseconds: 500));
    await assembleKimi(tester);

    expect((await analytics.all()).single.rtMs, 0);
    expect((await analytics.all()).single.meta[AttemptMeta.heard], isTrue);
  });

  testWidgets(
    'resume does not restart an interrupted item; the next word times',
    (tester) async {
      addTearDown(() => resumeApp(tester));
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      var now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      await pumpDictationLifecycle(
        tester,
        speech: ScriptedSpeechService(const [
          SpeechPlaybackResult.played,
          SpeechPlaybackResult.played,
        ]),
        analytics: analytics,
        words: words,
        clock: () => now,
        elapsed: () => elapsed,
        items: const [_kimi, _ame],
      );

      pauseApp(tester);
      await tester.pump();
      resumeApp(tester);
      await tester.pump();
      elapsed = 500;
      now = now.add(const Duration(milliseconds: 500));
      await assembleKimi(tester);
      expect((await analytics.all()).single.rtMs, 0);
      expect(words.statForItem('word:きみ').srsLevel, 1);

      await tester.tap(find.text(AppStrings.dictationNext));
      await tester.pump();
      await tester.pump();
      elapsed = 1000;
      now = now.add(const Duration(milliseconds: 500));
      await assembleAme(tester);

      final logged = await analytics.all();
      expect(logged.map((a) => a.rtMs), [0, 500]);
      expect(logged.every((a) => a.meta[AttemptMeta.heard] == true), isTrue);
      expect(logged.every((a) => a.meta[AttemptMeta.scored] == true), isTrue);
      expect(words.statForItem('word:あめ').srsLevel, 1);
    },
  );
}
