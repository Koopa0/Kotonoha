// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';

void main() {
  test('withFocuses keeps at most two unique scenes in pick order', () {
    final plan = TravelFocusPlan.empty.withFocuses([
      const TravelFocus(scene: TravelSceneId.transport),
      const TravelFocus(scene: TravelSceneId.clothing),
      const TravelFocus(scene: TravelSceneId.shrine),
      const TravelFocus(scene: TravelSceneId.transport),
    ]);
    expect(plan.focuses.map((f) => f.scene), [
      TravelSceneId.transport,
      TravelSceneId.clothing,
    ]);
  });

  test('fromJson drops unknown scenes and extra rows, never invents dates', () {
    final plan = TravelFocusPlan.fromJson({
      'focuses': [
        {'scene': 'transport', 'date': '2026-10-21'},
        {'scene': 'unknown'},
        {'scene': 'clothing', 'date': 'not-a-day'},
        {'scene': 'shrine'},
      ],
      'kanaBoostOn': 'bad',
      'served': {'transport': '2026-09-11', 'nope': '2026-09-11'},
    });
    expect(plan.focuses, [
      TravelFocus(scene: TravelSceneId.transport, date: DateTime(2026, 10, 21)),
      const TravelFocus(scene: TravelSceneId.clothing),
    ]);
    expect(plan.kanaBoostOn, isNull);
    expect(plan.servedOn[TravelSceneId.transport], DateTime(2026, 9, 11));
    expect(plan.servedOn.containsKey(TravelSceneId.clothing), isFalse);
  });

  test('clearing the plan forgets the choice and leaves no cursor', () {
    final plan = TravelFocusPlan.empty
        .withFocuses(const [TravelFocus(scene: TravelSceneId.transport)])
        .markKanaBoost(DateTime(2026, 9, 11, 8))
        .markServed(TravelSceneId.transport, DateTime(2026, 9, 11, 9))
        .cleared();
    expect(plan, TravelFocusPlan.empty);
    expect(plan.isActive, isFalse);
  });

  test('round-trip json keeps dates as calendar days', () {
    final original = TravelFocusPlan.empty
        .withFocuses([
          TravelFocus(
            scene: TravelSceneId.transport,
            date: DateTime(2026, 9, 18, 15, 4),
          ),
        ])
        .markKanaBoost(DateTime(2026, 9, 11, 21));
    final copy = TravelFocusPlan.fromJson(
      Map<String, dynamic>.from(original.toJson()),
    );
    expect(copy.focuses.single.date, DateTime(2026, 9, 18));
    expect(copy.kanaBoostOn, DateTime(2026, 9, 11));
  });

  test('constructor copies and seals focuses and servedOn', () {
    final focuses = [const TravelFocus(scene: TravelSceneId.transport)];
    final servedOn = <TravelSceneId, DateTime>{
      TravelSceneId.transport: DateTime(2026, 9, 14),
    };
    final plan = TravelFocusPlan(focuses: focuses, servedOn: servedOn);

    focuses.clear();
    servedOn.clear();
    expect(plan.isActive, isTrue);
    expect(plan.servedOn[TravelSceneId.transport], DateTime(2026, 9, 14));

    expect(plan.focuses.clear, throwsUnsupportedError);
    expect(
      () => plan.focuses.add(const TravelFocus(scene: TravelSceneId.clothing)),
      throwsUnsupportedError,
    );
    expect(
      () => plan.focuses[0] = const TravelFocus(scene: TravelSceneId.shrine),
      throwsUnsupportedError,
    );
    expect(plan.servedOn.clear, throwsUnsupportedError);
    expect(
      () => plan.servedOn[TravelSceneId.clothing] = DateTime(2026, 9, 15),
      throwsUnsupportedError,
    );
    expect(plan.focuses.single.scene, TravelSceneId.transport);
    expect(plan.servedOn, hasLength(1));
  });

  test(
    'fromJson, withFocuses, markKanaBoost, and markServed keep old snapshots',
    () {
      final decoded = TravelFocusPlan.fromJson({
        'focuses': [
          {'scene': 'transport'},
        ],
        'served': {'transport': '2026-09-14'},
      });
      expect(decoded.focuses.clear, throwsUnsupportedError);
      expect(decoded.servedOn.clear, throwsUnsupportedError);

      final original = TravelFocusPlan.empty.withFocuses(const [
        TravelFocus(scene: TravelSceneId.transport),
      ]);
      final boosted = original.markKanaBoost(DateTime(2026, 9, 14, 8));
      final served = original.markServed(
        TravelSceneId.transport,
        DateTime(2026, 9, 14, 9),
      );
      final swapped = original.withFocuses(const [
        TravelFocus(scene: TravelSceneId.clothing),
      ]);

      expect(original.kanaBoostOn, isNull);
      expect(original.servedOn, isEmpty);
      expect(original.focuses.single.scene, TravelSceneId.transport);
      expect(boosted.kanaBoostOn, DateTime(2026, 9, 14));
      expect(boosted.focuses.single.scene, TravelSceneId.transport);
      expect(served.servedOn[TravelSceneId.transport], DateTime(2026, 9, 14));
      expect(served.focuses.single.scene, TravelSceneId.transport);
      expect(swapped.focuses.single.scene, TravelSceneId.clothing);
      expect(swapped.servedOn, isEmpty);
      expect(original.focuses.single.scene, TravelSceneId.transport);
    },
  );

  test('restaurant and convenience ids persist and are not dropped', () {
    final original = TravelFocusPlan.empty.withFocuses(const [
      TravelFocus(scene: TravelSceneId.restaurant),
      TravelFocus(scene: TravelSceneId.convenience),
    ]);
    final copy = TravelFocusPlan.fromJson(
      Map<String, dynamic>.from(original.toJson()),
    );
    expect(copy.focuses.map((f) => f.scene), [
      TravelSceneId.restaurant,
      TravelSceneId.convenience,
    ]);
    expect(TravelFocusPlan.sceneNamed('restaurant'), TravelSceneId.restaurant);
    expect(
      TravelFocusPlan.sceneNamed('convenience'),
      TravelSceneId.convenience,
    );
    expect(TravelFocusPlan.sceneNamed('hotel'), TravelSceneId.hotel);
  });
}
