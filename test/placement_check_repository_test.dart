// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ao = Lessons.fromKana(kAllKana).firstWhere((l) => l.id == 'hira_row_0');

  test('save then reload keeps only real grades', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await PlacementCheckRepository.load();
    var draft = PlacementCheck.start([ao])!;
    draft = PlacementCheck.record(draft, 'あ', PlacementOutcome.unknown);
    await first.save(draft);

    final reloaded = await PlacementCheckRepository.load();
    expect(reloaded.draft.records.single.kanaId, 'あ');
    expect(reloaded.draft.records.single.outcome, PlacementOutcome.unknown);
    expect(reloaded.draft.pendingKanaIds, isNot(contains('あ')));
    expect(reloaded.draft.pendingKanaIds, contains('い'));
  });

  test('corrupt payload does not invent answers', () async {
    final prefs = FakePreferencesService();
    prefs.seed('placement_check_v1', '{not-json');
    final store = await PlacementCheckRepository.load(prefs);
    expect(store.draft.records, isEmpty);
    expect(store.draft.pendingKanaIds, isEmpty);
    expect(store.health, StoreHealth.recoveryRequired);
  });

  test('discardAfterRestore removes a complete draft from disk', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlacementCheckRepository.load();
    await store.save(PlacementCheck.start([ao])!);
    await store.discardAfterRestore();
    expect(store.draft.hasProgress, isFalse);

    final reloaded = await PlacementCheckRepository.load();
    expect(reloaded.draft.hasProgress, isFalse);
  });

  test('clear removes the in-progress check', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlacementCheckRepository.load();
    await store.save(PlacementCheck.start([ao])!);
    await store.clear();
    expect(store.draft.hasProgress, isFalse);

    final reloaded = await PlacementCheckRepository.load();
    expect(reloaded.draft.hasProgress, isFalse);
  });

  test('hinted exposure survives save then reload', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await PlacementCheckRepository.load();
    var draft = PlacementCheck.start([ao])!;
    draft = PlacementCheck.noteHinted(draft, 'あ');
    await first.save(draft);

    final reloaded = await PlacementCheckRepository.load();
    expect(reloaded.draft.isHinted('あ'), isTrue);
    expect(reloaded.draft.pendingKanaIds.first, 'あ');
    expect(reloaded.draft.records, isEmpty);
  });

  test('a failed write keeps memory; flushPending lands after the platform recovers', () async {
    final fake = FakePreferencesService();
    final store = await PlacementCheckRepository.load(fake);
    var draft = PlacementCheck.start([ao])!;
    draft = PlacementCheck.noteHinted(draft, 'あ');
    fake.failWrites.add('placement_check_v1');
    await expectLater(store.save(draft), throwsA(isA<StoreWriteFailure>()));
    expect(store.draft.isHinted('あ'), isTrue);

    final afterFail = await PlacementCheckRepository.load(
      FakePreferencesService.restarted(fake),
    );
    expect(afterFail.draft.isHinted('あ'), isFalse);
    expect(afterFail.draft.hasProgress, isFalse);

    fake.failWrites.clear();
    await store.flushPending();
    final recovered = await PlacementCheckRepository.load(
      FakePreferencesService.restarted(fake),
    );
    expect(recovered.draft.isHinted('あ'), isTrue);
    expect(recovered.draft.pendingKanaIds.first, 'あ');
  });
}
