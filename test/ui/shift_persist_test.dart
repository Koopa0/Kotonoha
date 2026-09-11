// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home→今天只練原句 with production [FileAnalyticsLog] and an injected
/// append fault. Memory keeps the sitting; the close must not claim a
/// durable hold, and retry only flushes the existing buffer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kotonoha-shift-persist-');
    file = File('${dir.path}/log.jsonl');
    await file.create();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets(
    'Home hold write failure keeps memory, shows retry, and does not claim persist',
    (tester) async {
      final analytics = FileAnalyticsLog.forFile(file);
      await analytics.all();
      analytics.debugAppend = (f, line) async {
        throw const FileSystemException('injected append failure');
      };
      final words = await WordProgressRepository.load();
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpHome(
        tester,
        analytics: analytics,
        words: words,
        clock: () => DateTime(2026, 9, 10, 10),
      );

      await tester.tap(find.text(AppStrings.shiftAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftHoldStart));
      await tester.pumpAndSettle();
      await _completeBeat(tester);

      expect(find.text(AppStrings.persistFailedLine), findsWidgets);
      expect(find.text(AppStrings.shiftPersistFailed), findsWidgets);
      expect(find.text(AppStrings.persistRetry), findsWidgets);
      expect(find.text(AppStrings.shiftHeldUntilTomorrow), findsNothing);
      expect(await analytics.count(), 6);
      expect(analytics.unpersistedCount, 6);
      expect(words.stats, isEmpty);

      final cold = FileAnalyticsLog.forFile(file);
      expect(await cold.count(), 0);

      analytics.debugAppend = null;
      await tester.tap(find.text(AppStrings.persistRetry));
      await tester.pumpAndSettle();

      expect(analytics.unpersistedCount, 0);
      expect(find.text(AppStrings.shiftHeldUntilTomorrow), findsWidgets);
      expect(find.text(AppStrings.persistFailedLine), findsNothing);
      final reopened = FileAnalyticsLog.forFile(file);
      expect(await reopened.count(), 6);
    },
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required AnalyticsLog analytics,
  required WordProgressRepository words,
  required DateTime Function() clock,
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
            analyticsFlush: analytics.flushPending,
          ),
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: analytics),
      ],
      child: MaterialApp(home: HomeScreen(clock: clock)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeBeat(WidgetTester tester) async {
  await _tapVisible(tester, find.text(AppStrings.iReadUnprompted));
  await _tapVisible(tester, find.text(AppStrings.iReadIt));
  await tester.enterText(find.byType(TextField), '自評用筆記');
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.text(AppStrings.shiftSenseReady));
  await _tapVisible(tester, find.text(AppStrings.shiftSenseOk));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      280,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
