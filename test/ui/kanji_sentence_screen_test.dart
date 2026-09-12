// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/ui/kanji_sentence_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _noon() => DateTime(2026, 9, 11, 12);

const _yama = KanjiPhrase(
  segments: [
    RubySegment(text: '山', furigana: 'やま'),
    RubySegment(text: 'を'),
    RubySegment(text: '見', furigana: 'み'),
    RubySegment(text: 'る'),
  ],
  romaji: 'yama o miru',
  meaning: '看山',
);

const _kawa = KanjiPhrase(
  segments: [
    RubySegment(text: '川', furigana: 'かわ'),
    RubySegment(text: 'が'),
    RubySegment(text: '見', furigana: 'み'),
    RubySegment(text: 'える'),
  ],
  romaji: 'kawa ga mieru',
  meaning: '看得見河',
);

Future<void> _pumpKanjiSentence(
  WidgetTester tester, {
  required List<KanjiPhrase> phrases,
  required WordProgressRepository words,
  Set<String> alreadyTransferredIds = const {},
  AnalyticsLog? analytics,
}) async {
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
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
        Provider<AnalyticsLog>.value(
          value: analytics ?? InMemoryAnalyticsLog(),
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
      ],
      child: MaterialApp(
        home: KanjiSentenceScreen(
          phrases: phrases,
          title: AppStrings.kanjiSentenceTitle,
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

Future<void> _confirmUnprompted(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await _pumpFrame(tester);
  await tester.tap(find.text(AppStrings.iReadIt));
  await _pumpFrame(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('prompted confirm after hint keeps intake without climbing', (
    tester,
  ) async {
    final words = await WordProgressRepository.load();
    final analytics = InMemoryAnalyticsLog();
    await _pumpKanjiSentence(
      tester,
      phrases: const [_yama],
      words: words,
      analytics: analytics,
    );

    expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);
    expect(find.text(AppStrings.recallHint), findsOneWidget);
    await tester.tap(find.text(AppStrings.recallHint));
    await _pumpFrame(tester);
    expect(find.text('やまをみる'), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await _pumpFrame(tester);

    expect(words.statForItem(_yama.progressId).isSeen, isTrue);
    expect(words.statForItem(_yama.progressId).correctCount, 0);
    expect(words.statForItem(_yama.progressId).srsLevel, 0);
    final logged = await analytics.all();
    expect(logged.single.correct, isTrue);
    expect(logged.single.meta[AttemptMeta.prompted], isTrue);
  });

  testWidgets('unprompted 讀得出來 climbs and marks analytics unprompted', (
    tester,
  ) async {
    final words = await WordProgressRepository.load();
    final analytics = InMemoryAnalyticsLog();
    await _pumpKanjiSentence(
      tester,
      phrases: const [_yama],
      words: words,
      analytics: analytics,
    );

    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await _pumpFrame(tester);
    expect(words.statForItem(_yama.progressId).correctCount, 0);
    await tester.tap(find.text(AppStrings.iReadIt));
    await _pumpFrame(tester);

    expect(words.statForItem(_yama.progressId).correctCount, 1);
    expect(words.statForItem(_yama.progressId).srsLevel, 1);
    final logged = await analytics.all();
    expect(logged.single.correct, isTrue);
    expect(logged.single.meta[AttemptMeta.prompted], isFalse);
  });

  group('もう一回 grind gate', () {
    testWidgets('wrap same id unprompted-correct does not climb SRS', (
      tester,
    ) async {
      final words = await WordProgressRepository.load();
      await words.introduce(_yama.progressId, at: _noon());
      expect(words.statForItem(_yama.progressId).srsLevel, 1);
      await _pumpKanjiSentence(
        tester,
        phrases: const [_yama],
        words: words,
        alreadyTransferredIds: {_yama.progressId},
      );
      await _confirmUnprompted(tester);
      expect(words.statForItem(_yama.progressId).srsLevel, 1);
      expect(words.statForItem(_yama.progressId).correctCount, 1);
    });

    testWidgets('wrap miss still resets SRS', (tester) async {
      final words = await WordProgressRepository.load();
      await words.introduce(_yama.progressId, at: _noon());
      await _pumpKanjiSentence(
        tester,
        phrases: const [_yama],
        words: words,
        alreadyTransferredIds: {_yama.progressId},
      );
      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await _pumpFrame(tester);
      await tester.tap(find.text(AppStrings.iCouldnt));
      await _pumpFrame(tester);
      expect(words.statForItem(_yama.progressId).srsLevel, 0);
      expect(words.statForItem(_yama.progressId).wrongCount, 1);
    });

    testWidgets('uncovered new id still climbs on first unprompted confirm', (
      tester,
    ) async {
      final words = await WordProgressRepository.load();
      await _pumpKanjiSentence(tester, phrases: const [_kawa], words: words);
      await _confirmUnprompted(tester);
      expect(words.statForItem(_kawa.progressId).srsLevel, 1);
      expect(words.statForItem(_kawa.progressId).correctCount, 1);
    });
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
          ChangeNotifierProvider<KanjiReadingRepository>.value(
            value: await KanjiReadingRepository.load(),
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
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                KanjiSentenceScreen.route(
                  const [_yama],
                  AppStrings.kanjiSentenceTitle,
                  alreadyTransferredIds: {_yama.progressId},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _pumpFrame(tester);
    final screen = tester.widget<KanjiSentenceScreen>(
      find.byType(KanjiSentenceScreen),
    );
    expect(screen.alreadyTransferredIds, {_yama.progressId});
  });
}
