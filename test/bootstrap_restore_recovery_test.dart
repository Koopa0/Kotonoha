// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Formal bootstrap probes for restore-journal recovery: production provider
// wiring, startup banner, and learning isolation through [bootstrap].

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/main.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
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
}
