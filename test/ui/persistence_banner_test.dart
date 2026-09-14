// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// P0-B — the persistence surface, end-to-end through the real app widget
// (KanaLoopApp). These began as the watched-red demonstration (the failure /
// recovery copy was absent on unmodified production); with the app-scoped owner
// and banner wired they are green, and they pin that normal saving stays
// silent. See scratchpad/watched-red-p0b.txt for the pre-implementation red.
//
// Bounded pumps (never pumpAndSettle) so ambient app motion can't stall. The
// learned state is seeded synchronously on the durable layer (fake.seed), so
// the only write is the one the test drives — and it runs entirely under the
// pumped clock, not a lingering real-async tail from runAsync seeding.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_recovery.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:provider/provider.dart';

import '../services/fake_preferences_service.dart';
import '../support/restore_recovery_test_support.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  ProgressPersistenceController ownerFor(
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
  ) {
    return ProgressPersistenceController(
      kanaFlush: kana.flushPending,
      kanjiFlush: kanji.flushPending,
      wordFlush: () async {},
      health: [
        kana.statsHealth,
        kana.learnedUnitsHealth,
        kana.seenUnlocksHealth,
        kanji.statsHealth,
      ],
    );
  }

  Widget appWith(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
    ProgressPersistenceController persistence, {
    ProgressRestoreRecoveryController? recovery,
  }) {
    final effectiveRecovery =
        recovery ??
        recoveryForRepos(prefs: fake, kana: kana, kanji: kanji, words: words);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: persistence,
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: effectiveRecovery,
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    );
  }

  testWidgets('a failed final write raises the calm banner app-wide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fake = FakePreferencesService();
    // Learned あ行 already on disk (no pre-pump writes) → the 詞と句 unlock line
    // shows; the only write the test makes is the dismiss below.
    fake.seed('learned_units_v1', '["hira_row_0"]');
    fake.failWrites.add('seen_unlocks_v1');
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final owner = ownerFor(kana, kanji);

    await tester.pumpWidget(appWith(fake, kana, kanji, words, owner));
    await settle(tester);

    // Dismiss the unlock — call site #6 (markUnlockSeen), whose write fails.
    expect(find.text(AppStrings.unlockWords), findsOneWidget);
    await tester.tap(find.text(AppStrings.unlockDismiss));
    await settle(tester);

    // No next mutation follows; the app-scoped owner surfaces it calmly.
    expect(owner.hasWriteFailure, isTrue);
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
    expect(find.text(AppStrings.persistRetry), findsOneWidget);
  });

  testWidgets(
    'a recovered-at-startup store shows an honest, dismissible notice',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fake = FakePreferencesService();
      // A corrupt primary with no valid last-known-good → recoveryRequired: the
      // progress is temporarily unreadable, the raw is left in place.
      fake.seed('kana_stats_v1', 'not json');
      final kana = await KanaProgressRepository.load(fake);
      final kanji = await KanjiReadingRepository.load(fake);
      final words = await WordProgressRepository.load(fake);

      await tester.pumpWidget(
        appWith(fake, kana, kanji, words, ownerFor(kana, kanji)),
      );
      await settle(tester);

      expect(
        find.text(AppStrings.persistRecoveryRecoveryRequired),
        findsOneWidget,
      );

      // Acknowledged for the session — it folds away.
      await tester.tap(find.text(AppStrings.persistAck));
      await settle(tester);
      expect(
        find.text(AppStrings.persistRecoveryRecoveryRequired),
        findsNothing,
      );
    },
  );

  testWidgets('normal successful saving stays silent', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fake = FakePreferencesService();
    fake.seed('learned_units_v1', '["hira_row_0"]');
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final owner = ownerFor(kana, kanji);

    await tester.pumpWidget(appWith(fake, kana, kanji, words, owner));
    await settle(tester);
    // A successful dismiss write — nothing should ever announce success.
    await tester.tap(find.text(AppStrings.unlockDismiss));
    await settle(tester);

    expect(owner.hasWriteFailure, isFalse);
    expect(find.text(AppStrings.persistFailedLine), findsNothing);
    expect(find.text(AppStrings.persistRetry), findsNothing);
  });

  testWidgets(
    'needsRecovery + unlock dismiss still shows restore recovery banner and retry calls restoreRecovery.retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fake = FakePreferencesService();
      fake.seed('learned_units_v1', '["hira_row_0"]');
      final kana = await KanaProgressRepository.load(fake);
      final kanji = await KanjiReadingRepository.load(fake);
      final words = await WordProgressRepository.load(fake);
      final recovery = _TrackingRestoreRecoveryController(
        recovery: ProgressRestoreRecovery(
          prefs: fake,
          kana: kana,
          kanji: kanji,
          words: words,
        ),
        needsRecovery: true,
      );
      final owner = ownerFor(kana, kanji);

      await tester.pumpWidget(
        appWith(fake, kana, kanji, words, owner, recovery: recovery),
      );
      await settle(tester);

      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);
      expect(find.text(AppStrings.unlockWords), findsOneWidget);

      await tester.tap(find.text(AppStrings.unlockDismiss));
      await settle(tester);

      expect(owner.hasWriteFailure, isTrue);
      expect(find.text(AppStrings.restoreJournalRecoveryLine), findsOneWidget);
      expect(find.text(AppStrings.persistFailedLine), findsNothing);

      expect(recovery.retryCount, 0);
      await tester.tap(find.text(AppStrings.persistRetry));
      await settle(tester);
      expect(recovery.retryCount, 1);
    },
  );
}

class _TrackingRestoreRecoveryController
    extends ProgressRestoreRecoveryController {
  _TrackingRestoreRecoveryController({
    required super.recovery,
    required super.needsRecovery,
  });

  int retryCount = 0;

  @override
  Future<void> retry() {
    retryCount++;
    return super.retry();
  }
}
