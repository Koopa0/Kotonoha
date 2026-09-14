// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_exporter.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';
import '../services/fake_snapshot_file_port.dart';
import '../support/restore_recovery_test_support.dart';

/// #102: the two rings keep 92 / 208, and only the nearby copy names the set.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('same sample keeps 5/92 on home and 5/208 on 歩み', (tester) async {
    final store = await _seedGojuon(count: 5);
    await _pumpHome(tester, store);
    expect(find.text('5/92'), findsOneWidget);
    expect(find.text('5/208'), findsNothing);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text(AppStrings.practicedGojuonScope), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaScope), findsNothing);
    expect(find.text(AppStrings.practicedAllKanaHint), findsNothing);

    await _pumpProgress(tester, store);
    expect(find.text('5/208'), findsOneWidget);
    expect(find.text('5/92'), findsNothing);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaScope), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaHint), findsOneWidget);
    expect(find.text(AppStrings.practicedGojuonScope), findsNothing);
  });

  testWidgets('an extended kana widens only the 歩み ring', (tester) async {
    final store = await _seedGojuon(count: 5);
    await store.recordAnswer(
      kHiraganaDakuten.first,
      correct: true,
      at: DateTime(2026, 6),
      latencyMs: 300,
    );

    await _pumpHome(tester, store);
    expect(find.text('5/92'), findsOneWidget);
    expect(find.text(AppStrings.practicedGojuonScope), findsOneWidget);

    await _pumpProgress(tester, store);
    expect(find.text('6/208'), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaScope), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaHint), findsOneWidget);
  });

  testWidgets('rings keep contact wording, not mastery wording', (
    tester,
  ) async {
    final store = await _seedGojuon(count: 5);
    await _pumpHome(tester, store);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text('學會'), findsNothing);
    expect(find.text('完成'), findsNothing);

    await _pumpProgress(tester, store);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text('學會'), findsNothing);
    expect(find.text('完成'), findsNothing);
  });

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets(
        'home ${width.toInt()}px at ${scale}x keeps scope copy without overflow',
        (tester) async {
          final store = await _seedGojuon(count: 5);
          await _pumpHome(
            tester,
            store,
            size: Size(width, 1800),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('5/92'), findsOneWidget);
          expect(find.text(AppStrings.practiced), findsOneWidget);
          expect(find.text(AppStrings.practicedGojuonScope), findsOneWidget);
          _expectUnclipped(tester, AppStrings.practicedGojuonScope);
        },
      );

      testWidgets(
        '歩み ${width.toInt()}px at ${scale}x keeps scope copy without overflow',
        (tester) async {
          final store = await _seedGojuon(count: 5);
          await _pumpProgress(
            tester,
            store,
            size: Size(width, 1800),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('5/208'), findsOneWidget);
          expect(find.text(AppStrings.practiced), findsOneWidget);
          expect(find.text(AppStrings.practicedAllKanaScope), findsOneWidget);
          expect(find.text(AppStrings.practicedAllKanaHint), findsOneWidget);
          _expectUnclipped(tester, AppStrings.practicedAllKanaScope);
          _expectUnclipped(tester, AppStrings.practicedAllKanaHint);
        },
      );
    }
  }

  testWidgets('ProgressRing title stays outside the 148 box at 2x', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Center(
              child: ProgressRing(
                value: 0,
                centerLabel: '0/92',
                caption: AppStrings.practiced,
                title: AppStrings.practicedGojuonScope,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('0/92'), findsOneWidget);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text(AppStrings.practicedGojuonScope), findsOneWidget);

    final ringFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SizedBox && widget.width == 148 && widget.height == 148,
    );
    final ringBox = tester.getRect(ringFinder);
    final titleBox = tester.getRect(find.text(AppStrings.practicedGojuonScope));
    expect(titleBox.top, greaterThanOrEqualTo(ringBox.bottom));
    expect(ringBox.height, 148);
  });
}

Future<KanaProgressRepository> _seedGojuon({required int count}) async {
  final store = await KanaProgressRepository.load();
  final at = DateTime(2026, 6);
  for (final kana in kHiraganaGojuon.take(count)) {
    await store.recordAnswer(kana, correct: true, at: at, latencyMs: 300);
  }
  return store;
}

Future<void> _pumpHome(
  WidgetTester tester,
  KanaProgressRepository store, {
  Size size = const Size(420, 1800),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final backing = FakePreferencesService();
  final kanji = await KanjiReadingRepository.load(backing);
  final words = await WordProgressRepository.load(backing);
  final recovery = await idleRestoreRecovery(backing);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: store.flushPending,
            kanjiFlush: kanji.flushPending,
            wordFlush: words.flushPending,
          ),
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const HomeScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpProgress(
  WidgetTester tester,
  KanaProgressRepository store, {
  Size size = const Size(420, 1800),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final backing = await PreferencesService.create();
  final kanji = await KanjiReadingRepository.load(backing);
  final words = await WordProgressRepository.load(backing);
  final snapshots = ProgressSnapshotCapture(
    kana: store,
    kanji: kanji,
    words: words,
    prefs: backing,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        Provider<ProgressSnapshotExporter>.value(
          value: ProgressSnapshotExporter(
            capture: snapshots,
            files: FakeSnapshotFilePort(),
          ),
        ),
        Provider<ProgressSnapshotRestorer>.value(
          value: ProgressSnapshotRestorer(
            capture: snapshots,
            transaction: ProgressRestoreTransaction(
              prefs: backing,
              kana: store,
              kanji: kanji,
              words: words,
            ),
            files: FakeSnapshotFilePort(),
          ),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const ProgressScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectUnclipped(WidgetTester tester, String label) {
  final text = tester.widget<Text>(find.text(label));
  expect(text.maxLines, isNull);
  expect(text.overflow, anyOf(isNull, TextOverflow.visible, TextOverflow.clip));
  expect(tester.getSize(find.text(label)).height, greaterThan(0));
}
