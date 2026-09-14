// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/travel/travel_focus_viewmodel.dart';

import 'services/fake_preferences_service.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'did not settle');
}

/// Reads the travel-focus editor ViewModel's contract without pumping a
/// widget: the draft and its dates, the two-focus limit, save / clear with
/// their in-flight and failure state, and the write block.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);

  Future<
    ({
      TravelFocusViewModel vm,
      TravelFocusRepository focuses,
      ProgressPersistenceController persistence,
      FakePreferencesService fake,
    })
  >
  makeVm({List<TravelFocus> retained = const []}) async {
    final fake = FakePreferencesService();
    final focuses = await TravelFocusRepository.load(fake);
    if (retained.isNotEmpty) await focuses.saveFocuses(retained);
    final persistence = ProgressPersistenceController(
      kanaFlush: () async {},
      kanjiFlush: () async {},
      wordFlush: () async {},
      travelFocusFlush: focuses.flushPending,
    );
    final vm = TravelFocusViewModel(
      focuses: focuses,
      persistence: persistence,
      clock: () => now,
    );
    return (vm: vm, focuses: focuses, persistence: persistence, fake: fake);
  }

  test('opens on a copy of the retained plan', () async {
    final t = await makeVm(
      retained: [
        TravelFocus(scene: TravelSceneId.transport, date: DateTime(2026, 10)),
      ],
    );
    expect(t.vm.draft, hasLength(1));
    expect(t.vm.isSelected(TravelSceneId.transport), isTrue);
    expect(t.vm.dateOf(TravelSceneId.transport), DateTime(2026, 10));
    expect(t.vm.initialDateFor(TravelSceneId.transport), DateTime(2026, 10));
    expect(t.vm.isSelected(TravelSceneId.hotel), isFalse);
    expect(
      t.vm.initialDateFor(TravelSceneId.hotel),
      TravelFocusPlan.dayOf(now),
    );
    expect(t.vm.showsLimitHint, isFalse);
    expect(t.vm.isSaving, isFalse);
    expect(t.vm.isBlocked, isFalse);
    expect(t.vm.now, now);
    t.vm.dispose();
  });

  test('toggling adds, removes, and refuses a third focus', () async {
    final t = await makeVm();
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.toggle(TravelSceneId.transport);
    t.vm.toggle(TravelSceneId.clothing);
    expect(t.vm.draft.map((f) => f.scene), [
      TravelSceneId.transport,
      TravelSceneId.clothing,
    ]);
    t.vm.toggle(TravelSceneId.hotel);
    expect(t.vm.isSelected(TravelSceneId.hotel), isFalse);
    expect(t.vm.showsLimitHint, isTrue);
    t.vm.toggle(TravelSceneId.transport);
    expect(t.vm.isSelected(TravelSceneId.transport), isFalse);
    expect(t.vm.showsLimitHint, isFalse);
    expect(notifications, 4);
    // Nothing is written until save.
    expect(t.focuses.plan.focuses, isEmpty);
    t.vm.dispose();
  });

  test('dates belong to retained focuses only', () async {
    final t = await makeVm();
    t.vm.setDate(TravelSceneId.transport, DateTime(2026, 11, 3));
    expect(t.vm.isSelected(TravelSceneId.transport), isFalse);
    t.vm.toggle(TravelSceneId.transport);
    t.vm.setDate(TravelSceneId.transport, DateTime(2026, 11, 3));
    expect(t.vm.dateOf(TravelSceneId.transport), DateTime(2026, 11, 3));
    t.vm.clearDate(TravelSceneId.transport);
    expect(t.vm.dateOf(TravelSceneId.transport), isNull);
    expect(t.vm.isSelected(TravelSceneId.transport), isTrue);
    t.vm.dispose();
  });

  test('save writes the draft and reports the landed write', () async {
    final t = await makeVm();
    t.vm.toggle(TravelSceneId.transport);
    t.vm.setDate(TravelSceneId.transport, DateTime(2026, 12, 24));
    var sawSaving = false;
    t.vm.addListener(() => sawSaving |= t.vm.isSaving);
    expect(await t.vm.save(), isTrue);
    expect(sawSaving, isTrue);
    expect(t.vm.isSaving, isFalse);
    expect(t.persistence.hasWriteFailure, isFalse);
    final reloaded = await TravelFocusRepository.load(
      FakePreferencesService.restarted(t.fake),
    );
    final focus = reloaded.plan.focuses.single;
    expect(focus.scene, TravelSceneId.transport);
    expect(focus.date, DateTime(2026, 12, 24));
    t.vm.dispose();
  });

  test('clear empties the plan and reports the landed write', () async {
    final t = await makeVm(
      retained: const [TravelFocus(scene: TravelSceneId.shrine)],
    );
    expect(await t.vm.clear(), isTrue);
    expect(t.focuses.plan.focuses, isEmpty);
    final reloaded = await TravelFocusRepository.load(
      FakePreferencesService.restarted(t.fake),
    );
    expect(reloaded.plan.focuses, isEmpty);
    t.vm.dispose();
  });

  test('a failed save keeps the editor open and blocks edits', () async {
    final t = await makeVm();
    t.vm.toggle(TravelSceneId.transport);
    t.fake.failWrites.add('travel_focus_v1');
    expect(await t.vm.save(), isFalse);
    expect(t.vm.isSaving, isFalse);
    await _settle(() => t.persistence.hasWriteFailure);
    expect(t.vm.isBlocked, isTrue);

    // The banner owns the failure: nothing else may change until retry.
    t.vm.toggle(TravelSceneId.clothing);
    t.vm.setDate(TravelSceneId.transport, DateTime(2026, 12));
    expect(t.vm.isSelected(TravelSceneId.clothing), isFalse);
    expect(t.vm.dateOf(TravelSceneId.transport), isNull);
    expect(await t.vm.save(), isFalse);
    expect(await t.vm.clear(), isFalse);

    t.fake.failWrites.clear();
    await t.persistence.retry();
    expect(t.vm.isBlocked, isFalse);
    expect(await t.vm.save(), isTrue);
    t.vm.dispose();
  });

  test('a second submit while a write is pending is refused', () async {
    final t = await makeVm();
    t.vm.toggle(TravelSceneId.transport);
    final first = t.vm.save();
    expect(t.vm.isSaving, isTrue);
    expect(t.vm.isBlocked, isTrue);
    expect(await t.vm.clear(), isFalse); // refused while the save is in flight
    t.vm.toggle(TravelSceneId.hotel); // and so are edits
    expect(t.vm.isSelected(TravelSceneId.hotel), isFalse);
    expect(await first, isTrue);
    expect(t.focuses.plan.focuses.single.scene, TravelSceneId.transport);
    t.vm.dispose();
  });
}
