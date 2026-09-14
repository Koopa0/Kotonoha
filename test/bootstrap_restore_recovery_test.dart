// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Formal bootstrap probes for restore-journal recovery: production provider
// wiring, startup banner, and learning isolation through [bootstrap].

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_restore_placement_discard.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/main.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> testBootstrap({PreferencesService? prefs}) {
    return bootstrap(
      prefs: prefs,
      speech: const SilentSpeechService(),
      analytics: InMemoryAnalyticsLog(),
    );
  }

  Future<void> mountBootstrap(
    WidgetTester tester, {
    PreferencesService? prefs,
  }) async {
    await tester.pumpWidget(
      await testBootstrap(prefs: prefs),
      duration: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Seeds shared_preferences with a corrupt journal so startup recovery keeps
  /// blocking without learned progress (avoids a widget-test scheduling loop
  /// that only reproduces with FakePreferences + learned rows).
  Future<void> seedSharedPrefsBlockingJournal() async {
    SharedPreferences.setMockInitialValues({
      ProgressRestoreJournal.journalKey: 'not json',
    });
  }

  /// Learned あ行 plus corrupt journal — exercises the same durable state as a
  /// real device with existing progress, without FakePreferences scheduling
  /// loops in widget tests.
  Future<void> seedSharedPrefsBlockingJournalWithLearnedProgress() async {
    SharedPreferences.setMockInitialValues({
      'learned_units_v1': '["hira_row_0"]',
      'kana_stats_v1':
          '{"あ":{"s":3,"c":2,"w":1},"い":{"s":3,"c":2,"w":1},'
          '"う":{"s":3,"c":2,"w":1},"え":{"s":3,"c":2,"w":1},'
          '"お":{"s":3,"c":2,"w":1}}',
      ProgressRestoreJournal.journalKey: 'not json',
    });
  }

  testWidgets(
    'placement discard pending clears stale draft without blocking bootstrap',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'learned_units_v1': '["hira_row_1"]',
        'placement_check_v1':
            '{"records":[{"kanaId":"あ","outcome":"independent"}],'
            '"pendingKanaIds":[],"scopeLessonIds":["hira_row_0"]}',
        ProgressRestorePlacementDiscard.pendingKey: 'pending',
      });
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await mountBootstrap(tester);

      expect(find.text(AppStrings.appTitle), findsOneWidget);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsNothing);
      final root = tester.element(find.text(AppStrings.appTitle));
      final checks = root.read<PlacementCheckRepository>();
      final kana = root.read<KanaProgressRepository>();
      expect(checks.draft.hasProgress, isFalse);
      expect(kana.learnedUnits, {'hira_row_1'});
    },
  );

  testWidgets('bootstrap pumps with production restore-recovery provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await mountBootstrap(tester);

    expect(find.text(AppStrings.appTitle), findsOneWidget);
    expect(find.text(AppStrings.restoreJournalRecoveryLine), findsNothing);
  });

  testWidgets('blocking journal shows recovery banner on bootstrap', (
    tester,
  ) async {
    await seedSharedPrefsBlockingJournal();
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await mountBootstrap(tester);

    expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);
    expect(find.text(AppStrings.persistRetry), findsOneWidget);
  });

  testWidgets('blocking journal keeps home learning entry isolated', (
    tester,
  ) async {
    await seedSharedPrefsBlockingJournal();
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await mountBootstrap(tester);

    await tester.tap(find.text(AppStrings.continueLearning));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('あ行'), findsNothing);
    expect(find.text(AppStrings.learnHiragana), findsOneWidget);
    expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);
  });

  testWidgets(
    'blocking journal with learned progress isolates quiet practice quiz',
    (tester) async {
      await seedSharedPrefsBlockingJournalWithLearnedProgress();
      final analytics = InMemoryAnalyticsLog();
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        await bootstrap(
          speech: const SilentSpeechService(),
          analytics: analytics,
        ),
        duration: Duration.zero,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final root = tester.element(find.text(AppStrings.appTitle));
      final recovery = root.read<ProgressRestoreRecoveryController>();
      final liveKana = root.read<KanaProgressRepository>();
      expect(recovery.needsRecovery, isTrue);
      final statsBefore = liveKana.stats.values.fold<int>(
        0,
        (sum, stat) => sum + stat.correctCount,
      );
      expect(statsBefore, 10);
      expect(liveKana.isUnitLearned('hira_row_0'), isTrue);
      expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);

      await tester.tap(find.text(AppStrings.quietPracticeAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(QuizScreen), findsNothing);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);
      final statsAfter = liveKana.stats.values.fold<int>(
        0,
        (sum, stat) => sum + stat.correctCount,
      );
      expect(statsAfter, statsBefore);
      expect(await analytics.count(), 0);
    },
  );
}
