// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_exporter.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_theme.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';
import '../services/fake_snapshot_file_port.dart';
import '../support/restore_recovery_test_support.dart';

/// Widget test: 歩み is a MAP, not a scoreboard — it shows coverage (kana met /
/// total) and the per-status breakdown, with NO accuracy %, NO reaction time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('KleeOne')
      ..addFont(rootBundle.load('assets/fonts/KleeOne-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/KleeOne-SemiBold.ttf'));
    await loader.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProgressSnapshotExporter> defaultExporter(
    KanaProgressRepository store, {
    FakeSnapshotFilePort? files,
  }) async {
    final kanji = await KanjiReadingRepository.load();
    final words = await WordProgressRepository.load();
    return ProgressSnapshotExporter(
      capture: ProgressSnapshotCapture(kana: store, kanji: kanji, words: words),
      files: files ?? FakeSnapshotFilePort(),
    );
  }

  ProgressSnapshotRestorer defaultRestorer(
    PreferencesService prefs,
    KanaProgressRepository store,
    KanjiReadingRepository kanji,
    WordProgressRepository words, {
    FakeSnapshotFilePort? files,
  }) {
    final snapshots = ProgressSnapshotCapture(
      kana: store,
      kanji: kanji,
      words: words,
      prefs: prefs,
    );
    return ProgressSnapshotRestorer(
      capture: snapshots,
      transaction: ProgressRestoreTransaction(
        prefs: prefs,
        kana: store,
        kanji: kanji,
        words: words,
      ),
      files: files ?? FakeSnapshotFilePort(),
    );
  }

  Future<String> encodedBackup(
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words, {
    DateTime? createdAt,
  }) async {
    final stamp = createdAt ?? DateTime.utc(2026, 9, 14, 12, 30);
    final first = kana.allKana.first;
    await kana.recordAnswer(first, correct: true, at: stamp);
    await kana.markUnitLearned('hira_row_1');
    return ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).exportEncoded(createdAt: stamp);
  }

  void configureNarrowLargeTextView(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  Future<void> pump(
    WidgetTester tester,
    KanaProgressRepository store, {
    ProgressSnapshotExporter? exporter,
    ProgressSnapshotRestorer? restorer,
    FakePreferencesService? prefs,
    Size surface = const Size(420, 1800),
    ThemeData? theme,
    TextScaler textScaler = TextScaler.noScaling,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backing = prefs ?? await PreferencesService.create();
    final kanji = await KanjiReadingRepository.load(backing);
    final words = await WordProgressRepository.load(backing);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<ProgressSnapshotExporter>.value(
            value: exporter ?? await defaultExporter(store),
          ),
          Provider<ProgressSnapshotRestorer>.value(
            value: restorer ?? defaultRestorer(backing, store, kanji, words),
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recoveryForRepos(
              prefs: backing,
              kana: store,
              kanji: kanji,
              words: words,
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(size: surface, textScaler: textScaler),
            child: const ProgressScreen(),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> dragWithoutSettling(
    WidgetTester tester,
    Finder target,
    Offset offset,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(target));
    await gesture.moveBy(offset);
    await gesture.up();
    await tester.pump();
  }

  Future<void> revealOnPage(
    WidgetTester tester,
    Finder target, {
    Finder? scrollable,
  }) async {
    final scroller = scrollable ?? find.byType(Scrollable).first;
    for (var i = 0; i < 32; i++) {
      if (target.hitTestable().evaluate().isNotEmpty) {
        return;
      }
      await dragWithoutSettling(tester, scroller, const Offset(0, -96));
    }
    expect(target.hitTestable(), findsOneWidget);
  }

  Future<void> tapWithoutSettling(WidgetTester tester, Finder target) async {
    await tester.tapAt(tester.getCenter(target));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('cold start shows 0/208 coverage and no accuracy score', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    await pump(tester, store);

    expect(find.text('0/208'), findsOneWidget); // coverage, not a grade
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaScope), findsOneWidget);
    expect(find.text(AppStrings.practicedAllKanaHint), findsOneWidget);
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
    expect(find.text(AppStrings.practicedAllKanaScope), findsOneWidget);
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

      expect(files.saveCalls, 1);
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

    expect(files.saveCalls, 1);
    expect(find.text(AppStrings.backupSaved), findsNothing);
    expect(find.text(AppStrings.backupFailed), findsNothing);
  });

  testWidgets('restore copy names scope and excludes full-history claim', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    await pump(tester, store);

    expect(find.text(AppStrings.restoreTitle), findsOneWidget);
    expect(find.text(AppStrings.restoreScope), findsOneWidget);
    expect(find.text(AppStrings.restoreNotIncluded), findsOneWidget);
    expect(find.text(AppStrings.restoreAction), findsOneWidget);
    expect(find.textContaining('完整學習歷程'), findsOneWidget);
    expect(find.textContaining('旅行重點'), findsOneWidget);
    expect(find.textContaining('主動複習'), findsOneWidget);
    expect(find.textContaining('明日'), findsOneWidget);
  });

  test('restorePreviewBody mentions travel focus preservation', () {
    final body = AppStrings.restorePreviewBody(
      DateTime.utc(2026, 9, 14, 12, 30),
    );
    expect(body, contains('旅行重點'));
    expect(body, contains('今天已做的安排'));
    expect(body, contains('主動複習'));
    expect(body, contains('明日'));
    expect(body, isNot(contains('完整學習歷程')));
  });

  testWidgets('restore confirm dialog scrolls travel copy at 320x568 / 1.6x', (
    tester,
  ) async {
    configureNarrowLargeTextView(tester);
    late String backup;
    late FakePreferencesService prefs;
    late KanaProgressRepository store;
    late KanjiReadingRepository kanji;
    late WordProgressRepository words;
    final files = FakeSnapshotFilePort();
    await tester.runAsync(() async {
      final sourcePrefs = FakePreferencesService();
      final sourceKana = await KanaProgressRepository.load(sourcePrefs);
      final sourceKanji = await KanjiReadingRepository.load(sourcePrefs);
      final sourceWords = await WordProgressRepository.load(sourcePrefs);
      backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);
      files.pickContents = backup;

      prefs = FakePreferencesService();
      store = await KanaProgressRepository.load(prefs);
      await store.markUnitLearned('hira_row_0');
      kanji = await KanjiReadingRepository.load(prefs);
      words = await WordProgressRepository.load(prefs);
    });
    final restorer = defaultRestorer(prefs, store, kanji, words, files: files);

    await pump(
      tester,
      store,
      restorer: restorer,
      prefs: prefs,
      surface: const Size(320, 568),
      theme: AppTheme.light(),
      textScaler: const TextScaler.linear(1.6),
      settle: false,
    );
    await revealOnPage(tester, find.text(AppStrings.restoreAction));
    await tapWithoutSettling(tester, find.text(AppStrings.restoreAction));

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.text(AppStrings.restoreConfirmTitle), findsOneWidget);
    final dialogScrollable = find.descendant(
      of: dialog,
      matching: find.byType(Scrollable),
    );
    expect(dialogScrollable, findsOneWidget);

    final travelTail = find.descendant(
      of: dialog,
      matching: find.textContaining('明日照常接續'),
    );
    expect(travelTail, findsOneWidget);
    final scrollRect = tester.getRect(dialogScrollable);
    final tailBefore = tester.getRect(travelTail);
    expect(
      tailBefore.bottom,
      greaterThan(scrollRect.bottom),
      reason: 'travel tail must start below the visible dialog viewport',
    );

    for (var i = 0; i < 24; i++) {
      final tailRect = tester.getRect(travelTail);
      if (tailRect.bottom <= scrollRect.bottom + 1) {
        break;
      }
      await dragWithoutSettling(tester, dialogScrollable, const Offset(0, -72));
    }
    await tester.pump(const Duration(milliseconds: 100));

    final tailAfter = tester.getRect(travelTail);
    expect(
      tailAfter.bottom,
      lessThanOrEqualTo(scrollRect.bottom + 1),
      reason: 'scrolled travel tail must sit inside the dialog viewport',
    );
    expect(travelTail.hitTestable(), findsOneWidget);
    _expectDialogBodyNotClipped(
      tester,
      find.descendant(of: dialog, matching: find.textContaining('備份時間')),
    );
    expect(
      find.text(AppStrings.restoreConfirmNo).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.restoreConfirmYes).hitTestable(),
      findsOneWidget,
    );

    await tapWithoutSettling(tester, find.text(AppStrings.restoreConfirmNo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsNothing);
    expect(files.pickCalls, 1);
    expect(store.learnedUnits, {'hira_row_0'});
    expect(store.isUnitLearned('hira_row_1'), isFalse);
    expect(find.text(AppStrings.restoreRestored), findsNothing);
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
        capture: ProgressSnapshotCapture(
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
      expect(files.saveCalls, 0);
    },
  );
}

void _expectDialogBodyNotClipped(WidgetTester tester, Finder textFinder) {
  final paragraph = tester.renderObject<RenderParagraph>(textFinder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    textAlign: paragraph.textAlign,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textHeightBehavior: paragraph.textHeightBehavior,
    textWidthBasis: paragraph.textWidthBasis,
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: paragraph.constraints.maxWidth);

  expect(
    paragraph.size.height + 0.5,
    greaterThanOrEqualTo(painter.height),
    reason:
        'dialog body clipped: box=${paragraph.size.height.toStringAsFixed(1)} '
        'natural=${painter.height.toStringAsFixed(1)}',
  );
}
