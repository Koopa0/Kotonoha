// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_kanji_reading_repository.dart';
import 'services/fake_preferences_service.dart';

/// #149 B9: the kanji reading contract is replaceable. These prove the
/// snapshot, notify and save-retry rules on both owners, and runtime identity
/// in the real composition — they are not the source-registration guard in
/// test/architecture/pure_layer_imports_test.dart.
void main() {
  final at = DateTime(2026, 3, 1, 9);
  const a = 'unit:学校#がっこう';
  const b = 'unit:先生#せんせい';

  group('stats snapshot ownership', () {
    test('a handed-out snapshot does not move when the owner writes', () async {
      final owner = FakeKanjiReadingRepository();
      await owner.recordAnswer(a, correct: true, at: at);

      final held = owner.stats;
      await owner.recordAnswer(b, correct: true, at: at);

      expect(held.keys, [
        a,
      ], reason: 'the snapshot handed out earlier moved under the reader');
      expect(owner.stats.keys, containsAll(<String>[a, b]));
    });

    test('the snapshot rejects mutation', () async {
      final owner = FakeKanjiReadingRepository();
      await owner.recordAnswer(a, correct: true, at: at);

      final snapshot = owner.stats;
      expect(snapshot.clear, throwsUnsupportedError);
      expect(
        () => snapshot['unit:made-up'] = const ReadingStat(),
        throwsUnsupportedError,
      );
    });

    test('a constructor input cannot alias the owner', () async {
      final seed = <String, ReadingStat>{a: const ReadingStat()};
      final owner = FakeKanjiReadingRepository(stats: seed);

      seed[b] = const ReadingStat();

      expect(owner.stats.keys, [
        a,
      ], reason: 'the caller wrote through the constructor input');
    });
  });

  // The same probes against Local and Fake. A substitute that invented its own
  // due ordering, marked flush dirty, or dropped a mutation on a failed write
  // would let a session test pass on one owner and fail on the other.
  group('owner parity', () {
    final cases =
        <
          ({
            String name,
            Future<({KanjiReadingRepository owner, void Function() failWrites})>
            Function()
            create,
          })
        >[
          (
            name: 'local',
            create: () async {
              final prefs = FakePreferencesService();
              final owner = await KanjiReadingRepository.load(prefs);
              return (
                owner: owner,
                failWrites: () =>
                    prefs.failWrites.add(ProgressStoreKeys.kanjiStats),
              );
            },
          ),
          (
            name: 'fake',
            create: () async {
              final owner = FakeKanjiReadingRepository();
              return (owner: owner, failWrites: () => owner.failWrites = true);
            },
          ),
        ];

    for (final spec in cases) {
      group(spec.name, () {
        test('recordAnswer delegates the schedule to ReadingStat', () async {
          final t = await spec.create();
          await t.owner.recordAnswer(a, correct: true, at: at);

          final expected = const ReadingStat().recordAnswer(
            correct: true,
            at: at,
          );
          expect(t.owner.statForUnit(a).srsLevel, expected.srsLevel);
          expect(t.owner.statForUnit(a).dueAt, expected.dueAt);
          expect(t.owner.statForUnit(a).correctCount, expected.correctCount);
        });

        test('dueUnitIds returns due units, earliest first', () async {
          final t = await spec.create();
          await t.owner.recordAnswer(a, correct: true, at: at);
          await t.owner.recordAnswer(
            b,
            correct: true,
            at: at.subtract(const Duration(days: 2)),
          );

          final due = t.owner.dueUnitIds(at.add(const Duration(days: 365)));
          expect(due, [b, a], reason: 'due units came back in the wrong order');
        });

        test('dueUnitIds excludes units not yet due', () async {
          final t = await spec.create();
          await t.owner.recordAnswer(a, correct: true, at: at);

          expect(
            t.owner.dueUnitIds(at),
            isEmpty,
            reason: 'a unit answered now is already due',
          );
        });

        test('seenUnitCount counts practised units only', () async {
          final t = await spec.create();
          expect(t.owner.seenUnitCount, 0);

          await t.owner.recordAnswer(a, correct: true, at: at);
          expect(t.owner.seenUnitCount, 1);

          await t.owner.recordAnswer(a, correct: false, at: at);
          expect(
            t.owner.seenUnitCount,
            1,
            reason: 'answering the same unit twice counted it twice',
          );
        });

        test('a clean owner is a no-op when writes are unavailable', () async {
          final t = await spec.create();
          t.failWrites();
          await t.owner.flushPending();
          expect(t.owner.stats, isEmpty);
        });

        test('a failed write keeps the answer in memory', () async {
          final t = await spec.create();
          t.failWrites();
          await expectLater(
            t.owner.recordAnswer(a, correct: true, at: at),
            throwsA(anything),
          );
          expect(t.owner.statForUnit(a).isSeen, isTrue);
        });

        test('prepareForRestore refuses flushPending', () async {
          final t = await spec.create();
          await t.owner.prepareForRestore();
          await expectLater(
            t.owner.flushPending(),
            throwsA(isA<ProgressRestoreInProgress>()),
          );
        });

        test('a blocked restore journal refuses flushPending', () async {
          final t = await spec.create();
          t.owner.setRestoreJournalBlocked(true);
          await expectLater(
            t.owner.flushPending(),
            throwsA(isA<ProgressRestoreJournalBlocked>()),
          );
        });
      });
    }
  });

  // The defect found by review on the travel contract, probed here before it
  // can be repeated: a write already in flight must commit the state it
  // started with, and clear only that generation.
  group('a parked write commits only its own generation', () {
    test('fake', () async {
      final owner = FakeKanjiReadingRepository();
      final gate = FakeRepositoryWriteGate();
      owner.writeGate = gate;

      final first = owner.recordAnswer(a, correct: true, at: at);
      await gate.entered;
      final second = owner.recordAnswer(b, correct: true, at: at);
      gate.release();

      await first;
      expect(owner.durableStats.keys, [
        a,
      ], reason: 'the parked write committed a later answer as its own');

      await second;
      expect(owner.durableStats.keys, containsAll(<String>[a, b]));
    });

    test(
      'fake keeps a later answer pending when its own write fails',
      () async {
        final owner = FakeKanjiReadingRepository();
        final gate = FakeRepositoryWriteGate();
        owner.writeGate = gate;

        final first = owner.recordAnswer(a, correct: true, at: at);
        await gate.entered;
        final second = owner.recordAnswer(b, correct: true, at: at);
        owner.failWrites = true;
        gate.release();

        await expectLater(first, throwsA(isA<StoreWriteFailure>()));
        await expectLater(second, throwsA(isA<StoreWriteFailure>()));
        expect(owner.durableStats, isEmpty);

        owner.failWrites = false;
        owner.writeGate = null;
        await owner.flushPending();

        expect(
          owner.durableStats.keys,
          containsAll(<String>[a, b]),
          reason: 'the pending answers were dropped instead of retried',
        );
      },
    );
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
        final owner = element.read<KanjiReadingRepository>();
        expect(owner, isA<LocalKanjiReadingRepository>());
        expect(
          identical(owner, element.read<KanjiReadingRepository>()),
          isTrue,
          reason: 'two reads of the same route produced different owners',
        );
      },
    );

    testWidgets('an injected fake is the same instance the tree reads', (
      tester,
    ) async {
      final fake = FakeKanjiReadingRepository();
      await tester.pumpWidget(
        await bootstrap(
          prefs: FakePreferencesService(),
          speech: const SilentSpeechService(),
          analytics: InMemoryAnalyticsLog(),
          kanji: fake,
        ),
        duration: Duration.zero,
      );
      await tester.pump();

      final composed = tester
          .element(find.byType(KanaLoopApp))
          .read<KanjiReadingRepository>();
      expect(identical(composed, fake), isTrue);
      expect(composed, isNot(isA<LocalKanjiReadingRepository>()));
    });
  });
}
