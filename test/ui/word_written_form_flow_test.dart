// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_theme.dart';
import 'package:kotonoha/ui/core/widgets/japanese_written_form.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';
import 'dictation_screen_test.dart' show pumpDictation;
import 'listening_screen_test.dart' show pumpListening;

Word word(String kana) => kWords.singleWhere((w) => w.kana == kana);

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> pumpPage(
  WidgetTester tester,
  Widget page,
  WordProgressRepository words,
  SpeechService speech,
) async {
  final kana = await KanaProgressRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>(
          create: (_) => ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            wordFlush: words.flushPending,
            kanjiFlush: () async {},
          ),
        ),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        Provider<SpeechService>.value(value: speech),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets('ferry links airport sound to 空港 at 320px / ${scale}x', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final words = await WordProgressRepository.load();
      // An existing review remains attached to its original kana ID.
      await words.introduce('word:くうこう', at: DateTime(2026, 9));
      final before = words.statForItem('word:くうこう').correctCount;
      final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
      await pumpPage(
        tester,
        FerryScreen(words: [word('くうこう'), word('かみ')], title: '渡し舟'),
        words,
        speech,
      );
      expect(find.text('空港'), findsNothing);
      expect(find.text('機場'), findsNothing);
      expect(find.byType(JapaneseWrittenForm), findsNothing);
      await tap(tester, AppStrings.ferryShowText);
      expect(find.text('くうこう'), findsOneWidget);
      expect(find.text('空港'), findsOneWidget);
      expect(find.text('機場'), findsOneWidget);
      expect(find.text(AppStrings.wordWrittenForm), findsOneWidget);
      await tester.ensureVisible(find.text('空港'));
      await tester.pumpAndSettle();
      expect(find.text('空港').hitTestable(), findsOneWidget);
      await tap(tester, AppStrings.ferryReadSelf);
      expect(find.text('空港'), findsOneWidget);
      await tap(tester, AppStrings.iReadIt);
      expect(find.text('空港'), findsNothing);
      expect(find.byType(JapaneseWrittenForm), findsNothing);
      await tap(tester, AppStrings.ferryShowText);
      expect(find.text('紙（紙）・髪（頭髮）'), findsOneWidget);
      await tap(tester, AppStrings.ferryReadSelf);
      await tap(tester, AppStrings.iReadIt);
      expect(tester.takeException(), isNull);
      expect(speech.spoken, contains('くうこう'));
      expect(speech.spoken, isNot(contains('空港')));
      await words.flushPending();
      final restored = await WordProgressRepository.load();
      expect(restored.statForItem('word:くうこう').correctCount, before);
      expect(restored.statForItem('word:空港').isSeen, isFalse);
    });
  }

  testWidgets('reading reveals spelling without changing the kana prompt', (
    tester,
  ) async {
    final words = await WordProgressRepository.load();
    await pumpPage(
      tester,
      ReadingScreen(items: [word('くうこう')], title: '黙読'),
      words,
      const SilentSpeechService(),
    );
    expect(find.text('くうこう'), findsOneWidget);
    expect(find.text('空港'), findsNothing);
    await tap(tester, AppStrings.recallHint);
    expect(find.text('空港'), findsOneWidget);
    expect(find.text('機場'), findsOneWidget);
    await tap(tester, AppStrings.iReadAfterHint);
    expect(words.statForItem('word:くうこう').srsLevel, 0);
    expect(tester.takeException(), isNull);
  });

  for (final correct in [true, false]) {
    testWidgets(
      'dictation reveals spelling after ${correct ? 'hit' : 'miss'}',
      (tester) async {
        final speech = ScriptedSpeechService(const [
          SpeechPlaybackResult.played,
        ]);
        await pumpDictation(
          tester,
          words: [word('くうこう')],
          size: const Size(320, 640),
          textScale: 2,
          speech: speech,
        );
        expect(find.text('空港'), findsNothing);
        expect(find.text('機場'), findsNothing);
        // The second う tile is a separate tile; used tiles disappear.
        for (final unit
            in correct ? ['く', 'う', 'こ', 'う'] : ['こ', 'う', 'く', 'う']) {
          final tile = find.text(unit).last;
          await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();
        }
        expect(find.text('空港'), findsOneWidget);
        expect(find.text('機場'), findsOneWidget);
        await tap(tester, AppStrings.dictationNext);
        expect(find.byType(JapaneseWrittenForm), findsNothing);
        expect(speech.spoken.every((text) => text == 'くうこう'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a word spelled as it sounds gets no 日文寫法 line', (tester) async {
    // パン IS ordinary Japanese spelling. Repeating the kana under a label
    // would be a line with nothing in it to read.
    final words = await WordProgressRepository.load();
    await pumpPage(
      tester,
      ReadingScreen(items: [word('パン')], title: '黙読'),
      words,
      const SilentSpeechService(),
    );
    await tap(tester, AppStrings.recallHint);
    expect(find.text(AppStrings.wordWrittenForm), findsNothing);
    expect(find.text('パン'), findsOneWidget);
    expect(find.text('麵包'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listening keeps spelling hidden until reveal then resets it', (
    tester,
  ) async {
    final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
    await pumpListening(
      tester,
      speech: speech,
      items: [word('くうこう'), word('えき')],
      size: const Size(320, 640),
      textScale: 2,
    );
    expect(find.text('空港'), findsNothing);
    await tap(tester, AppStrings.listeningReveal);
    expect(find.text('空港'), findsOneWidget);
    await tap(tester, AppStrings.listeningHeard);
    expect(find.text('空港'), findsNothing);
    expect(find.byType(JapaneseWrittenForm), findsNothing);
    await tap(tester, AppStrings.listeningReveal);
    expect(
      find.descendant(
        of: find.byType(JapaneseWrittenForm),
        matching: find.text('駅'),
      ),
      findsOneWidget,
    );
    await tap(tester, AppStrings.listeningHeard);
    expect(tester.takeException(), isNull);
  });
}
