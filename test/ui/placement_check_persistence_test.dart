// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/placement/placement_check_screen.dart';
import 'package:kotonoha/ui/placement/placement_result_screen.dart';
import 'package:kotonoha/ui/placement/placement_scope_screen.dart';
import 'package:provider/provider.dart';

import '../services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unprompted health: independent stays independent after reload', (
    tester,
  ) async {
    final app = await _pumpFormal(tester);
    await _openAoCheck(tester);
    await _independentCorrect(tester);

    expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 1);
    expect(
      app.checks.draft.records.single.outcome,
      PlacementOutcome.independent,
    );
    expect(find.text(AppStrings.persistFailedLine), findsNothing);
    expect(app.persist.hasWriteFailure, isFalse);

    final reloaded = await _remount(tester, app);
    expect(reloaded.kana.statFor(_kanaOf(reloaded.kana, 'あ')).correctCount, 1);
    expect(
      reloaded.checks.draft.records.single.outcome,
      PlacementOutcome.independent,
    );
    expect(reloaded.checks.draft.isHinted('あ'), isFalse);

    await _resumeCheck(tester);
    expect(find.byType(PlacementCheckScreen), findsOneWidget);
    expect(find.text('い'), findsOneWidget);
    expect(find.text('あ'), findsNothing);
    expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);
  });

  testWidgets(
    'same-visit 讀得出來 then 讀對了 stays independent — reveal persist does not wipe it',
    (tester) async {
      final app = await _pumpFormal(tester);
      await _openAoCheck(tester);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
      expect(find.text(AppStrings.iReadIt), findsOneWidget);
      expect(find.text(AppStrings.iReadAfterHint), findsNothing);

      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      expect(
        app.checks.draft.records.single.outcome,
        PlacementOutcome.independent,
      );
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 1);
    },
  );

  testWidgets('hint, leave, resume: cannot mint a first independent correct', (
    tester,
  ) async {
    final app = await _pumpFormal(tester);
    await _openAoCheck(tester);

    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(app.checks.draft.isHinted('あ'), isTrue);
    expect(find.text(AppStrings.iReadUnprompted), findsNothing);
    expect(find.text(AppStrings.iReadAfterHint), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PlacementScopeScreen), findsOneWidget);
    expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 0);

    await tester.tap(find.text(AppStrings.placementResume));
    await tester.pumpAndSettle();
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text(AppStrings.iReadUnprompted), findsNothing);
    expect(find.text(AppStrings.iReadAfterHint), findsOneWidget);

    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await tester.pumpAndSettle();
    expect(app.checks.draft.records.single.outcome, PlacementOutcome.prompted);
    expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 0);
    expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).seenCount, 1);
  });

  testWidgets(
    'hint then process reload keeps prompted-only — no independent wash',
    (tester) async {
      final app = await _pumpFormal(tester);
      await _openAoCheck(tester);
      await tester.tap(find.text(AppStrings.recallHint));
      await tester.pumpAndSettle();
      expect(app.checks.draft.isHinted('あ'), isTrue);

      final reloaded = await _remount(tester, app);
      expect(reloaded.checks.draft.isHinted('あ'), isTrue);
      expect(reloaded.checks.draft.pendingKanaIds.first, 'あ');
      expect(reloaded.checks.draft.records, isEmpty);

      await _resumeCheck(tester);
      expect(find.text('あ'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text(AppStrings.iReadUnprompted), findsNothing);

      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      expect(
        reloaded.checks.draft.records.single.outcome,
        PlacementOutcome.prompted,
      );
      expect(
        reloaded.kana.statFor(_kanaOf(reloaded.kana, 'あ')).correctCount,
        0,
      );
    },
  );

  testWidgets(
    '讀得出來 reveal, leave, resume: cannot restart a first unprompted round',
    (tester) async {
      final app = await _pumpFormal(tester);
      await _openAoCheck(tester);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
      expect(app.checks.draft.isHinted('あ'), isTrue);
      expect(find.text(AppStrings.iReadIt), findsOneWidget);
      expect(find.text(AppStrings.iReadUnprompted), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PlacementScopeScreen), findsOneWidget);
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 0);

      await tester.tap(find.text(AppStrings.placementResume));
      await tester.pumpAndSettle();
      expect(find.text('あ'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text(AppStrings.iReadUnprompted), findsNothing);
      expect(find.text(AppStrings.iReadAfterHint), findsOneWidget);

      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      expect(
        app.checks.draft.records.single.outcome,
        PlacementOutcome.prompted,
      );
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 0);
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).seenCount, 1);
    },
  );

  testWidgets('讀得出來 reveal then process reload stays prompted-only', (
    tester,
  ) async {
    final app = await _pumpFormal(tester);
    await _openAoCheck(tester);
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    expect(app.checks.draft.isHinted('あ'), isTrue);

    final reloaded = await _remount(tester, app);
    expect(reloaded.checks.draft.isHinted('あ'), isTrue);
    expect(reloaded.checks.draft.pendingKanaIds.first, 'あ');
    expect(reloaded.checks.draft.records, isEmpty);

    await _resumeCheck(tester);
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text(AppStrings.iReadUnprompted), findsNothing);
    expect(find.text(AppStrings.iReadAfterHint), findsOneWidget);

    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await tester.pumpAndSettle();
    expect(
      reloaded.checks.draft.records.single.outcome,
      PlacementOutcome.prompted,
    );
    expect(reloaded.kana.statFor(_kanaOf(reloaded.kana, 'あ')).correctCount, 0);
  });

  testWidgets('start write failure stays on scope; retry then resume', (
    tester,
  ) async {
    final app = await _pumpFormal(tester);
    await _openScope(tester);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'あ行'));
    await tester.pumpAndSettle();

    app.prefs.failWrites.add('placement_check_v1');
    await tester.tap(find.text(AppStrings.placementStart));
    await tester.pumpAndSettle();

    expect(find.byType(PlacementCheckScreen), findsNothing);
    expect(find.byType(PlacementScopeScreen), findsOneWidget);
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
    expect(app.persist.hasWriteFailure, isTrue);
    expect(app.checks.draft.hasProgress, isTrue);
    expect(
      (await PlacementCheckRepository.load(
        FakePreferencesService.restarted(app.prefs),
      )).draft.hasProgress,
      isFalse,
    );

    app.prefs.failWrites.clear();
    await tester.tap(find.text(AppStrings.persistRetry));
    await tester.pumpAndSettle();
    expect(app.persist.hasWriteFailure, isFalse);
    expect(find.text(AppStrings.persistFailedLine), findsNothing);

    final afterRetry = await PlacementCheckRepository.load(
      FakePreferencesService.restarted(app.prefs),
    );
    expect(afterRetry.draft.pendingKanaIds.first, 'あ');

    await tester.tap(find.text(AppStrings.placementResume));
    await tester.pumpAndSettle();
    expect(find.byType(PlacementCheckScreen), findsOneWidget);
    expect(find.text('あ'), findsOneWidget);
  });

  testWidgets(
    '讀得出來 reveal write failure blocks confirm; retry keeps same-visit independent',
    (tester) async {
      final app = await _pumpFormal(tester);
      await _openAoCheck(tester);

      app.prefs.failWrites.add('placement_check_v1');
      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
      expect(app.persist.hasWriteFailure, isTrue);
      expect(app.checks.draft.isHinted('あ'), isTrue);
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 0);

      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, AppStrings.iReadIt),
      );
      expect(confirm.onPressed, isNull);

      app.prefs.failWrites.clear();
      await tester.tap(find.text(AppStrings.persistRetry));
      await tester.pumpAndSettle();
      expect(app.persist.hasWriteFailure, isFalse);

      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      expect(
        app.checks.draft.records.single.outcome,
        PlacementOutcome.independent,
      );
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 1);
    },
  );

  testWidgets(
    'per-question write failure surfaces; retry flushes without re-grading',
    (tester) async {
      final app = await _pumpFormal(tester);
      await _openAoCheck(tester);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      app.prefs.failWrites.add('placement_check_v1');
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
      expect(app.persist.hasWriteFailure, isTrue);
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 1);
      expect(app.checks.draft.records.single.kanaId, 'あ');
      expect(
        (await PlacementCheckRepository.load(
          FakePreferencesService.restarted(app.prefs),
        )).draft.pendingKanaIds.first,
        'あ',
      );

      final continueBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, AppStrings.continueLabel),
      );
      expect(continueBtn.onPressed, isNull);

      app.prefs.failWrites.clear();
      await tester.tap(find.text(AppStrings.persistRetry));
      await tester.pumpAndSettle();
      expect(app.persist.hasWriteFailure, isFalse);
      expect(app.kana.statFor(_kanaOf(app.kana, 'あ')).correctCount, 1);

      final recovered = await _remount(tester, app);
      expect(recovered.checks.draft.records.single.kanaId, 'あ');
      expect(
        recovered.checks.draft.records.single.outcome,
        PlacementOutcome.independent,
      );
      expect(
        recovered.kana.statFor(_kanaOf(recovered.kana, 'あ')).correctCount,
        1,
      );

      await _resumeCheck(tester);
      expect(find.text('い'), findsOneWidget);
      expect(find.text('あ'), findsNothing);
      expect(
        recovered.kana.statFor(_kanaOf(recovered.kana, 'あ')).correctCount,
        1,
      );
    },
  );

  testWidgets('discard write failure stays visible; retry flushes empty', (
    tester,
  ) async {
    final app = await _pumpFormal(tester);
    await _openAoCheck(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.placementResume), findsOneWidget);

    app.prefs.failWrites.add('placement_check_v1');
    await tester.tap(find.text(AppStrings.placementStartNew));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
    expect(app.persist.hasWriteFailure, isTrue);
    expect(app.checks.draft.hasProgress, isFalse);
    expect(
      (await PlacementCheckRepository.load(
        FakePreferencesService.restarted(app.prefs),
      )).draft.hasProgress,
      isTrue,
    );

    app.prefs.failWrites.clear();
    await tester.tap(find.text(AppStrings.persistRetry));
    await tester.pumpAndSettle();
    expect(app.persist.hasWriteFailure, isFalse);

    final recovered = await _remount(tester, app);
    expect(recovered.checks.draft.hasProgress, isFalse);
    await tester.tap(find.text(AppStrings.learnNewKanaAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.placementEntry));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.placementResume), findsNothing);
  });

  testWidgets(
    'clear-on-complete failure is visible; retry does not re-mark the row',
    (tester) async {
      final app = await _pumpFormal(tester);
      await _openAoCheck(tester);
      for (var i = 0; i < 4; i++) {
        await _independentCorrect(tester);
        await tester.tap(find.text(AppStrings.continueLabel));
        await tester.pumpAndSettle();
      }
      await _independentCorrect(tester);

      app.prefs.failWrites.add('placement_check_v1');
      await tester.tap(find.text(AppStrings.seeResults));
      await tester.pumpAndSettle();

      expect(find.byType(PlacementResultScreen), findsOneWidget);
      expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
      expect(app.persist.hasWriteFailure, isTrue);
      expect(app.kana.isUnitLearned('hira_row_0'), isTrue);
      expect(app.checks.draft.hasProgress, isFalse);
      expect(
        (await PlacementCheckRepository.load(
          FakePreferencesService.restarted(app.prefs),
        )).draft.isComplete,
        isTrue,
      );

      app.prefs.failWrites.clear();
      await tester.tap(find.text(AppStrings.persistRetry));
      await tester.pumpAndSettle();
      expect(app.persist.hasWriteFailure, isFalse);

      final recovered = await _remount(tester, app);
      expect(recovered.checks.draft.hasProgress, isFalse);
      expect(recovered.kana.isUnitLearned('hira_row_0'), isTrue);
      expect(find.byType(PlacementScopeScreen), findsNothing);
    },
  );
}

