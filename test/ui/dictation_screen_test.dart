// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

Finder dictationSlot(int index) =>
    find.byKey(ValueKey<String>('dictation-slot-$index'));

List<Word> longestCorpusWords() {
  var longest = 0;
  final words = <Word>[];
  for (final word in kWords) {
    final n = KanaTokenizer.tokenize(word.kana).length;
    if (n > longest) {
      longest = n;
      words
        ..clear()
        ..add(word);
    } else if (n == longest) {
      words.add(word);
    }
  }
  return words;
}

Future<void> pumpDictation(
  WidgetTester tester, {
  required List<Word> words,
  Size size = const Size(360, 800),
  double textScale = 1,
  InMemoryAnalyticsLog? analytics,
  WordProgressRepository? wordRepo,
  ProgressPersistenceController? persistence,
  SpeechService speech = const SilentSpeechService(),
  KanaProgressRepository? kanaRepo,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final resolvedWordRepo = wordRepo ?? await WordProgressRepository.load();
  final resolvedPersistence =
      persistence ??
      ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: resolvedWordRepo.flushPending,
      );
  final resolvedAnalytics = analytics ?? InMemoryAnalyticsLog();
  final resolvedKana = kanaRepo ?? await KanaProgressRepository.load();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(
          value: resolvedKana,
        ),
        ChangeNotifierProvider<WordProgressRepository>.value(
          value: resolvedWordRepo,
        ),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: resolvedPersistence,
        ),
        Provider<AnalyticsLog>.value(value: resolvedAnalytics),
        Provider<SpeechService>.value(value: speech),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: DictationScreen(
              words: words,
              title: AppStrings.dictationTitle,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

void expectSlotsReadable(WidgetTester tester, int count) {
  expect(count, greaterThan(0));
  final sizes = [
    for (var i = 0; i < count; i++) tester.getSize(dictationSlot(i)),
  ];
  expect(sizes, hasLength(count));
  expect(
    {for (final size in sizes) '${size.width}x${size.height}'},
    hasLength(1),
    reason: 'empty and filled slots must share one box — no answer leak',
  );
  expect(sizes.first.width, greaterThanOrEqualTo(48));
  expect(sizes.first.height, greaterThanOrEqualTo(48));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hear → assemble the kana → logs a dictation attempt', (
    tester,
  ) async {
    // Fresh store (seenCount 0) keeps the occasional 凪 余韻 out of this flow test.
    final store = await KanaProgressRepository.load();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: store.flushPending,
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    final analytics = InMemoryAnalyticsLog();
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

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
          home: DictationScreen(words: words, title: AppStrings.dictationTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the き then み tiles (distractors never include the word's own kana).
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('み'));
    await tester.pumpAndSettle();

    // Auto-checked at full length → result + next. Silent play is not
    // listening evidence: assembly can be right, SRS must stay 0.
    expect(find.text(AppStrings.dictationNext), findsOneWidget);
    final logged = await analytics.all();
    expect(logged.single.mode, PracticeMode.dictation.name);
    expect(logged.single.correct, isTrue);
    expect(logged.single.itemId, 'きみ');
    expect(logged.single.meta[AttemptMeta.heard], isFalse);
    expect(logged.single.meta[AttemptMeta.scored], isFalse);
    expect(logged.single.meta[AttemptMeta.prompted], isFalse);
    await wordRepo.flushPending();
    expect(
      (await WordProgressRepository.load()).statForItem('word:きみ').srsLevel,
      0,
    );
    expect(wordRepo.statForItem('word:きみ').isSeen, isFalse);

    await tester.tap(find.text(AppStrings.dictationNext));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);
  });

  testWidgets('wrong assembly is graded incorrect and reveals the answer', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: () async {},
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persistence,
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: DictationScreen(words: words, title: AppStrings.dictationTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Assemble in the wrong order: み then き → みき ≠ きみ.
    await tester.tap(find.text('み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();

    // Graded incorrect; the correct answer's kana + romaji + meaning is revealed.
    expect((await analytics.all()).single.correct, isFalse);
    expect(find.text('きみ'), findsOneWidget);
    expect(find.text('kimi'), findsOneWidget);
    expect(find.text('你'), findsOneWidget);
    expect(find.text(AppStrings.dictationNext), findsOneWidget);
  });

  testWidgets('rtMs times the assembly from the injected clock', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: () async {},
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    var now = DateTime(2026, 6);
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persistence,
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: MaterialApp(
          home: DictationScreen(
            words: words,
            title: AppStrings.dictationTitle,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    now = now.add(const Duration(milliseconds: 1200)); // time spent assembling
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('み'));
    await tester.pumpAndSettle();

    expect((await analytics.all()).single.rtMs, 1200);
  });

  group('long corpus words fit mobile widths', () {
    // Fails on main 85af055: ゆうびんきょく is 6 units × (52+10) = 372, so a
    // 360-wide Row overflows by 12px. After the wrap/scroll fix the same
    // production screen must stay exception-free at the acceptance sizes.
    const postal = Word(kana: 'ゆうびんきょく', romaji: 'yuubinkyoku', meaning: '郵局');

    testWidgets('ゆうびんきょく does not overflow at 360 logical px', (tester) async {
      final tokens = KanaTokenizer.tokenize(postal.kana);
      expect(tokens, ['ゆ', 'う', 'び', 'ん', 'きょ', 'く']);

      await pumpDictation(tester, words: const [postal]);
      expectNoOverflow(tester);
      expectSlotsReadable(tester, tokens.length);
      expect(find.text('ゆうびんきょく'), findsNothing);
      expect(find.text('yuubinkyoku'), findsNothing);
      expect(find.text('郵局'), findsNothing);
      expect(find.text('きょ'), findsOneWidget);
    });

    testWidgets('longest existing token sequences stay inside the viewport', (
      tester,
    ) async {
      expect(kWords.any((w) => w.kana == postal.kana), isTrue);
      final longWords = {
        ...longestCorpusWords(),
        ...kWords.where((w) => KanaTokenizer.tokenize(w.kana).length >= 5),
      }.toList();
      expect(longWords, isNotEmpty);
      expect(longWords.any((w) => w.kana == postal.kana), isTrue);

      const viewports = <Size>[
        Size(320, 800),
        Size(360, 800),
        Size(390, 800),
        Size(360, 560),
        Size(320, 480),
      ];
      for (final word in longWords) {
        final tokens = KanaTokenizer.tokenize(word.kana);
        for (final size in viewports) {
          await pumpDictation(tester, words: [word], size: size);
          expectNoOverflow(tester);
          expectSlotsReadable(tester, tokens.length);
          expect(find.text(word.kana), findsNothing);
        }
      }
    });

    testWidgets('2× text scale still fits and keeps chrome reachable', (
      tester,
    ) async {
      const next = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');
      await pumpDictation(
        tester,
        words: const [postal, next],
        size: const Size(360, 560),
        textScale: 2,
      );
      expectNoOverflow(tester);
      expectSlotsReadable(tester, 6);

      await tester.ensureVisible(find.text(AppStrings.dictationClear));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.dictationClear).hitTestable(),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });

    testWidgets('assemble → clear → miss reveal → next keeps order', (
      tester,
    ) async {
      const next = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');
      final analytics = InMemoryAnalyticsLog();
      await pumpDictation(
        tester,
        words: const [postal, next],
        analytics: analytics,
      );

      final tokens = KanaTokenizer.tokenize(postal.kana);
      expect(find.text(postal.kana), findsNothing);

      await tester.tap(find.text(tokens.first));
      await tester.pumpAndSettle();
      expectSlotsReadable(tester, tokens.length);
      expect(find.text(postal.kana), findsNothing);

      await tester.ensureVisible(find.text(AppStrings.dictationClear));
      await tester.tap(find.text(AppStrings.dictationClear));
      await tester.pumpAndSettle();
      expect(find.text(tokens.first), findsOneWidget);

      for (final token in tokens.reversed) {
        await tester.tap(find.text(token));
        await tester.pumpAndSettle();
      }
      expect((await analytics.all()).single.correct, isFalse);
      expect(find.text(postal.kana), findsOneWidget);
      expect(find.text(postal.romaji), findsOneWidget);
      expect(find.text(postal.meaning), findsOneWidget);
      expectNoOverflow(tester);

      await tester.ensureVisible(find.text(AppStrings.dictationNext));
      await tester.tap(find.text(AppStrings.dictationNext));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.itemProgress(2, 2)), findsOneWidget);
      expect(find.text(next.kana), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('repeated kana do not change slot size after a fill', (
      tester,
    ) async {
      const warm = Word(kana: 'あたたかい', romaji: 'atatakai', meaning: '溫暖');
      final tokens = KanaTokenizer.tokenize(warm.kana);
      expect(tokens.where((t) => t == 'た').length, 2);

      await pumpDictation(
        tester,
        words: const [warm],
        size: const Size(320, 800),
      );
      final empty = tester.getSize(dictationSlot(0));
      await tester.tap(find.text('あ'));
      await tester.pumpAndSettle();
      expect(tester.getSize(dictationSlot(0)), empty);
      expect(tester.getSize(dictationSlot(1)), empty);
      expectNoOverflow(tester);
      expect(find.text(warm.kana), findsNothing);
    });
  });

  group('audio evidence', () {
    Future<void> assembleKimi(WidgetTester tester) async {
      await tester.tap(find.text('き'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('み'));
      await tester.pumpAndSettle();
    }

    testWidgets('platform speak 0 then assemble does not raise word SRS', (
      tester,
    ) async {
      final client = FakeTtsClient(speakResult: 0);
      final speech = FlutterTtsSpeechService(client: client, ready: true);
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      await pumpDictation(
        tester,
        words: const [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')],
        analytics: analytics,
        wordRepo: words,
        speech: speech,
      );

      expect(client.spoken, ['きみ']);
      expect(find.text(AppStrings.dictationFailed), findsOneWidget);
      await assembleKimi(tester);

      final logged = await analytics.all();
      expect(logged.single.correct, isTrue);
      expect(logged.single.meta[AttemptMeta.heard], isFalse);
      expect(logged.single.meta[AttemptMeta.scored], isFalse);
      expect(
        logged.single.meta[AttemptMeta.playback],
        SpeechPlaybackResult.failed.name,
      );
      await words.flushPending();
      expect(
        (await WordProgressRepository.load()).statForItem('word:きみ').srsLevel,
        0,
      );
      expect(words.statForItem('word:きみ').isSeen, isFalse);
    });

    testWidgets('fail then replay success then assemble is unprompted SRS', (
      tester,
    ) async {
      final client = FakeTtsClient(speakResult: 0);
      final speech = FlutterTtsSpeechService(client: client, ready: true);
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      await pumpDictation(
        tester,
        words: const [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')],
        analytics: analytics,
        wordRepo: words,
        speech: speech,
      );

      client.speakResult = 1;
      await tester.tap(find.byKey(const ValueKey<String>('dictation-replay')));
      await tester.pump();
      expect(find.text(AppStrings.dictationFailed), findsNothing);
      await assembleKimi(tester);

      final logged = await analytics.all();
      expect(logged.single.meta[AttemptMeta.heard], isTrue);
      expect(logged.single.meta[AttemptMeta.scored], isTrue);
      expect(logged.single.meta[AttemptMeta.prompted], isFalse);
      expect(words.statForItem('word:きみ').srsLevel, 1);
    });

    testWidgets('assemble after reveal replay cannot backfill unprompted SRS', (
      tester,
    ) async {
      final client = FakeTtsClient(speakResult: 0);
      final speech = FlutterTtsSpeechService(client: client, ready: true);
      final words = await WordProgressRepository.load();
      final analytics = InMemoryAnalyticsLog();
      await pumpDictation(
        tester,
        words: const [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')],
        analytics: analytics,
        wordRepo: words,
        speech: speech,
      );

      await assembleKimi(tester);
      expect(words.statForItem('word:きみ').srsLevel, 0);
      client.speakResult = 1;
      await tester.tap(find.byKey(const ValueKey<String>('dictation-replay')));
      await tester.pump();
      await words.flushPending();
      expect(
        (await WordProgressRepository.load()).statForItem('word:きみ').srsLevel,
        0,
      );
      expect((await analytics.all()).single.meta[AttemptMeta.scored], isFalse);
    });

    testWidgets(
      'old speak complete after advance cannot credit the next word',
      (tester) async {
        const channel = MethodChannel('flutter_tts');
        Completer<int>? pendingFirst;
        Object? subsequent = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            switch (call.method) {
              case 'speak':
                if (pendingFirst == null) {
                  pendingFirst = Completer<int>();
                  return pendingFirst!.future;
                }
                return subsequent;
              case 'stop':
                return 1;
              case 'getEngines':
                return <String>['com.google.android.tts'];
              case 'setLanguage':
              case 'setEngine':
                return 1;
              default:
                return 1;
            }
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });

        final speech = await FlutterTtsSpeechService.create();
        expect(speech.ready, isTrue);
        final analytics = InMemoryAnalyticsLog();
        final words = await WordProgressRepository.load();
        await pumpDictation(
          tester,
          words: const [
            Word(kana: 'きみ', romaji: 'kimi', meaning: '你'),
            Word(kana: 'あめ', romaji: 'ame', meaning: '雨'),
          ],
          analytics: analytics,
          wordRepo: words,
          speech: speech,
        );
        expect(pendingFirst, isNotNull);

        await assembleKimi(tester);
        await tester.tap(find.text(AppStrings.dictationNext));
        pendingFirst!.complete(1);
        await tester.idle();
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('あ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('め'));
        await tester.pumpAndSettle();

        await words.flushPending();
        final reloaded = await WordProgressRepository.load();
        expect(reloaded.statForItem('word:あめ').srsLevel, 0);
        expect(reloaded.statForItem('word:あめ').isSeen, isFalse);
        expect(words.statForItem('word:あめ').srsLevel, 0);
        final logged = await analytics.all();
        expect(
          logged.where(
            (a) =>
                a.itemId.contains('あめ') &&
                a.meta[AttemptMeta.heard] == true &&
                a.meta[AttemptMeta.scored] == true,
          ),
          isEmpty,
        );
      },
    );
  });
}
