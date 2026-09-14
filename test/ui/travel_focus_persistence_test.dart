// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/travel/travel_focus_screen.dart';
import 'package:provider/provider.dart';

import '../services/fake_preferences_service.dart';
import '../support/restore_recovery_test_support.dart';

typedef _AppHarness = ({
  FakePreferencesService prefs,
  TravelFocusRepository travel,
  ProgressPersistenceController persist,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  setUp(() {
    now = DateTime(2026, 9, 11, 12);
  });

  Future<_AppHarness> pumpHarness(
    WidgetTester tester, {
    FakePreferencesService? prefs,
    TravelFocusRepository? travel,
    Size size = const Size(420, 2400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final effectivePrefs = prefs ?? FakePreferencesService();
    final effectiveKana =
        await KanaProgressRepository.load(effectivePrefs);
    final kanji = await KanjiReadingRepository.load(effectivePrefs);
    final effectiveWords =
        await WordProgressRepository.load(effectivePrefs);
    final effectiveChecks =
        await PlacementCheckRepository.load(effectivePrefs);
    final effectiveTravel =
        travel ?? await TravelFocusRepository.load(effectivePrefs);

    final persist = ProgressPersistenceController(
      kanaFlush: effectiveKana.flushPending,
      kanjiFlush: kanji.flushPending,
      wordFlush: effectiveWords.flushPending,
      placementFlush: effectiveChecks.flushPending,
      travelFocusFlush: effectiveTravel.flushPending,
      health: [
        effectiveKana.statsHealth,
        effectiveKana.learnedUnitsHealth,
        effectiveKana.seenUnlocksHealth,
        kanji.statsHealth,
        effectiveWords.statsHealth,
        effectiveChecks.health,
        effectiveTravel.health,
      ],
    );

    final recovery = recoveryForRepos(
      prefs: effectivePrefs,
      kana: effectiveKana,
      kanji: kanji,
      words: effectiveWords,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(
            value: effectiveKana,
          ),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(
            value: effectiveWords,
          ),
          ChangeNotifierProvider<PlacementCheckRepository>.value(
            value: effectiveChecks,
          ),
          ChangeNotifierProvider<TravelFocusRepository>.value(
            value: effectiveTravel,
          ),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persist,
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              PersistenceBanner(child: child ?? const SizedBox.shrink()),
          home: HomeScreen(clock: () => now),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    return (
      prefs: effectivePrefs,
      travel: effectiveTravel,
      persist: persist,
    );
  }

  Future<_AppHarness> seedPartialTransport(WidgetTester tester) async {
    final effectivePrefs = FakePreferencesService();
    final seededPlan = TravelFocusPlan(
      focuses: [
        TravelFocus(
          scene: TravelSceneId.transport,
          date: DateTime(2026, 9, 18),
        ),
        TravelFocus(scene: TravelSceneId.clothing, date: DateTime(2026, 9, 18)),
      ],
    );
    effectivePrefs.seed('travel_focus_v1', jsonEncode(seededPlan.toJson()));

    return pumpHarness(tester, prefs: effectivePrefs);
  }

  group('TravelFocusScreen persistence (#132)', () {
    testWidgets(
      'save blocks duplicate submit while write is pending',
      (tester) async {
        final gate = PlatformGate();
        final prefs = FakePreferencesService();
        prefs.writeGates['travel_focus_v1'] = gate;
        final harness = await pumpHarness(tester, prefs: prefs);

        await tester.ensureVisible(find.text(AppStrings.travelFocusAction));
        await tester.tap(find.text(AppStrings.travelFocusAction));
        await tester.pumpAndSettle();
        expect(find.byType(TravelFocusScreen), findsOneWidget);

        await tester.tap(
          find.widgetWithText(
            CheckboxListTile,
            AppStrings.travelSceneTransport,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.travelFocusSave));
        await tester.pump();

        final saveBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, AppStrings.backupSaving),
        );
        expect(saveBtn.onPressed, isNull);
        expect(find.text(AppStrings.backupSaving), findsWidgets);

        final clearBtn = tester.widget<TextButton>(
          find.widgetWithText(TextButton, AppStrings.backupSaving),
        );
        expect(clearBtn.onPressed, isNull);

        gate.release();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byType(TravelFocusScreen).evaluate().isEmpty) break;
        }
        expect(find.byType(TravelFocusScreen), findsNothing);
      },
    );

    testWidgets(
      'save write failure stays on screen, blocks buttons; retry flushes and pops',
      (tester) async {
        final harness = await pumpHarness(tester);

        await tester.ensureVisible(find.text(AppStrings.travelFocusAction));
        await tester.tap(find.text(AppStrings.travelFocusAction));
        await tester.pumpAndSettle();
        expect(find.byType(TravelFocusScreen), findsOneWidget);

        await tester.tap(
          find.widgetWithText(
            CheckboxListTile,
            AppStrings.travelSceneTransport,
          ),
        );
        await tester.pumpAndSettle();

        harness.prefs.failWrites.add('travel_focus_v1');
        await tester.tap(find.text(AppStrings.travelFocusSave));
        await tester.pumpAndSettle();

        expect(find.byType(TravelFocusScreen), findsOneWidget);
        expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
        expect(harness.persist.hasWriteFailure, isTrue);

        final saveBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, AppStrings.travelFocusSave),
        );
        expect(saveBtn.onPressed, isNull);

        final clearBtn = tester.widget<TextButton>(
          find.widgetWithText(TextButton, AppStrings.travelFocusClear),
        );
        expect(clearBtn.onPressed, isNull);

        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.isActive, isFalse);

        harness.prefs.failWrites.clear();
        await tester.tap(find.text(AppStrings.persistRetry));
        await tester.pumpAndSettle();

        expect(harness.persist.hasWriteFailure, isFalse);
        expect(find.text(AppStrings.persistFailedLine), findsNothing);

        final reloadedAfterRetry = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(
          reloadedAfterRetry.plan.focuses.single.scene,
          TravelSceneId.transport,
        );

        await tester.tap(find.text(AppStrings.travelFocusSave));
        await tester.pumpAndSettle();
        expect(find.byType(TravelFocusScreen), findsNothing);
      },
    );

    testWidgets(
      'clear write failure stays on screen, blocks buttons; restart keeps plan',
      (tester) async {
        final harness = await seedPartialTransport(tester);

        await tester.ensureVisible(find.text(AppStrings.travelFocusEditAction));
        await tester.tap(find.text(AppStrings.travelFocusEditAction));
        await tester.pumpAndSettle();
        expect(find.byType(TravelFocusScreen), findsOneWidget);

        harness.prefs.failWrites.add('travel_focus_v1');
        await tester.tap(find.text(AppStrings.travelFocusClear));
        await tester.pumpAndSettle();

        expect(find.byType(TravelFocusScreen), findsOneWidget);
        expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
        expect(harness.persist.hasWriteFailure, isTrue);

        final saveBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, AppStrings.travelFocusSave),
        );
        expect(saveBtn.onPressed, isNull);
        final clearBtn = tester.widget<TextButton>(
          find.widgetWithText(TextButton, AppStrings.travelFocusClear),
        );
        expect(clearBtn.onPressed, isNull);

        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.isActive, isTrue);
        expect(restarted.plan.focuses.length, 2);

        harness.prefs.failWrites.clear();
        await tester.tap(find.text(AppStrings.persistRetry));
        await tester.pumpAndSettle();

        expect(harness.persist.hasWriteFailure, isFalse);
        expect(find.text(AppStrings.persistFailedLine), findsNothing);

        final reloadedAfterRetry = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(reloadedAfterRetry.plan.isActive, isFalse);

        await tester.tap(find.text(AppStrings.travelFocusClear));
        await tester.pumpAndSettle();
        expect(find.byType(TravelFocusScreen), findsNothing);
      },
    );
  });
}
