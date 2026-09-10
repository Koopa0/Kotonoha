// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
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

  test('clear removes the in-progress check', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PlacementCheckRepository.load();
    await store.save(PlacementCheck.start([ao])!);
    await store.clear();
    expect(store.draft.hasProgress, isFalse);

    final reloaded = await PlacementCheckRepository.load();
    expect(reloaded.draft.hasProgress, isFalse);
  });
}
