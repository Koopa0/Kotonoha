// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/placement/placement_result_viewmodel.dart';

import 'services/fake_preferences_service.dart';
import 'support/restore_recovery_test_support.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 64 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'did not settle');
}

/// Reads the placement results ViewModel's contract without pumping a
/// widget: the summary, the row-then-draft apply order, that a failed or
/// blocked write keeps the draft and finishes the pair after retry, and
/// that the apply never runs twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every kana of [row] graded [outcome].
  PlacementDraft graded(Lesson row, PlacementOutcome outcome) {
    var draft = PlacementCheck.start([row])!;
    for (final id in row.kana.map((k) => k.id)) {
      draft = PlacementCheck.record(draft, id, outcome);
    }
    return draft;
  }

  Future<
    ({
      PlacementResultViewModel vm,
      KanaProgressRepository kana,
      PlacementCheckRepository checks,
      ProgressPersistenceController persistence,
      ProgressRestoreRecoveryController recovery,
      FakePreferencesService fake,
      Lesson row,
    })
  >
  makeVm({
    PlacementOutcome outcome = PlacementOutcome.independent,
    bool needsRecovery = false,
    Set<String> failWrites = const {},
  }) async {
    final fake = FakePreferencesService();
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final checks = await PlacementCheckRepository.load(fake);
    final row = Lessons.fromKana(kana.allKana).first;
    final draft = graded(row, outcome);
    await checks.save(draft);
    fake.failWrites.addAll(failWrites);
    final persistence = ProgressPersistenceController(
      kanaFlush: kana.flushPending,
      kanjiFlush: kanji.flushPending,
      wordFlush: words.flushPending,
      placementFlush: checks.flushPending,
    );
    final recovery = recoveryForRepos(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
      needsRecovery: needsRecovery,
    );
    final vm = PlacementResultViewModel(
      draft: draft,
      checks: checks,
      kana: kana,
      persistence: persistence,
      recovery: recovery,
      clock: () => DateTime(2026, 9, 11, 12),
    );
    return (
      vm: vm,
      kana: kana,
      checks: checks,
      persistence: persistence,
      recovery: recovery,
      fake: fake,
      row: row,
    );
  }

  test('summarizes the graded rows without applying anything yet', () async {
    final t = await makeVm();
    expect(t.vm.summary.independent, t.row.kana);
    expect(t.vm.summary.prompted, isEmpty);
    expect(t.vm.summary.unknown, isEmpty);
    expect(t.vm.summary.confirmedLessons.map((l) => l.id), [t.row.id]);
    expect(t.vm.summary.hasGaps, isFalse);
    expect(t.vm.firstGap, isNull);
    expect(t.vm.isApplied, isFalse);
    expect(t.vm.isAwaitingRetry, isFalse);
    expect(t.vm.isDailyReady, isFalse);
    expect(t.kana.isUnitLearned(t.row.id), isFalse);
    t.vm.dispose();
  });

  test(
    'apply marks the confirmed row learned, then clears the draft',
    () async {
      final t = await makeVm();
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      await t.vm.applyConfirmed();
      expect(t.vm.isApplied, isTrue);
      expect(t.kana.isUnitLearned(t.row.id), isTrue);
      await _settle(() => !t.checks.draft.hasProgress);
      expect(t.persistence.hasWriteFailure, isFalse);
      expect(notifications, greaterThan(0));

      final reloadedKana = await KanaProgressRepository.load(
        FakePreferencesService.restarted(t.fake),
      );
      expect(reloadedKana.isUnitLearned(t.row.id), isTrue);
      await t.checks.flushPending();
      final reloadedChecks = await PlacementCheckRepository.load(
        FakePreferencesService.restarted(t.fake),
      );
      expect(reloadedChecks.draft.hasProgress, isFalse);

      // A second visit of the frame is a no-op.
      final before = notifications;
      await t.vm.applyConfirmed();
      expect(notifications, before);
      t.vm.dispose();
    },
  );

  test('gaps confirm nothing; the draft is still cleared', () async {
    final t = await makeVm(outcome: PlacementOutcome.unknown);
    expect(t.vm.summary.unknown, t.row.kana);
    expect(t.vm.summary.confirmedLessons, isEmpty);
    expect(t.vm.summary.hasGaps, isTrue);
    expect(t.vm.firstGap?.id, t.row.id);
    await t.vm.applyConfirmed();
    expect(t.kana.isUnitLearned(t.row.id), isFalse);
    await _settle(() => !t.checks.draft.hasProgress);
    t.vm.dispose();
  });

  test(
    'a failed row write keeps the draft and finishes the pair after retry',
    () async {
      final t = await makeVm(failWrites: {'learned_units_v1'});
      await t.vm.applyConfirmed();
      expect(t.vm.isApplied, isFalse);
      expect(t.vm.isAwaitingRetry, isTrue);
      expect(t.kana.isUnitLearned(t.row.id), isTrue); // in memory only
      expect(t.checks.draft.hasProgress, isTrue); // kept for cold start
      await _settle(() => t.persistence.hasWriteFailure);

      t.fake.failWrites.clear();
      await t.persistence.retry();
      await _settle(() => t.vm.isApplied);
      expect(t.vm.isAwaitingRetry, isFalse);
      await _settle(() => !t.checks.draft.hasProgress);
      final reloaded = await KanaProgressRepository.load(
        FakePreferencesService.restarted(t.fake),
      );
      expect(reloaded.isUnitLearned(t.row.id), isTrue);
      t.vm.dispose();
    },
  );

  test('a restore that needs recovery parks the apply', () async {
    final t = await makeVm(needsRecovery: true);
    await t.vm.applyConfirmed();
    expect(t.vm.isApplied, isFalse);
    expect(t.vm.isAwaitingRetry, isTrue);
    expect(t.kana.isUnitLearned(t.row.id), isFalse);
    expect(t.checks.draft.hasProgress, isTrue);
    await t.vm.applyConfirmed(); // still parked, still once
    expect(t.vm.isAwaitingRetry, isTrue);
    t.vm.dispose();
  });

  test(
    'a pending learned write finishing after leave does not clear a new draft',
    () async {
      final t = await makeVm();
      final nextRow = Lessons.fromKana(t.kana.allKana)
          .firstWhere((l) => l.id != t.row.id);
      final learnedGate = PlatformGate();
      t.fake.writeGates['learned_units_v1'] = learnedGate;

      var notificationsAfterLeave = 0;
      var left = false;
      t.vm.addListener(() {
        if (left) notificationsAfterLeave++;
      });
      final apply = t.vm.applyConfirmed();
      await learnedGate.entered;

      left = true;
      t.vm.dispose();
      final nextDraft = PlacementCheck.start([nextRow])!;
      await t.checks.save(nextDraft);
      expect(t.checks.draft.lessonIds, [nextRow.id]);

      learnedGate.release();
      await apply;
      await _settle(() => t.persistence.hasWriteFailure == false);

      expect(t.checks.draft.lessonIds, [nextRow.id]);
      expect(t.checks.draft.hasProgress, isTrue);
      expect(notificationsAfterLeave, 0);
    },
  );
}