Kana _kanaOf(KanaProgressRepository store, String character) =>
    store.allKana.firstWhere((k) => k.character == character);

typedef _FormalApp = ({
  FakePreferencesService prefs,
  KanaProgressRepository kana,
  PlacementCheckRepository checks,
  ProgressPersistenceController persist,
});

Future<_FormalApp> _pumpFormal(
  WidgetTester tester, [
  FakePreferencesService? existing,
]) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prefs = existing ?? FakePreferencesService();
  final kana = await KanaProgressRepository.load(prefs);
  final kanji = await KanjiReadingRepository.load(prefs);
  final words = await WordProgressRepository.load(prefs);
  final checks = await PlacementCheckRepository.load(prefs);
  final persist = ProgressPersistenceController(
    kanaFlush: kana.flushPending,
    kanjiFlush: kanji.flushPending,
    wordFlush: words.flushPending,
    placementFlush: checks.flushPending,
    health: [
      kana.statsHealth,
      kana.learnedUnitsHealth,
      kana.seenUnlocksHealth,
      kanji.statsHealth,
      words.statsHealth,
      checks.health,
    ],
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<PlacementCheckRepository>.value(value: checks),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: persist,
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (prefs: prefs, kana: kana, checks: checks, persist: persist);
}

Future<_FormalApp> _remount(WidgetTester tester, _FormalApp previous) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  return _pumpFormal(tester, FakePreferencesService.restarted(previous.prefs));
}

Future<void> _openScope(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.learnNewKanaAction));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.placementEntry));
  await tester.pumpAndSettle();
}

Future<void> _openAoCheck(WidgetTester tester) async {
  await _openScope(tester);
  await tester.tap(find.widgetWithText(CheckboxListTile, 'あ行'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.placementStart));
  await tester.pumpAndSettle();
}

Future<void> _resumeCheck(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.learnNewKanaAction));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.placementEntry));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.placementResume));
  await tester.pumpAndSettle();
}

Future<void> _independentCorrect(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.iReadIt));
  await tester.pumpAndSettle();
}
