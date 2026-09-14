// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
import 'package:kotonoha/ui/travel/travel_focus_screen.dart';
import 'package:provider/provider.dart';

import '../services/fake_preferences_service.dart';
import '../support/restore_recovery_test_support.dart';

typedef _AppHarness = ({
  FakePreferencesService prefs,
  KanaProgressRepository kana,
  WordProgressRepository words,
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
    KanaProgressRepository? kana,
    WordProgressRepository? words,
    PlacementCheckRepository? checks,
    TravelFocusRepository? travel,
    Size size = const Size(420, 2400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final effectivePrefs = prefs ?? FakePreferencesService();
    final effectiveKana =
        kana ?? await KanaProgressRepository.load(effectivePrefs);
    final kanji = await KanjiReadingRepository.load(effectivePrefs);
    final effectiveWords =
        words ?? await WordProgressRepository.load(effectivePrefs);
    final effectiveChecks =
        checks ?? await PlacementCheckRepository.load(effectivePrefs);
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
      kana: effectiveKana,
      words: effectiveWords,
      travel: effectiveTravel,
      persist: persist,
    );
  }

  Future<_AppHarness> seedPartialTransport(
    WidgetTester tester, {
    FakePreferencesService? prefs,
  }) async {
    final effectivePrefs = prefs ?? FakePreferencesService();
    effectivePrefs.seed(
      'learned_units_v1',
      jsonEncode(['hira_row_0', 'hira_row_1']),
    );
    effectivePrefs.seed(
      'seen_unlocks_v1',
      jsonEncode(Unlock.values.map((u) => u.id).toList()),
    );
    final aStat = const KanaStat().recordAnswer(
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    final iStat = const KanaStat().recordAnswer(
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    effectivePrefs.seed(
      'kana_stats_v1',
      jsonEncode({'あ': aStat.toJson(), 'い': iStat.toJson()}),
    );
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

  Future<_AppHarness> seedMeetReady(
    WidgetTester tester, {
    FakePreferencesService? prefs,
  }) async {
    final effectivePrefs = prefs ?? FakePreferencesService();
    effectivePrefs.seed(
      'learned_units_v1',
      jsonEncode(['hira_row_0', 'hira_row_1']),
    );
    effectivePrefs.seed(
      'seen_unlocks_v1',
      jsonEncode(Unlock.values.map((u) => u.id).toList()),
    );
    final aStat = const KanaStat().recordAnswer(
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    effectivePrefs.seed('kana_stats_v1', jsonEncode({'あ': aStat.toJson()}));
    final seededPlan = TravelFocusPlan(
      focuses: [
        TravelFocus(
          scene: TravelSceneId.transport,
          date: DateTime(2026, 9, 18),
        ),
        TravelFocus(scene: TravelSceneId.clothing, date: DateTime(2026, 9, 18)),
      ],
      kanaBoostOn: DateTime(2026, 9, 11),
    );
    effectivePrefs.seed('travel_focus_v1', jsonEncode(seededPlan.toJson()));

    return pumpHarness(tester, prefs: effectivePrefs);
  }

  group('TravelFocusScreen persistence (#132)', () {
    testWidgets(
      'save write failure stays on screen, blocks buttons; retry flushes and pops',
      (tester) async {
        final harness = await pumpHarness(tester);

        // Open TravelFocusScreen
        await tester.ensureVisible(find.text(AppStrings.travelFocusAction));
        await tester.tap(find.text(AppStrings.travelFocusAction));
        await tester.pumpAndSettle();
        expect(find.byType(TravelFocusScreen), findsOneWidget);

        // Select transport scene
        await tester.tap(
          find.widgetWithText(
            CheckboxListTile,
            AppStrings.travelSceneTransport,
          ),
        );
        await tester.pumpAndSettle();

        // Fail write to travel_focus_v1
        harness.prefs.failWrites.add('travel_focus_v1');
        await tester.tap(find.text(AppStrings.travelFocusSave));
        await tester.pumpAndSettle();

        // Acceptance: stay on screen, show failure like placement scope, disable actions
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

        // Acceptance: restart reload matches what user saw after failure (not saved)
        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.isActive, isFalse);

        // Retry flushes pending plan
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

        // Buttons re-enabled; save pops cleanly
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

        // Stays on screen and surfaces failure banner
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

        // Restart reload matches what user saw after failure (clear did not persist)
        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.isActive, isTrue);
        expect(restarted.plan.focuses.length, 2);

        // Retry flushes empty plan
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

  group('HomeScreen travel cursor persistence (#134)', () {
    testWidgets(
      'skip travel boost write failure does not advance guidance; restart matches',
      (tester) async {
        final harness = await seedPartialTransport(tester);

        expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
        expect(find.text(AppStrings.travelPrepMeetAction), findsNothing);

        harness.prefs.failWrites.add('travel_focus_v1');
        await tester.tap(find.text(AppStrings.travelPrepSkipAction));
        await tester.pumpAndSettle();

        // Acceptance: don't advance guidance on failure; show failure like placement scope
        expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
        expect(find.text(AppStrings.travelPrepMeetAction), findsNothing);
        expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
        expect(harness.persist.hasWriteFailure, isTrue);
        expect(harness.travel.plan.kanaBoostOn, isNull);

        // Acceptance: restart reload matches what user saw after failure
        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.kanaBoostOn, isNull);

        // Remount from restarted prefs: guidance is still travelPrepBoostAction
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await pumpHarness(
          tester,
          prefs: FakePreferencesService.restarted(harness.prefs),
        );
        expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
        expect(find.text(AppStrings.travelPrepMeetAction), findsNothing);
      },
    );

    testWidgets(
      'finish daily round write failure does not advance guidance; restart matches',
      (tester) async {
        final harness = await seedPartialTransport(tester);

        expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
        await tester.tap(find.text(AppStrings.travelPrepBoostAction));
        await tester.pumpAndSettle();
        expect(find.byType(QuizScreen), findsOneWidget);

        harness.prefs.failWrites.add('travel_focus_v1');
        await _finishDailyRound(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await _popToTravelHome(tester);

        // Acceptance: guidance does not advance on failure
        expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
        expect(find.text(AppStrings.travelPrepMeetAction), findsNothing);
        expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
        expect(harness.persist.hasWriteFailure, isTrue);
        expect(harness.travel.plan.kanaBoostOn, isNull);

        // Acceptance: restart reload matches failure state
        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.kanaBoostOn, isNull);
      },
    );

    testWidgets(
      'skip travel scene meet write failure does not advance guidance; restart matches',
      (tester) async {
        final harness = await seedMeetReady(tester);

        expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);

        harness.prefs.failWrites.add('travel_focus_v1');
        await tester.tap(find.text(AppStrings.travelPrepSkipAction));
        await tester.pumpAndSettle();

        // Guidance stays on meet, does not advance to recall
        expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
        expect(find.text(AppStrings.travelPrepRecallAction), findsNothing);
        expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
        expect(harness.persist.hasWriteFailure, isTrue);
        expect(harness.travel.plan.servedOn[TravelSceneId.transport], isNull);

        // Restart reload matches
        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.servedOn[TravelSceneId.transport], isNull);
      },
    );

    testWidgets(
      'finish travel scene meet write failure does not advance guidance; restart matches',
      (tester) async {
        final harness = await seedMeetReady(tester);

        expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
        await tester.tap(find.text(AppStrings.travelPrepMeetAction));
        await tester.pumpAndSettle();
        expect(find.byType(FerryScreen), findsOneWidget);

        harness.prefs.failWrites.add('travel_focus_v1');
        await _finishFerryRound(tester);

        await tester.tap(find.text(AppStrings.done));
        await tester.pumpAndSettle();

        // Guidance stays on transport (unserved), does not advance to clothing
        expect(
          find.widgetWithText(FilledButton, AppStrings.travelPrepListenAction),
          findsOneWidget,
        );
        expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
        expect(harness.persist.hasWriteFailure, isTrue);
        expect(harness.travel.plan.servedOn[TravelSceneId.transport], isNull);

        // Restart reload matches
        final restarted = await TravelFocusRepository.load(
          FakePreferencesService.restarted(harness.prefs),
        );
        expect(restarted.plan.servedOn[TravelSceneId.transport], isNull);
      },
    );
  });
}

Future<void> _finishFerryRound(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    if (find.text(AppStrings.done).evaluate().isNotEmpty) return;
    expect(find.text(AppStrings.ferryShowText), findsOneWidget);
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
  }
  expect(find.text(AppStrings.done), findsOneWidget);
}

Future<void> _finishDailyRound(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump();
    if (find.byType(QuizScreen).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    final canAnswer =
        find.text(AppStrings.iReadUnprompted).evaluate().isNotEmpty ||
        find.text(AppStrings.iReadIt).evaluate().isNotEmpty ||
        find.byType(AnswerOptionButton).evaluate().isNotEmpty;
    if (!canAnswer) {
      await tester.pumpAndSettle();
      if (find.byType(QuizScreen).evaluate().isEmpty) return;
      continue;
    }
    await _answerCurrentDaily(tester);
  }
  await tester.pumpAndSettle();
  expect(
    find.byType(QuizScreen),
    findsNothing,
    reason: 'daily must officially close',
  );
}

Future<void> _answerCurrentDaily(WidgetTester tester) async {
  if (find.text(AppStrings.iReadUnprompted).evaluate().isNotEmpty) {
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return;
  }
  if (find.text(AppStrings.iReadIt).evaluate().isNotEmpty &&
      find.byType(AnswerOptionButton).evaluate().isEmpty) {
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return;
  }
  if (find.byType(AnswerOptionButton).evaluate().isEmpty) {
    await tester.pumpAndSettle();
    return;
  }
  final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
  final labels = tester
      .widgetList<AnswerOptionButton>(find.byType(AnswerOptionButton))
      .map((b) => b.label)
      .toList();
  final question = quiz.items.map((item) => item.question).firstWhere((q) {
    if (!listEquals(q.options, labels)) return false;
    if (q.direction == QuizDirection.soundToKana) {
      return find.text(AppStrings.chooseBySound).evaluate().isNotEmpty;
    }
    return find.text(q.prompt).evaluate().isNotEmpty;
  });
  await tester.tap(
    find.widgetWithText(AnswerOptionButton, question.correctAnswer),
  );
  await tester.pump();
  final next = find.text(AppStrings.continueLabel);
  if (next.evaluate().isNotEmpty) {
    await tester.tap(next);
  } else if (find.text(AppStrings.seeResults).evaluate().isNotEmpty) {
    await tester.tap(find.text(AppStrings.seeResults));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _popToTravelHome(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    final overlayGone =
        find.byType(QuizScreen).evaluate().isEmpty &&
        find.byType(QuizResultScreen).evaluate().isEmpty &&
        find.byType(FerryScreen).evaluate().isEmpty;
    if (overlayGone && find.byType(HomeScreen).evaluate().isNotEmpty) {
      return;
    }
    if (find.text(AppStrings.done).evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text(AppStrings.done));
      await tester.tap(find.text(AppStrings.done));
      await tester.pumpAndSettle();
      continue;
    }
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      continue;
    }
    await tester.pumpAndSettle();
  }
  expect(find.byType(QuizScreen), findsNothing);
  expect(find.byType(QuizResultScreen), findsNothing);
  expect(find.byType(HomeScreen), findsOneWidget);
}
