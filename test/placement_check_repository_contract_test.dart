// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_placement_check_repository.dart';
import 'services/fake_preferences_service.dart';

/// #149 B9: the placement check contract is replaceable. These prove the
/// snapshot, notify and save-retry rules on both owners, and runtime identity
/// in the real composition — they are not the source-registration guard in
/// test/architecture/pure_layer_imports_test.dart.
void main() {
  late PlacementDraft started;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load(FakePreferencesService());
    started = PlacementCheck.start([Lessons.fromKana(kana.allKana).first])!;
  });

  // PlacementDraft is immutable, so one value is safe to reuse across tests.
  PlacementDraft startedDraft() => started;

  group('draft snapshot ownership', () {
    test(
      'a handed-out draft does not move when the owner saves again',
      () async {
        final owner = FakePlacementCheckRepository();
        await owner.save(startedDraft());

        final held = owner.draft;
        await owner.clear();

        expect(
          held.pendingKanaIds,
          isNotEmpty,
          reason: 'the draft handed out earlier moved under the reader',
        );
        expect(owner.draft.pendingKanaIds, isEmpty);
      },
    );

    test('draft collections reject mutation', () async {
      final owner = FakePlacementCheckRepository();
      await owner.save(startedDraft());

      final draft = owner.draft;
      expect(draft.pendingKanaIds.clear, throwsUnsupportedError);
      expect(draft.lessonIds.clear, throwsUnsupportedError);
      expect(draft.records.clear, throwsUnsupportedError);
    });
  });

  // The same probes against Local and Fake. A substitute that marked flush
  // dirty, dropped a mutation on a failed write, or disagreed about what a
  // restore lock refuses would let a placement test pass on one owner only.
  group('owner parity', () {
    final cases =
        <
          ({
            String name,
            Future<
              ({PlacementCheckRepository owner, void Function() failWrites})
            >
            Function()
            create,
          })
        >[
          (
            name: 'local',
            create: () async {
              final prefs = FakePreferencesService();
              final owner = await PlacementCheckRepository.load(prefs);
              return (
                owner: owner,
                failWrites: () => prefs.failWrites.add(
                  LocalPlacementCheckRepository.storageKey,
                ),
              );
            },
          ),
          (
            name: 'fake',
            create: () async {
              final owner = FakePlacementCheckRepository();
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
          expect(t.owner.draft.hasProgress, isFalse);
        });

        test('a failed write keeps the draft in memory', () async {
          final t = await spec.create();
          t.failWrites();
          await expectLater(t.owner.save(startedDraft()), throwsA(anything));
          expect(
            t.owner.draft.pendingKanaIds,
            isNotEmpty,
            reason: 'a failed write discarded the in-memory draft',
          );
        });

        test('clear empties a started draft', () async {
          final t = await spec.create();
          await t.owner.save(startedDraft());
          expect(t.owner.draft.pendingKanaIds, isNotEmpty);

          await t.owner.clear();
          expect(t.owner.draft.pendingKanaIds, isEmpty);
          expect(t.owner.draft.hasProgress, isFalse);
        });

        test('a save notifies its listeners once', () async {
          final t = await spec.create();
          var notified = 0;
          t.owner.addListener(() => notified++);

          final pending = t.owner.save(startedDraft());
          expect(
            notified,
            1,
            reason: 'the reader was not told before the write',
          );
          await pending;
          expect(notified, 1);
        });

        test('prepareForRestore refuses a save', () async {
          final t = await spec.create();
          await t.owner.prepareForRestore();
          await expectLater(
            t.owner.save(startedDraft()),
            throwsA(isA<ProgressRestoreInProgress>()),
          );
        });

        test('prepareForRestore refuses flushPending', () async {
          final t = await spec.create();
          await t.owner.prepareForRestore();
          await expectLater(
            t.owner.flushPending(),
            throwsA(isA<ProgressRestoreInProgress>()),
          );
        });

        test('finishRestore lets writes through again', () async {
          final t = await spec.create();
          await t.owner.prepareForRestore();
          t.owner.finishRestore();

          await t.owner.save(startedDraft());
          expect(t.owner.draft.pendingKanaIds, isNotEmpty);
        });

        test('discardForRestore drops the draft', () async {
          final t = await spec.create();
          await t.owner.save(startedDraft());

          await t.owner.discardForRestore();
          expect(t.owner.draft.hasProgress, isFalse);
        });

        test('hideDraftWhileDiscardPending hides without a write', () async {
          final t = await spec.create();
          await t.owner.save(startedDraft());
          t.failWrites();

          t.owner.hideDraftWhileDiscardPending();
          expect(
            t.owner.draft.hasProgress,
            isFalse,
            reason: 'the stale draft stayed visible',
          );
        });
      });
    }
  });

  // The defect review found on the travel contract, probed here too: a write
  // already in flight must commit the draft it started with, and clear only
  // that generation.
  group('a parked write commits only its own generation', () {
    test('fake', () async {
      final owner = FakePlacementCheckRepository();
      final gate = FakeRepositoryWriteGate();
      owner.writeGate = gate;

      final first = owner.save(startedDraft());
      await gate.entered;
      final second = owner.clear();
      gate.release();

      await first;
      expect(
        owner.durableDraft.pendingKanaIds,
        isNotEmpty,
        reason: 'the parked write committed a later draft as its own',
      );

      await second;
      expect(owner.durableDraft.pendingKanaIds, isEmpty);
    });
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
        final owner = element.read<PlacementCheckRepository>();
        expect(owner, isA<LocalPlacementCheckRepository>());
        expect(
          identical(owner, element.read<PlacementCheckRepository>()),
          isTrue,
          reason: 'two reads of the same route produced different owners',
        );
      },
    );

    testWidgets('an injected fake is the same instance the tree reads', (
      tester,
    ) async {
      final fake = FakePlacementCheckRepository();
      await tester.pumpWidget(
        await bootstrap(
          prefs: FakePreferencesService(),
          speech: const SilentSpeechService(),
          analytics: InMemoryAnalyticsLog(),
          placement: fake,
        ),
        duration: Duration.zero,
      );
      await tester.pump();

      final composed = tester
          .element(find.byType(KanaLoopApp))
          .read<PlacementCheckRepository>();
      expect(identical(composed, fake), isTrue);
      expect(composed, isNot(isA<LocalPlacementCheckRepository>()));
    });
  });
}
