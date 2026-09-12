// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';
import '../support/restore_recovery_test_support.dart';

DateTime _noon() => DateTime(2026, 9, 11, 12);

const _inu = Word(kana: 'いぬ', romaji: 'inu', meaning: '狗');

Future<void> _pumpReading(
  WidgetTester tester, {
  required List<ReadingItem> items,
  required WordProgressRepository words,
  Set<String> alreadyTransferredIds = const {},
  ProgressPersistenceController? persist,
  bool banner = false,
}) async {
  final kana = await KanaProgressRepository.load();
  final recovery = await idleRestoreRecovery();
  final persistence =
      persist ??
      ProgressPersistenceController(
        kanaFlush: kana.flushPending,
        kanjiFlush: () async {},
        wordFlush: words.flushPending,
      );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: persistence,
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
      ],
      child: MaterialApp(
        builder: banner
            ? (context, child) =>
                  PersistenceBanner(child: child ?? const SizedBox.shrink())
            : null,
        home: ReadingScreen(
          items: items,
          title: AppStrings.sentenceTitle,
          clock: _noon,
          alreadyTransferredIds: alreadyTransferredIds,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// FakePreferencesService.writeString parks on Future.delayed(Duration.zero).
/// testWidgets uses a fake clock, so a bare await never completes until we
/// pump. Keep this at the init / flush boundary — do not runAsync-seed.
Future<void> _awaitPumped(WidgetTester tester, Future<void> write) async {
  var settled = false;
  Object? error;
  StackTrace? stack;
  unawaited(
    write.then(
      (_) => settled = true,
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        settled = true;
      },
    ),
  );
  for (var i = 0; i < 16 && !settled; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(
    settled,
    isTrue,
    reason: 'prefs write did not finish under pumped clock',
  );
  if (error != null) {
    Error.throwWithStackTrace(error!, stack!);
  }
}

Future<void> _confirmUnprompted(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await _pumpFrame(tester);
  await tester.tap(find.text(AppStrings.iReadIt));
  await _pumpFrame(tester);
}

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
    expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);

    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pumpAndSettle();
    expect(find.text('inu'), findsOneWidget);
    expect(find.text('狗'), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await tester.pumpAndSettle();

    // Q2.
    expect(find.text('やま'), findsOneWidget);
    await tester.tap(find.text(AppStrings.recallHint));
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
    expect(logged.first.meta[AttemptMeta.prompted], isTrue);
    expect(logged.last.meta[AttemptMeta.prompted], isTrue);
    // Prompted "現在讀對了" keeps intake but must not climb recall.
    expect(wordRepo.statForItem('word:いぬ').isSeen, isTrue);
    expect(wordRepo.statForItem('word:いぬ').correctCount, 0);
    expect(wordRepo.statForItem('word:いぬ').srsLevel, 0);
    expect(wordRepo.statForItem('word:やま').srsLevel, 0);
    expect(wordRepo.statForItem('word:やま').wrongCount, 1);
  });

  testWidgets('unprompted 讀得出來 climbs the schedule without showing romaji', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: store.flushPending,
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    final analytics = InMemoryAnalyticsLog();
    const words = [Word(kana: 'いぬ', romaji: 'inu', meaning: '狗')];

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
    expect(find.text('inu'), findsNothing);
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    expect(find.text('inu'), findsOneWidget);
    expect(wordRepo.statForItem('word:いぬ').correctCount, 0);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);
    expect(wordRepo.statForItem('word:いぬ').correctCount, 1);
    expect(wordRepo.statForItem('word:いぬ').srsLevel, 1);
    final logged = await analytics.all();
    expect(logged.single.meta[AttemptMeta.prompted], isFalse);
  });

  group('もう一回 grind gate', () {
    testWidgets('wrap same id unprompted-correct does not climb SRS', (
      tester,
    ) async {
      final words = await WordProgressRepository.load();
      await words.introduce('word:いぬ', at: _noon());
      expect(words.statForItem('word:いぬ').srsLevel, 1);
      await _pumpReading(
        tester,
        items: const [_inu],
        words: words,
        alreadyTransferredIds: {'word:いぬ'},
      );
      await _confirmUnprompted(tester);
      expect(words.statForItem('word:いぬ').srsLevel, 1);
      expect(words.statForItem('word:いぬ').correctCount, 1);
    });

    testWidgets('wrap miss still resets SRS', (tester) async {
      final words = await WordProgressRepository.load();
      await words.introduce('word:いぬ', at: _noon());
      await _pumpReading(
        tester,
        items: const [_inu],
        words: words,
        alreadyTransferredIds: {'word:いぬ'},
      );
      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await _pumpFrame(tester);
      await tester.tap(find.text(AppStrings.iCouldnt));
      await _pumpFrame(tester);
      expect(words.statForItem('word:いぬ').srsLevel, 0);
    });

    testWidgets('prompted confirm after hint does not climb as independent', (
      tester,
    ) async {
      final words = await WordProgressRepository.load();
      await words.introduce('word:いぬ', at: _noon());
      await _pumpReading(tester, items: const [_inu], words: words);
      await tester.tap(find.text(AppStrings.recallHint));
      await _pumpFrame(tester);
      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await _pumpFrame(tester);
      expect(words.statForItem('word:いぬ').srsLevel, 1);
      expect(words.statForItem('word:いぬ').correctCount, 1);
    });

    testWidgets('uncovered new id still climbs on first unprompted confirm', (
      tester,
    ) async {
      final words = await WordProgressRepository.load();
      await words.introduce('word:いぬ', at: _noon());
      await _pumpReading(tester, items: const [_inu], words: words);
      await _confirmUnprompted(tester);
      expect(words.statForItem('word:いぬ').srsLevel, 2);
    });

    testWidgets('failed save retry flushes without climbing again', (
      tester,
    ) async {
      final fake = FakePreferencesService();
      final words = await WordProgressRepository.load(fake);
      await _awaitPumped(tester, words.introduce('word:いぬ', at: _noon()));
      expect(words.statForItem('word:いぬ').srsLevel, 1);
      fake.failWrites.add('word_stats_v1');
      final persist = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: words.flushPending,
      );
      await _pumpReading(
        tester,
        items: const [_inu],
        words: words,
        persist: persist,
        banner: true,
      );
      await _confirmUnprompted(tester);
      expect(words.statForItem('word:いぬ').srsLevel, 2);
      expect(words.statForItem('word:いぬ').correctCount, 2);
      expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
      expect(find.text(AppStrings.persistRetry), findsOneWidget);

      fake.failWrites.clear();
      await tester.tap(find.text(AppStrings.persistRetry));
      await _pumpFrame(tester);
      expect(persist.hasWriteFailure, isFalse);
      expect(words.statForItem('word:いぬ').srsLevel, 2);
      expect(words.statForItem('word:いぬ').correctCount, 2);
      final reloaded = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForItem('word:いぬ').srsLevel, 2);
    });

    testWidgets('route forwards alreadyTransferredIds into the screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<KanaProgressRepository>.value(
              value: await KanaProgressRepository.load(),
            ),
            ChangeNotifierProvider<WordProgressRepository>.value(
              value: await WordProgressRepository.load(),
            ),
            ChangeNotifierProvider<ProgressPersistenceController>.value(
              value: ProgressPersistenceController(
                kanaFlush: () async {},
                kanjiFlush: () async {},
                wordFlush: () async {},
              ),
            ),
            Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
            Provider<SpeechService>.value(value: const SilentSpeechService()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      ReadingScreen.route(
                        const [_inu],
                        AppStrings.sentenceTitle,
                        clock: _noon,
                        alreadyTransferredIds: {'word:いぬ'},
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();
      final screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      expect(screen.alreadyTransferredIds, {'word:いぬ'});
      expect(screen.clock, isNotNull);
    });
  });

  testWidgets('320×640 / 2x keeps カードは つかえません meaning and grade reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(320, 640));
    final words = await WordProgressRepository.load();
    await _pumpReading(
      tester,
      items: const [
        Phrase(
          kana: 'カードは つかえません',
          romaji: 'kaado wa tsukaemasen',
          meaning: '不能用卡',
        ),
      ],
      words: words,
    );

    expect(find.text('カードは つかえません'), findsOneWidget);
    await tester.ensureVisible(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iReadUnprompted).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await _pumpFrame(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('reading-meaning')),
    );
    await tester.pumpAndSettle();
    expect(find.text('不能用卡').hitTestable(), findsOneWidget);
    final meaning = tester.getRect(
      find.byKey(const ValueKey<String>('reading-meaning')),
    );
    expect(meaning.bottom, lessThanOrEqualTo(641));
    expect(meaning.top, greaterThanOrEqualTo(-1));
    expect(words.statForItem('phrase:カードは つかえません').isSeen, isFalse);
    await tester.ensureVisible(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iReadIt).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadIt));
    await _pumpFrame(tester);
    expect(words.statForItem('phrase:カードは つかえません').isSeen, isTrue);
  });
}
