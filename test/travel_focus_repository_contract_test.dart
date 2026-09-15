// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_travel_focus_repository.dart';
import 'services/fake_preferences_service.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// #149 B9: the travel focus contract is replaceable. These prove the
/// snapshot, notify and save-retry rules on both owners, and runtime
/// identity in the real composition — they are not the source-registration
/// guard in test/architecture/pure_layer_imports_test.dart.
void main() {
  final at = DateTime(2026, 3, 1, 9);
  const transport = TravelFocus(scene: TravelSceneId.transport);
  const hotel = TravelFocus(scene: TravelSceneId.hotel);

  group('plan snapshot ownership', () {
    test(
      'a handed-out plan does not move when the owner saves again',
      () async {
        final owner = FakeTravelFocusRepository();
        await owner.saveFocuses([transport]);

        final held = owner.plan;
        await owner.saveFocuses([hotel]);

        expect(
          held.focuses.single.scene,
          TravelSceneId.transport,
          reason: 'the plan handed out earlier moved under the reader',
        );
        expect(owner.plan.focuses.single.scene, TravelSceneId.hotel);
      },
    );

    test('plan collections reject mutation', () async {
      final owner = FakeTravelFocusRepository();
      await owner.saveFocuses([transport]);
      await owner.markServed(TravelSceneId.transport, at);

      final plan = owner.plan;
      expect(plan.focuses.clear, throwsUnsupportedError);
      expect(plan.servedOn.clear, throwsUnsupportedError);
      expect(() => plan.focuses.add(hotel), throwsUnsupportedError);
    });

    test('a constructor input cannot alias the owner', () {
      final focuses = <TravelFocus>[transport];
      final owner = FakeTravelFocusRepository(
        plan: TravelFocusPlan(focuses: focuses),
      );

      focuses.add(hotel);

      expect(
        owner.plan.focuses.length,
        1,
        reason: 'the caller wrote through the constructor input',
      );
    });
  });

  group('notify, save and retry', () {
    test('a mutation notifies before the flush lands', () async {
      final owner = FakeTravelFocusRepository();
      final gate = FakeRepositoryWriteGate();
      owner.writeGate = gate;

      var notified = 0;
      owner.addListener(() => notified++);

      final pending = owner.saveFocuses([transport]);
      await gate.entered;

      expect(notified, 1, reason: 'the reader was not told before the write');
      expect(owner.plan.focuses.single.scene, TravelSceneId.transport);
      expect(
        owner.durablePlan.isActive,
        isFalse,
        reason: 'the write landed before it was released',
      );

      gate.release();
      await pending;
      expect(owner.durablePlan.focuses.single.scene, TravelSceneId.transport);
    });

    test('a failed flush keeps memory and retry does not re-apply', () async {
      final owner = FakeTravelFocusRepository()..failWrites = true;

      await expectLater(owner.saveFocuses([transport]), throwsA(anything));
      expect(
        owner.plan.focuses.single.scene,
        TravelSceneId.transport,
        reason: 'a failed write discarded the in-memory value',
      );
      expect(owner.durablePlan.isActive, isFalse);

      owner.failWrites = false;
      await owner.flushPending();

      expect(owner.durablePlan.focuses.single.scene, TravelSceneId.transport);
      expect(
        owner.plan.focuses.length,
        1,
        reason: 'the retry applied the mutation a second time',
      );
    });

    test(
      'removing the last focus clears rather than storing inactive',
      () async {
        final owner = FakeTravelFocusRepository();
        await owner.saveFocuses([transport]);
        await owner.markKanaBoost(at);
        await owner.markServed(TravelSceneId.transport, at);
        expect(owner.plan.kanaBoostOn, isNotNull);
        expect(owner.plan.servedOn, isNotEmpty);

        await owner.saveFocuses(const <TravelFocus>[]);

        expect(owner.plan.isActive, isFalse);
        expect(owner.plan.focuses, isEmpty);
        // The difference between clearing and merely saving an empty focus
        // list: withFocuses carries kanaBoostOn and servedOn forward, so a
        // plan that was emptied but not cleared keeps yesterday's daily
        // cursor and would suppress today's travel step.
        expect(
          owner.plan.kanaBoostOn,
          isNull,
          reason: 'an emptied plan kept its kana boost cursor',
        );
        expect(
          owner.plan.servedOn,
          isEmpty,
          reason: 'an emptied plan kept its served cursor',
        );
      },
    );
  });

  // The same probes against Local and Fake. A substitute that marked flush
  // dirty, or dropped a mutation on a failed write, would let the retry
  // tests above pass on one owner and fail on the other.
  group('owner parity', () {
    final cases =
        <
          ({
            String name,
            Future<({TravelFocusRepository owner, void Function() failWrites})>
            Function()
            create,
          })
        >[
          (
            name: 'local',
            create: () async {
              final prefs = FakePreferencesService();
              final owner = await TravelFocusRepository.load(prefs);
              return (
                owner: owner,
                failWrites: () => prefs.failWrites.add('travel_focus_v1'),
              );
            },
          ),
          (
            name: 'fake',
            create: () async {
              final owner = FakeTravelFocusRepository();
              return (owner: owner, failWrites: () => owner.failWrites = true);
            },
          ),
        ];

    for (final spec in cases) {
      group(spec.name, () {
        test('a clean owner is a no-op when writes are unavailable', () async {
          final t = await spec.create();
          t.failWrites();
          await t.owner.flushPending();
          expect(t.owner.plan.isActive, isFalse);
        });

        test('a failed write keeps the value in memory', () async {
          final t = await spec.create();
          t.failWrites();
          await expectLater(
            t.owner.saveFocuses([transport]),
            throwsA(anything),
          );
          expect(t.owner.plan.focuses.single.scene, TravelSceneId.transport);
        });

        test('clear empties an active plan', () async {
          final t = await spec.create();
          await t.owner.saveFocuses([transport]);
          expect(t.owner.plan.isActive, isTrue);

          await t.owner.clear();
          expect(t.owner.plan.isActive, isFalse);
        });

        test('a save notifies its listeners once', () async {
          final t = await spec.create();
          var notified = 0;
          t.owner.addListener(() => notified++);

          final pending = t.owner.saveFocuses([transport]);
          expect(notified, 1);
          await pending;
          await _settle(() => notified == 1);
        });
      });
    }
  });

  group('formal composition identity', () {
    testWidgets(
      'the load path serves the local owner as the runtime instance',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          await bootstrap(
            speech: const SilentSpeechService(),
            analytics: InMemoryAnalyticsLog(),
          ),
          duration: Duration.zero,
        );
        await tester.pump();

        final element = tester.element(find.byType(KanaLoopApp));
        final owner = element.read<TravelFocusRepository>();
        expect(owner, isA<LocalTravelFocusRepository>());
        expect(
          identical(owner, element.read<TravelFocusRepository>()),
          isTrue,
          reason: 'two reads of the same route produced different owners',
        );
      },
    );

    testWidgets('an injected fake is the same instance the tree reads', (
      tester,
    ) async {
      final fake = FakeTravelFocusRepository();
      await tester.pumpWidget(
        await bootstrap(
          prefs: FakePreferencesService(),
          speech: const SilentSpeechService(),
          analytics: InMemoryAnalyticsLog(),
          travel: fake,
        ),
        duration: Duration.zero,
      );
      await tester.pump();

      final composed = tester
          .element(find.byType(KanaLoopApp))
          .read<TravelFocusRepository>();
      expect(identical(composed, fake), isTrue);
      expect(composed, isNot(isA<LocalTravelFocusRepository>()));
    });
  });
}
