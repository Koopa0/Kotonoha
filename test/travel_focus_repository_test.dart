// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save then reload keeps the focuses and the daily cursor', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await TravelFocusRepository.load();
    await first.saveFocuses([
      TravelFocus(scene: TravelSceneId.transport, date: DateTime(2026, 9, 18)),
      const TravelFocus(scene: TravelSceneId.clothing),
    ]);
    await first.markKanaBoost(DateTime(2026, 9, 11, 18));
    await first.markServed(TravelSceneId.transport, DateTime(2026, 9, 11, 19));

    final reloaded = await TravelFocusRepository.load();
    expect(reloaded.plan.focuses.map((f) => f.scene), [
      TravelSceneId.transport,
      TravelSceneId.clothing,
    ]);
    expect(reloaded.plan.focuses.first.date, DateTime(2026, 9, 18));
    expect(reloaded.plan.kanaBoostOn, DateTime(2026, 9, 11));
    expect(
      reloaded.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );
  });

  test('clear removes the plan and a later load stays empty', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TravelFocusRepository.load();
    await store.saveFocuses(const [TravelFocus(scene: TravelSceneId.shrine)]);
    await store.clear();
    expect(store.plan.isActive, isFalse);

    final reloaded = await TravelFocusRepository.load();
    expect(reloaded.plan, TravelFocusPlan.empty);
  });

  test('corrupt payload does not invent a plan', () async {
    final prefs = FakePreferencesService();
    prefs.seed('travel_focus_v1', '{not-json');
    final store = await TravelFocusRepository.load(prefs);
    expect(store.plan, TravelFocusPlan.empty);
    expect(store.health, StoreHealth.recoveryRequired);
  });

  test(
    'mutating plan collections does not change live or durable state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await TravelFocusRepository.load();
      await repo.saveFocuses(const [
        TravelFocus(scene: TravelSceneId.transport),
      ]);
      await repo.markServed(TravelSceneId.transport, DateTime(2026, 9, 14));
      var notifications = 0;
      repo.addListener(() => notifications++);

      expect(repo.plan.focuses.clear, throwsUnsupportedError);
      expect(repo.plan.servedOn.clear, throwsUnsupportedError);
      expect(
        () => repo.plan.focuses.add(
          const TravelFocus(scene: TravelSceneId.clothing),
        ),
        throwsUnsupportedError,
      );
      expect(repo.plan.isActive, isTrue);
      expect(
        repo.plan.servedOn[TravelSceneId.transport],
        DateTime(2026, 9, 14),
      );
      expect(notifications, 0);

      final restarted = await TravelFocusRepository.load();
      expect(restarted.plan, repo.plan);
      expect(restarted.plan.isActive, isTrue);
      expect(
        restarted.plan.servedOn[TravelSceneId.transport],
        DateTime(2026, 9, 14),
      );
    },
  );

  test('legitimate writes still notify and persist the daily cursor', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await TravelFocusRepository.load();
    var notifications = 0;
    repo.addListener(() => notifications++);

    await repo.saveFocuses(const [TravelFocus(scene: TravelSceneId.transport)]);
    await repo.markServed(TravelSceneId.transport, DateTime(2026, 9, 14, 19));
    expect(notifications, 2);
    expect(repo.plan.focuses.single.scene, TravelSceneId.transport);
    expect(repo.plan.servedOn[TravelSceneId.transport], DateTime(2026, 9, 14));

    final restarted = await TravelFocusRepository.load();
    expect(restarted.plan, repo.plan);
  });

  test(
    'a failed write keeps memory; flushPending lands after recovery',
    () async {
      final fake = FakePreferencesService();
      final store = await TravelFocusRepository.load(fake);
      fake.failWrites.add('travel_focus_v1');
      await expectLater(
        store.saveFocuses(const [TravelFocus(scene: TravelSceneId.transport)]),
        throwsA(isA<StoreWriteFailure>()),
      );
      expect(store.plan.focuses.single.scene, TravelSceneId.transport);

      final afterFail = await TravelFocusRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(afterFail.plan.isActive, isFalse);

      fake.failWrites.clear();
      await store.flushPending();
      final afterFlush = await TravelFocusRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(afterFlush.plan.focuses.single.scene, TravelSceneId.transport);
    },
  );

  test('markKanaBoost write failure keeps memory; flushPending lands after recovery', () async {
    final fake = FakePreferencesService();
    final store = await TravelFocusRepository.load(fake);
    await store.saveFocuses(const [
      TravelFocus(scene: TravelSceneId.transport),
    ]);

    fake.failWrites.add('travel_focus_v1');
    await expectLater(
      store.markKanaBoost(DateTime(2026, 9, 11, 12)),
      throwsA(isA<StoreWriteFailure>()),
    );
    expect(store.plan.kanaBoostOn, DateTime(2026, 9, 11));

    final afterFail = await TravelFocusRepository.load(
      FakePreferencesService.restarted(fake),
    );
    expect(afterFail.plan.kanaBoostOn, isNull);

    fake.failWrites.clear();
    await store.flushPending();
    final afterFlush = await TravelFocusRepository.load(
      FakePreferencesService.restarted(fake),
    );
    expect(afterFlush.plan.kanaBoostOn, DateTime(2026, 9, 11));
  });

  test(
    'markServed write failure keeps memory; flushPending lands after recovery',
    () async {
      final fake = FakePreferencesService();
      final store = await TravelFocusRepository.load(fake);
      await store.saveFocuses(const [
        TravelFocus(scene: TravelSceneId.transport),
      ]);

      fake.failWrites.add('travel_focus_v1');
      await expectLater(
        store.markServed(TravelSceneId.transport, DateTime(2026, 9, 11, 12)),
        throwsA(isA<StoreWriteFailure>()),
      );
      expect(
        store.plan.servedOn[TravelSceneId.transport],
        DateTime(2026, 9, 11),
      );

      final afterFail = await TravelFocusRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(afterFail.plan.servedOn[TravelSceneId.transport], isNull);

      fake.failWrites.clear();
      await store.flushPending();
      final afterFlush = await TravelFocusRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(
        afterFlush.plan.servedOn[TravelSceneId.transport],
        DateTime(2026, 9, 11),
      );
    },
  );
}
