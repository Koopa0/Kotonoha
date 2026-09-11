// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';
import '../services/fake_snapshot_file_port.dart';

/// Widget test: 歩み is a MAP, not a scoreboard — it shows coverage (kana met /
/// total) and the per-status breakdown, with NO accuracy %, NO reaction time.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProgressSnapshotExporter> defaultExporter(
    KanaProgressRepository store, {
    FakeSnapshotFilePort? files,
  }) async {
    final kanji = await KanjiReadingRepository.load();
    final words = await WordProgressRepository.load();
    return ProgressSnapshotExporter(
      snapshots: ProgressSnapshotRepository(
        kana: store,
        kanji: kanji,
        words: words,
      ),
      files: files ?? FakeSnapshotFilePort(),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    KanaProgressRepository store, {
    ProgressSnapshotExporter? exporter,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<ProgressSnapshotExporter>.value(
            value: exporter ?? await defaultExporter(store),
          ),
        ],
        child: const MaterialApp(home: ProgressScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold start shows 0/208 coverage and no accuracy score', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    await pump(tester, store);

    expect(find.text('0/208'), findsOneWidget); // coverage, not a grade
    expect(find.textContaining('%'), findsNothing); // no accuracy anywhere
    expect(
      find.widgetWithText(Container, AppStrings.statusNew),
      findsOneWidget,
    );
  });

  testWidgets('recorded answers move coverage and the status counts', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final at = DateTime(2026, 6);
    // 4 strong (5 correct each) + 1 clearly weak (3 wrong) → 5 kana met.
    for (final k in kHiraganaGojuon.take(4)) {
      for (var i = 0; i < 5; i++) {
        await store.recordAnswer(k, correct: true, at: at, latencyMs: 300);
      }
    }
    final weak = kHiraganaGojuon[4];
    for (var i = 0; i < 3; i++) {
      await store.recordAnswer(weak, correct: false, at: at);
    }
    await pump(tester, store);

    expect(find.text('5/208'), findsOneWidget); // 5 kana met
    expect(find.textContaining('%'), findsNothing); // still no score
    // The 4 strong kana surface in the 熟練 row.
    expect(
      find.widgetWithText(Container, AppStrings.statusStrong),
      findsOneWidget,
    );
  });

  testWidgets(
    'backup copy names the five bodies and refuses a full-history claim',
    (tester) async {
      final store = await KanaProgressRepository.load();
      await pump(tester, store);

      expect(find.text(AppStrings.backupTitle), findsOneWidget);
      expect(find.text(AppStrings.backupScope), findsOneWidget);
      expect(find.text(AppStrings.backupNotIncluded), findsOneWidget);
      expect(find.text(AppStrings.backupAction), findsOneWidget);
      expect(find.textContaining('完整學習歷程'), findsOneWidget);
      expect(find.textContaining('不是完整'), findsOneWidget);
      expect(find.textContaining('完整備份'), findsNothing);
    },
  );

  testWidgets(
    'saving offers a self-importable snapshot and reports the location',
    (tester) async {
      final store = await KanaProgressRepository.load();
      final files = FakeSnapshotFilePort();
      await pump(
        tester,
        store,
        exporter: await defaultExporter(store, files: files),
      );

      await tester.ensureVisible(find.text(AppStrings.backupAction));
      await tester.tap(find.text(AppStrings.backupAction));
      await tester.pumpAndSettle();

      expect(files.calls, 1);
      expect(
        const ProgressSnapshotCodec().decodeAndValidate(files.lastContents!),
        isA<SnapshotDecodeSuccess>(),
      );
      expect(find.text(AppStrings.backupSaved), findsOneWidget);
    },
  );

  testWidgets('cancelling the picker leaves no saved copy and writes nothing', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final files = FakeSnapshotFilePort()..next = SnapshotSaveOutcome.cancelled;
    await pump(
      tester,
      store,
      exporter: await defaultExporter(store, files: files),
    );

    await tester.ensureVisible(find.text(AppStrings.backupAction));
    await tester.tap(find.text(AppStrings.backupAction));
    await tester.pumpAndSettle();

    expect(files.calls, 1);
    expect(find.text(AppStrings.backupSaved), findsNothing);
    expect(find.text(AppStrings.backupFailed), findsNothing);
  });

  testWidgets(
    'recoveryRequired disables save and never reaches the file port',
    (tester) async {
      final prefs = FakePreferencesService();
      prefs.seed('kana_stats_v1', 'not json');
      final store = await KanaProgressRepository.load(prefs);
      final kanji = await KanjiReadingRepository.load(prefs);
      final words = await WordProgressRepository.load(prefs);
      expect(store.statsHealth, StoreHealth.recoveryRequired);
      final files = FakeSnapshotFilePort();
      final exporter = ProgressSnapshotExporter(
        snapshots: ProgressSnapshotRepository(
          kana: store,
          kanji: kanji,
          words: words,
        ),
        files: files,
      );
      await pump(tester, store, exporter: exporter);

      expect(find.text(AppStrings.backupBlocked), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, AppStrings.backupAction),
      );
      expect(button.onPressed, isNull);
      expect(files.calls, 0);
    },
  );
}
