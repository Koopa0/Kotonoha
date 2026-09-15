// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_viewmodel.dart';
import 'package:kotonoha/ui/placement/placement_scope_viewmodel.dart';
import 'package:kotonoha/ui/travel/travel_focus_viewmodel.dart';

import 'services/fake_preferences_service.dart';
import 'support/restore_recovery_test_support.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'the write outcome did not settle');
}

/// #179: the two persistence faults gate different things on purpose, and
/// until now nothing said so in one place.
///
/// - A **failed write** keeps the answer in memory, the app-scoped owner
///   retries it, and the banner says exactly that (「內容仍留在這次開啟中,
///   可以再試一次。」). Practice is append-only evidence, so it continues.
///   A configuration edit is not: a half-saved travel plan or placement
///   draft changes what later days schedule, so those pause until the
///   write lands.
/// - An **unrecovered restore** means the durable state itself is
///   unconfirmed, so nothing may be written at all — and the banner says
///   that too (「學習進度暫時不能寫入。」). The home holds every learning
///   entry, which is also the only way into the travel and placement
///   editors.
///
/// These probes pin that split. A change that made the home block on a
/// write failure, or that let a settings editor keep writing through one,
/// fails here rather than quietly diverging from the banner's wording.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 6, 10, 12);

  Future<
    ({
      FakePreferencesService prefs,
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
      TravelFocusRepository travel,
      PlacementCheckRepository checks,
      ProgressPersistenceController persistence,
      ProgressRestoreRecoveryController recovery,
    })
  >
  makeApp({bool needsRecovery = false}) async {
    final prefs = FakePreferencesService();
    final kana = await KanaProgressRepository.load(prefs);
    final kanji = await KanjiReadingRepository.load(prefs);
    final words = await WordProgressRepository.load(prefs);
    final travel = await TravelFocusRepository.load(prefs);
    final checks = await PlacementCheckRepository.load(prefs);
    return (
      prefs: prefs,
      kana: kana,
      kanji: kanji,
      words: words,
      travel: travel,
      checks: checks,
      persistence: ProgressPersistenceController(
        kanaFlush: kana.flushPending,
        kanjiFlush: kanji.flushPending,
        wordFlush: words.flushPending,
        placementFlush: checks.flushPending,
        travelFocusFlush: travel.flushPending,
      ),
      recovery: recoveryForRepos(
        prefs: prefs,
        kana: kana,
        kanji: kanji,
        words: words,
        needsRecovery: needsRecovery,
      ),
    );
  }

  HomeViewModel homeOf(
    ({
      FakePreferencesService prefs,
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
      TravelFocusRepository travel,
      PlacementCheckRepository checks,
      ProgressPersistenceController persistence,
      ProgressRestoreRecoveryController recovery,
    })
    app,
  ) => HomeViewModel(
    kana: app.kana,
    words: app.words,
    kanji: app.kanji,
    travel: app.travel,
    persistence: app.persistence,
    recovery: app.recovery,
    clock: () => at,
    rng: Random(0),
  );

  group('a failed write', () {
    test('holds the settings editors but not practice', () async {
      final app = await makeApp();
      app.prefs.failWrites.add(ProgressStoreKeys.learnedUnits);
      app.persistence.trackKana(app.kana.markUnitLearned('hira_row_0'));
      await _settle(() => app.persistence.hasWriteFailure);

      final home = homeOf(app);
      final travel = TravelFocusViewModel(
        focuses: app.travel,
        persistence: app.persistence,
        clock: () => at,
      );
      final placement = PlacementScopeViewModel(
        kana: app.kana,
        checks: app.checks,
        persistence: app.persistence,
        recovery: app.recovery,
      );

      expect(
        home.learningBlocked,
        isFalse,
        reason:
            'practice stopped on a retryable write failure, which the banner '
            'tells the learner is still held in this session',
      );
      expect(
        travel.isBlocked,
        isTrue,
        reason: 'the travel plan kept taking edits through a failed write',
      );
      expect(
        placement.isBlocked,
        isTrue,
        reason: 'the placement draft kept taking edits through a failed write',
      );

      home.dispose();
      travel.dispose();
      placement.dispose();
    });

    test('lets the editors back in once the retry lands', () async {
      final app = await makeApp();
      app.prefs.failWrites.add(ProgressStoreKeys.learnedUnits);
      app.persistence.trackKana(app.kana.markUnitLearned('hira_row_0'));
      await _settle(() => app.persistence.hasWriteFailure);

      app.prefs.failWrites.remove(ProgressStoreKeys.learnedUnits);
      await app.persistence.retry();

      final travel = TravelFocusViewModel(
        focuses: app.travel,
        persistence: app.persistence,
        clock: () => at,
      );
      expect(app.persistence.hasWriteFailure, isFalse);
      expect(
        travel.isBlocked,
        isFalse,
        reason: 'the editor stayed shut after the write it waited on landed',
      );
      travel.dispose();
    });
  });

  group('an unrecovered restore', () {
    test('holds every learning entry, editors included', () async {
      final app = await makeApp(needsRecovery: true);

      final home = homeOf(app);
      final placement = PlacementScopeViewModel(
        kana: app.kana,
        checks: app.checks,
        persistence: app.persistence,
        recovery: app.recovery,
      );

      expect(app.persistence.hasWriteFailure, isFalse);
      expect(
        home.learningBlocked,
        isTrue,
        reason: 'learning ran while the durable state was unconfirmed',
      );
      expect(
        placement.isBlocked,
        isTrue,
        reason: 'the placement draft wrote while a restore needed recovery',
      );

      home.dispose();
      placement.dispose();
    });

    // The travel editor does not read the recovery controller itself; the
    // home route it is reached from refuses to open it. Pinning that here
    // stops the route gate being removed as redundant.
    test('is the home route gate for the travel editor', () async {
      final app = await makeApp(needsRecovery: true);
      final home = homeOf(app);
      final travel = TravelFocusViewModel(
        focuses: app.travel,
        persistence: app.persistence,
        clock: () => at,
      );

      expect(travel.isBlocked, isFalse);
      expect(
        home.learningBlocked,
        isTrue,
        reason:
            'the travel editor has no recovery gate of its own, so the home '
            'entry is the only thing keeping it shut',
      );

      home.dispose();
      travel.dispose();
    });
  });
}
