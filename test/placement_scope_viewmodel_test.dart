// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/placement/placement_scope_viewmodel.dart';

import 'services/fake_preferences_service.dart';
import 'support/restore_recovery_test_support.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the placement scope ViewModel's contract without pumping a widget:
/// the catalog and selection, start / resume / discard of the recoverable
/// draft, the on-disk gate before a check opens, and the write block.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
    ({
      PlacementScopeViewModel vm,
      KanaProgressRepository kana,
      PlacementCheckRepository checks,
      ProgressPersistenceController persistence,
      ProgressRestoreRecoveryController recovery,
      FakePreferencesService fake,
    })
  >
  makeVm({bool needsRecovery = false}) async {
    final fake = FakePreferencesService();
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final checks = await PlacementCheckRepository.load(fake);
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
    final vm = PlacementScopeViewModel(
      kana: kana,
      checks: checks,
      persistence: persistence,
      recovery: recovery,
    );
    return (
      vm: vm,
      kana: kana,
      checks: checks,
      persistence: persistence,
      recovery: recovery,
      fake: fake,
    );
  }

  test('opens with the catalog split by script and nothing named', () async {
    final t = await makeVm();
    expect(t.vm.catalog, isNotEmpty);
    expect(t.vm.hiragana.every((l) => l.script == KanaScript.hiragana), isTrue);
    expect(t.vm.katakana.every((l) => l.script == KanaScript.katakana), isTrue);
    expect(t.vm.hiragana.length + t.vm.katakana.length, t.vm.catalog.length);
    expect(t.vm.canStart, isFalse);
    expect(t.vm.canResume, isFalse);
    expect(t.vm.isBlocked, isFalse);
    expect(t.vm.resume(), isNull);
    t.vm.dispose();
  });

  test('naming a row enables start; un-naming it disables start', () async {
    final t = await makeVm();
    final row = t.vm.hiragana.first;
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.setSelected(row.id, selected: true);
    expect(t.vm.isSelected(row.id), isTrue);
    expect(t.vm.canStart, isTrue);
    t.vm.setSelected(row.id, selected: true); // already named — silent
    expect(notifications, 1);
    t.vm.setSelected(row.id, selected: false);
    expect(t.vm.canStart, isFalse);
    expect(notifications, 2);
    t.vm.dispose();
  });

  test('start saves the draft on disk and hands it back', () async {
    final t = await makeVm();
    final row = t.vm.hiragana.first;
    t.vm.setSelected(row.id, selected: true);
    final draft = await t.vm.startNew();
    expect(draft, isNotNull);
    expect(draft!.lessonIds, [row.id]);
    expect(draft.pendingKanaIds, row.kana.map((k) => k.id).toList());
    expect(t.checks.draft.hasProgress, isTrue);
    expect(t.vm.canResume, isTrue);
    expect(t.vm.isResumeFinished, isFalse);
    expect(t.vm.resume(), PlacementResume.check);
    expect(t.persistence.hasWriteFailure, isFalse);
    final reloaded = await PlacementCheckRepository.load(
      FakePreferencesService.restarted(t.fake),
    );
    expect(reloaded.draft.pendingKanaIds, draft.pendingKanaIds);
    t.vm.dispose();
  });

  test('start with nothing named opens nothing', () async {
    final t = await makeVm();
    expect(await t.vm.startNew(), isNull);
    expect(t.checks.draft.hasProgress, isFalse);
    t.vm.dispose();
  });

  test('a failed draft save keeps the learner here', () async {
    final t = await makeVm();
    t.fake.failWrites.add(PlacementCheckRepository.storageKey);
    t.vm.setSelected(t.vm.hiragana.first.id, selected: true);
    expect(await t.vm.startNew(), isNull);
    await _settle(() => t.persistence.hasWriteFailure);
    expect(t.vm.isBlocked, isTrue);
    expect(t.vm.canStart, isFalse);
    t.vm.dispose();
  });

  test('a finished draft resumes to the results', () async {
    final t = await makeVm();
    final row = t.vm.hiragana.first;
    var draft = PlacementCheck.start([row])!;
    for (final id in row.kana.map((k) => k.id)) {
      draft = PlacementCheck.record(
        draft,
        id,
        PlacementCheck.outcomeFor(correct: true, unprompted: true),
      );
    }
    await t.checks.save(draft);
    expect(t.vm.canResume, isTrue);
    expect(t.vm.isResumeFinished, isTrue);
    expect(t.vm.resume(), PlacementResume.results);
    t.vm.dispose();
  });

  test('discard clears the draft and stays', () async {
    final t = await makeVm();
    await t.checks.save(PlacementCheck.start([t.vm.hiragana.first])!);
    expect(t.vm.canResume, isTrue);
    await t.vm.discardAndStay();
    expect(t.checks.draft.hasProgress, isFalse);
    expect(t.vm.canResume, isFalse);
    expect(t.vm.resume(), isNull);
    t.vm.dispose();
  });

  test('a restore that needs recovery blocks every write', () async {
    final t = await makeVm(needsRecovery: true);
    expect(t.vm.isBlocked, isTrue);
    t.vm.setSelected(t.vm.hiragana.first.id, selected: true);
    expect(t.vm.canStart, isFalse);
    expect(await t.vm.startNew(), isNull);
    expect(t.vm.resume(), isNull);
    t.vm.dispose();
  });

  test('re-notifies when an owner changes', () async {
    final t = await makeVm();
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    await t.kana.markUnitLearned(t.vm.hiragana.first.id);
    expect(t.vm.isUnitLearned(t.vm.hiragana.first.id), isTrue);
    expect(notifications, greaterThan(0));
    final afterKana = notifications;
    await t.checks.save(PlacementCheck.start([t.vm.hiragana.last])!);
    expect(notifications, greaterThan(afterKana));
    t.vm.dispose();
  });
}
