// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_exporter.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';
import '../services/fake_snapshot_file_port.dart';
import '../support/restore_recovery_test_support.dart';

/// The one seam #148 moves: the restorer no longer reaches into the UI's
/// recovery controller. The progress screen that issued the restore hands
/// the outcome to the app-scoped owner — only when a transaction actually
/// ran — and always gets its button back, so an in-session restore that
/// leaves a blocking journal still raises the banner, a cancelled pick never
/// touches the platform, and a platform read that throws cannot strand the
/// card in its busy state.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A backup from repositories on the shared_preferences mock: its writes
  /// complete without timers, so awaiting them under the widget test's fake
  /// clock is safe (a FakePreferencesService write would park forever).
  Future<String> backupFromFreshRepos() async {
    final kana = await KanaProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    final words = await WordProgressRepository.load();
    await kana.markUnitLearned('hira_row_0');
    return ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).exportEncoded(createdAt: DateTime.utc(2026, 9, 14, 9));
  }

  /// Bounded pumps, never pumpAndSettle: the screen's ambient motion would
  /// stall it. FakePreferencesService parks every write on a zero-length
  /// timer and the restore transaction chains dozens of them; each pump
  /// drains what is due, and the dialog's transitions need real frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  OutlinedButton restoreButton(WidgetTester tester) => tester.widget(
    find.widgetWithText(OutlinedButton, AppStrings.restoreAction),
  );

  /// Mounts the production progress screen under the app-level banner with
  /// the same owners bootstrap wires: repositories on [fake], the
  /// persistence owner, the recovery controller, exporter and restorer.
  Future<
    ({
      KanaProgressRepository kana,
      WordProgressRepository words,
      ProgressRestoreRecoveryController recovery,
    })
  >
  pumpProgress(
    WidgetTester tester, {
    required FakePreferencesService fake,
    required FakeSnapshotFilePort files,
  }) async {
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final capture = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
      prefs: fake,
    );
    final recovery = recoveryForRepos(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
    );
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
            ),
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<ProgressSnapshotExporter>.value(
            value: ProgressSnapshotExporter(
              capture: capture,
              files: FakeSnapshotFilePort(),
            ),
          ),
          Provider<ProgressSnapshotRestorer>.value(
            value: ProgressSnapshotRestorer(
              capture: capture,
              transaction: ProgressRestoreTransaction(
                prefs: fake,
                kana: kana,
                kanji: kanji,
                words: words,
              ),
              files: files,
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              PersistenceBanner(child: child ?? const SizedBox.shrink()),
          home: const ProgressScreen(),
        ),
      ),
    );
    await settle(tester);
    expect(find.text(AppStrings.restoreJournalRecoveryLine), findsNothing);
    return (kana: kana, words: words, recovery: recovery);
  }

  Future<void> tapRestore(WidgetTester tester) async {
    await tester.ensureVisible(find.text(AppStrings.restoreAction));
    await tester.tap(find.text(AppStrings.restoreAction));
    await settle(tester);
  }

  testWidgets(
    'in-session restore that leaves a blocking journal raises the banner; retry clears it',
    (tester) async {
      final backup = await backupFromFreshRepos();
      // Seeded, not written: a fake write awaited before the first pump
      // would never complete under the fake clock.
      final fake = FakePreferencesService()
        ..seed(ProgressStoreKeys.learnedUnits, '["keep_me"]');
      // Apply fails on the third primary; the rollback of learned_units_v1
      // (its second write) fails too, so the journal stays on disk and
      // blocks learning.
      fake.failWriteOnAttempt[ProgressStoreKeys.seenUnlocks] = {1};
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {2};
      final t = await pumpProgress(
        tester,
        fake: fake,
        files: FakeSnapshotFilePort()..pickContents = backup,
      );
      expect(t.kana.learnedUnits, contains('keep_me'));

      await tapRestore(tester);
      expect(find.text(AppStrings.restoreConfirmYes), findsOneWidget);
      await tester.tap(find.text(AppStrings.restoreConfirmYes));
      await settle(tester);

      expect(tester.takeException(), isNull);
      // The card reports the journal block (it outranks the failure copy);
      // the app-level banner is what the learner acts on.
      expect(find.text(AppStrings.restoreBlocked), findsOneWidget);
      expect(find.text(AppStrings.restoreRestoring), findsNothing);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
      expect(t.recovery.needsRecovery, isTrue);
      expect(t.words.isRestoreJournalBlocked, isTrue);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);

      fake.failWriteOnAttempt.clear();
      await tester.tap(find.text(AppStrings.persistRetry));
      await settle(tester);

      expect(t.recovery.needsRecovery, isFalse);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsNothing);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(t.kana.learnedUnits, contains('keep_me'));
      expect(t.words.isRestoreJournalBlocked, isFalse);
      expect(restoreButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'cancelled pick never syncs the platform and hands the button back',
    (tester) async {
      final fake = FakePreferencesService()..throwReloads = true;
      final t = await pumpProgress(
        tester,
        fake: fake,
        files: FakeSnapshotFilePort()..nextPick = SnapshotPickOutcome.cancelled,
      );

      await tapRestore(tester);

      // No transaction ran, so no platform read was needed — a reload that
      // would have thrown never happened, and nothing escaped the handler.
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.restoreRestoring), findsNothing);
      expect(restoreButton(tester).onPressed, isNotNull);
      expect(find.text(AppStrings.restoreFailed), findsNothing);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsNothing);
      expect(t.recovery.needsRecovery, isFalse);
      expect(t.words.isRestoreJournalBlocked, isFalse);
    },
  );

  testWidgets(
    'a platform read that throws after the transaction still frees the button',
    (tester) async {
      final backup = await backupFromFreshRepos();
      final fake = FakePreferencesService()..throwReloads = true;
      final t = await pumpProgress(
        tester,
        fake: fake,
        files: FakeSnapshotFilePort()..pickContents = backup,
      );

      await tapRestore(tester);
      expect(find.text(AppStrings.restoreConfirmYes), findsOneWidget);
      await tester.tap(find.text(AppStrings.restoreConfirmYes));
      await settle(tester);

      // The transaction's own reload threw before staging, so nothing was
      // written; the sync then fell back to the cached verdict (no journal)
      // instead of throwing — the card reports the failure, the button is
      // live again, and no banner or blocking was invented.
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.restoreRestoring), findsNothing);
      expect(find.text(AppStrings.restoreFailed), findsOneWidget);
      expect(restoreButton(tester).onPressed, isNotNull);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsNothing);
      expect(t.recovery.needsRecovery, isFalse);
      expect(t.words.isRestoreJournalBlocked, isFalse);

      // Once the platform reads again, the same button retries.
      fake.throwReloads = false;
      await tapRestore(tester);
      await tester.tap(find.text(AppStrings.restoreConfirmYes));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.restoreRestored), findsOneWidget);
      expect(t.kana.learnedUnits, contains('hira_row_0'));
    },
  );
}
