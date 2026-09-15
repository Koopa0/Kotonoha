// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/main.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_kana_progress_repository.dart';
import 'helpers/fake_word_progress_repository.dart';
import 'services/fake_preferences_service.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// #149 B9: the 詞と句 progress contract is replaceable. These tests prove
/// runtime identity and the notify / save-retry / snapshot rules on Local
/// and Fake together — they are not the source-registration guard in
/// [test/architecture/pure_layer_imports_test.dart].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 9, 15, 12);
  const id = 'word:いぬ';
  const otherId = 'phrase:そらが あおい';
  const dueA = 'word:a';
  const dueB = 'word:b';

  final cases =
      <
        ({
          String name,
          Future<({WordProgressRepository owner, void Function() failWrites})>
          Function()
          create,
        })
      >[
        (
          name: 'local',
          create: () async {
            final prefs = FakePreferencesService();
            final owner = await WordProgressRepository.load(prefs);
            return (
              owner: owner,
              failWrites: () {
                prefs.failWrites.add(ProgressStoreKeys.wordStats);
              },
            );
          },
        ),
        (
          name: 'fake',
          create: () async {
            final owner = FakeWordProgressRepository();
            return (owner: owner, failWrites: () => owner.failWrites = true);
          },
        ),
      ];

  group('snapshot ownership', () {
    test('fake constructor inputs cannot alias the owner', () {
      final stats = <String, WordStat>{id: const WordStat(seenCount: 1)};
      final fake = FakeWordProgressRepository(stats: stats);

      stats[id] = const WordStat();

      expect(fake.statForItem(id).seenCount, 1);
    });

    for (final spec in cases) {
      test(
        '${spec.name} stats is a snapshot the reader cannot write through',
        () async {
          final t = await spec.create();
          await t.owner.recordAnswer(id, correct: true, at: at);

          final snapshot = t.owner.stats;
          expect(snapshot, isNotEmpty);
          expect(snapshot.clear, throwsUnsupportedError);
          expect(() => snapshot[id] = const WordStat(), throwsUnsupportedError);

          final before = Map<String, WordStat>.of(snapshot);
          await t.owner.recordAnswer(otherId, correct: true, at: at);
          expect(
            snapshot.keys,
            before.keys,
            reason: 'the handed-out map moved',
          );
          expect(t.owner.stats.keys, isNot(before.keys));
        },
      );
    }
  });

  group('notify before flush', () {
    test('local notifies before the platform write lands', () async {
      final prefs = FakePreferencesService();
      final gate = PlatformGate();
      prefs.writeGates[ProgressStoreKeys.wordStats] = gate;
      final owner = await WordProgressRepository.load(prefs);
      var notifications = 0;
      owner.addListener(() => notifications++);

      final write = owner.recordAnswer(id, correct: true, at: at);
      expect(owner.statForItem(id).isSeen, isTrue);
      expect(notifications, 1);
      await gate.entered;
      expect(notifications, 1);
      gate.release();
      await write;
      expect(notifications, 1);
    });

    test('fake notifies before the flush lands', () async {
      final fake = FakeWordProgressRepository();
      final gate = FakeRepositoryWriteGate();
      fake.writeGate = gate;
      var notifications = 0;
      fake.addListener(() => notifications++);

      final write = fake.recordAnswer(id, correct: true, at: at);
      expect(fake.statForItem(id).isSeen, isTrue);
      expect(notifications, 1);
      await gate.entered;
      expect(notifications, 1);
      gate.release();
      await write;
      expect(notifications, 1);
    });
  });

  group('gated flush preserves pending mid-write mutations', () {
    const inu = 'word:いぬ';
    const neko = 'word:ねこ';

    for (final spec in cases) {
      test(
        '${spec.name}: a failed gated flush keeps later mutations pending '
        'and the second future still reports failure',
        () async {
          late FakePreferencesService prefs;
          FakeRepositoryWriteGate? fakeGate;
          PlatformGate? platformGate;
          late WordProgressRepository owner;
          late void Function() fail;
          late void Function() clearFail;

          if (spec.name == 'local') {
            prefs = FakePreferencesService();
            platformGate = PlatformGate();
            prefs.writeGates[ProgressStoreKeys.wordStats] = platformGate;
            owner = await WordProgressRepository.load(prefs);
            fail = () => prefs.failWrites.add(ProgressStoreKeys.wordStats);
            clearFail = () =>
                prefs.failWrites.remove(ProgressStoreKeys.wordStats);
          } else {
            final fake = FakeWordProgressRepository();
            fakeGate = FakeRepositoryWriteGate();
            fake.writeGate = fakeGate;
            owner = fake;
            fail = () => fake.failWrites = true;
            clearFail = () => fake.failWrites = false;
            prefs = FakePreferencesService();
          }

          final first = owner.recordAnswer(inu, correct: true, at: at);
          final entered = spec.name == 'local'
              ? platformGate!.entered
              : fakeGate!.entered;
          await entered;
          final second = owner.recordAnswer(neko, correct: true, at: at);
          fail();
          if (spec.name == 'local') {
            platformGate!.release();
          } else {
            fakeGate!.release();
          }

          await expectLater(first, throwsA(isA<StoreWriteFailure>()));
          await expectLater(second, throwsA(isA<StoreWriteFailure>()));

          expect(owner.statForItem(inu).isSeen, isTrue);
          expect(owner.statForItem(neko).isSeen, isTrue);

          if (spec.name == 'local') {
            final fresh = await WordProgressRepository.load(
              FakePreferencesService.restarted(prefs),
            );
            expect(fresh.statForItem(inu).isSeen, isFalse);
            expect(fresh.statForItem(neko).isSeen, isFalse);
          }

          clearFail();
          await owner.flushPending();
          expect(owner.statForItem(inu).isSeen, isTrue);
          expect(owner.statForItem(neko).isSeen, isTrue);

          if (spec.name == 'local') {
            final fresh = await WordProgressRepository.load(
              FakePreferencesService.restarted(prefs),
            );
            expect(fresh.statForItem(inu).isSeen, isTrue);
            expect(fresh.statForItem(neko).isSeen, isTrue);
          } else {
            await owner.reloadFromPlatform();
            expect(owner.statForItem(inu).isSeen, isTrue);
            expect(owner.statForItem(neko).isSeen, isTrue);
          }
        },
      );
    }
  });

  group('pending writes and retry', () {
    for (final spec in cases) {
      test(
        '${spec.name}: a failed flush keeps memory and retry does not re-climb',
        () async {
          late FakePreferencesService? prefs;
          late FakeWordProgressRepository? fake;
          final WordProgressRepository owner;
          final void Function() fail;
          final void Function() clearFail;
          if (spec.name == 'local') {
            prefs = FakePreferencesService();
            owner = await WordProgressRepository.load(prefs);
            fail = () => prefs!.failWrites.add(ProgressStoreKeys.wordStats);
            clearFail = () =>
                prefs!.failWrites.remove(ProgressStoreKeys.wordStats);
            fake = null;
          } else {
            fake = FakeWordProgressRepository();
            owner = fake;
            fail = () => fake!.failWrites = true;
            clearFail = () => fake!.failWrites = false;
            prefs = null;
          }

          fail();
          final persist = ProgressPersistenceController(
            kanaFlush: () async {},
            kanjiFlush: () async {},
            wordFlush: owner.flushPending,
          );

          persist.trackWord(owner.recordAnswer(id, correct: true, at: at));
          expect(owner.statForItem(id).srsLevel, 1);
          await _settle(() => persist.hasWriteFailure);

          clearFail();
          await persist.retry();
          expect(persist.hasWriteFailure, isFalse);
          expect(owner.statForItem(id).srsLevel, 1);
          expect(owner.statForItem(id).correctCount, 1);

          await owner.reloadFromPlatform();
          expect(owner.statForItem(id).srsLevel, 1);
        },
      );
    }
  });

  group('flushPending contract', () {
    // The same three probes against Local and Fake. A substitute that
    // marks flush dirty or ignores restore / journal blocks would let
    // later retry tests pass on one owner and fail on the other.
    for (final spec in cases) {
      group(spec.name, () {
        test('a clean owner is a no-op when writes are unavailable', () async {
          final t = await spec.create();
          t.failWrites();
          await t.owner.flushPending();
          expect(t.owner.stats, isEmpty);
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

  group('WordStat rule parity', () {
    // Fake must not invent a second schedule. Both owners apply the same
    // value-type rules; a later kana confusable-scale parity stays a
    // follow-up on the kana contract and is not opened here.
    for (final spec in cases) {
      group(spec.name, () {
        test('recordAnswer delegates to WordStat', () async {
          final t = await spec.create();
          await t.owner.recordAnswer(id, correct: true, at: at);
          expect(
            t.owner.statForItem(id).srsLevel,
            const WordStat().recordAnswer(correct: true, at: at).srsLevel,
          );
          expect(
            t.owner.statForItem(id).dueAt,
            const WordStat().recordAnswer(correct: true, at: at).dueAt,
          );

          await t.owner.recordAnswer(id, correct: false, at: at);
          final afterWrong = const WordStat()
              .recordAnswer(correct: true, at: at)
              .recordAnswer(correct: false, at: at);
          expect(t.owner.statForItem(id).srsLevel, afterWrong.srsLevel);
          expect(t.owner.statForItem(id).wrongCount, afterWrong.wrongCount);
        });

        test('markIntroduced does not climb', () async {
          final t = await spec.create();
          await t.owner.markIntroduced(id, at: at);
          final expected = const WordStat().markIntroduced(at: at);
          expect(t.owner.statForItem(id).isSeen, isTrue);
          expect(t.owner.statForItem(id).correctCount, expected.correctCount);
          expect(t.owner.statForItem(id).srsLevel, expected.srsLevel);
          expect(t.owner.statForItem(id).dueAt, expected.dueAt);
        });

        test('introduce on unseen is one correct WordStat answer', () async {
          final t = await spec.create();
          await t.owner.introduce(id, at: at);
          final expected = const WordStat().recordAnswer(correct: true, at: at);
          expect(t.owner.statForItem(id).srsLevel, expected.srsLevel);
          expect(t.owner.statForItem(id).correctCount, expected.correctCount);
        });

        test('introduce on a seen item is exposure, not schedule', () async {
          final t = await spec.create();
          await t.owner.introduce(id, at: at);
          final afterFirst = t.owner.statForItem(id);

          await t.owner.introduce(id, at: at.add(const Duration(days: 1)));

          expect(t.owner.statForItem(id).srsLevel, afterFirst.srsLevel);
          expect(t.owner.statForItem(id).dueAt, afterFirst.dueAt);
          expect(t.owner.statForItem(id).correctCount, afterFirst.correctCount);
        });

        test(
          'markIntroduced on a seen item is exposure, not schedule',
          () async {
            final t = await spec.create();
            await t.owner.markIntroduced(id, at: at);
            final afterFirst = t.owner.statForItem(id);

            await t.owner.markIntroduced(
              id,
              at: at.add(const Duration(days: 1)),
            );

            expect(t.owner.statForItem(id).srsLevel, afterFirst.srsLevel);
            expect(t.owner.statForItem(id).dueAt, afterFirst.dueAt);
            expect(
              t.owner.statForItem(id).correctCount,
              afterFirst.correctCount,
            );
          },
        );

        test('dueItemIds returns due items earliest first', () async {
          final t = await spec.create();
          await t.owner.recordAnswer(dueA, correct: true, at: at);
          await t.owner.recordAnswer(
            dueB,
            correct: true,
            at: at.subtract(const Duration(days: 1)),
          );

          final due = t.owner.dueItemIds(at.add(const Duration(days: 30)));
          expect(due, [dueB, dueA]);
          expect(
            t.owner.dueItemIds(at.subtract(const Duration(days: 1))),
            isEmpty,
          );
        });
      });
    }
  });

  group('gated reset preserves pending mid-reset mutations', () {
    const inu = 'word:いぬ';
    const neko = 'word:ねこ';

    for (final spec in cases) {
      test(
        '${spec.name}: a failed gated reset keeps later mutations for owner '
        'retry',
        () async {
          late FakePreferencesService prefs;
          FakeRepositoryWriteGate? fakeGate;
          PlatformGate? platformGate;
          late WordProgressRepository owner;
          late void Function() fail;
          late void Function() clearFail;

          if (spec.name == 'local') {
            prefs = FakePreferencesService();
            platformGate = PlatformGate();
            prefs.removeGates[ProgressStoreKeys.wordStats] = platformGate;
            owner = await WordProgressRepository.load(prefs);
            fail = () {
              prefs.failRemoves.add(ProgressStoreKeys.wordStats);
              prefs.failWrites.add(ProgressStoreKeys.wordStats);
            };
            clearFail = () {
              prefs.failRemoves.remove(ProgressStoreKeys.wordStats);
              prefs.failWrites.remove(ProgressStoreKeys.wordStats);
            };
          } else {
            final fake = FakeWordProgressRepository();
            owner = fake;
            fail = () => fake.failWrites = true;
            clearFail = () => fake.failWrites = false;
            prefs = FakePreferencesService();
          }

          await owner.recordAnswer(inu, correct: true, at: at);
          if (spec.name == 'fake') {
            fakeGate = FakeRepositoryWriteGate();
            (owner as FakeWordProgressRepository).writeGate = fakeGate;
          }
          final reset = owner.reset();
          final entered = spec.name == 'local'
              ? platformGate!.entered
              : fakeGate!.entered;
          await entered;
          final answer = owner.recordAnswer(neko, correct: true, at: at);
          fail();
          if (spec.name == 'local') {
            platformGate!.release();
          } else {
            fakeGate!.release();
          }

          await expectLater(reset, throwsA(isA<StoreWriteFailure>()));
          await expectLater(answer, throwsA(isA<StoreWriteFailure>()));

          expect(owner.statForItem(inu).isSeen, isFalse);
          expect(owner.statForItem(neko).correctCount, 1);

          clearFail();
          await owner.flushPending();
          expect(owner.statForItem(neko).correctCount, 1);

          if (spec.name == 'local') {
            final fresh = await WordProgressRepository.load(
              FakePreferencesService.restarted(prefs),
            );
            expect(fresh.statForItem(neko).correctCount, 1);
          } else {
            await owner.reloadFromPlatform();
            expect(owner.statForItem(neko).correctCount, 1);
          }
        },
      );
    }
  });

  group('reset failure parity', () {
    // Local refuses removeAll; Fake refuses the empty flush. Both must
    // reconcile memory with the durable owner — not stay optimistically empty.
    for (final spec in cases) {
      test(
        '${spec.name}: a failed reset reconciles memory with durable data',
        () async {
          late FakePreferencesService? prefs;
          late FakeWordProgressRepository? fake;
          final WordProgressRepository owner;
          if (spec.name == 'local') {
            prefs = FakePreferencesService();
            owner = await WordProgressRepository.load(prefs);
          } else {
            fake = FakeWordProgressRepository();
            owner = fake;
            prefs = null;
          }

          await owner.recordAnswer(id, correct: true, at: at);
          expect(owner.statForItem(id).correctCount, 1);

          if (spec.name == 'local') {
            prefs!.failRemoves.add(ProgressStoreKeys.wordStats);
          } else {
            fake!.failWrites = true;
          }

          await expectLater(owner.reset(), throwsA(isA<StoreWriteFailure>()));
          expect(owner.statForItem(id).correctCount, 1);

          await owner.reloadFromPlatform();
          expect(owner.statForItem(id).correctCount, 1);
        },
      );

      test('${spec.name}: a failed reset matches a durable restart', () async {
        late FakePreferencesService? prefs;
        late FakeWordProgressRepository? fake;
        final WordProgressRepository owner;
        if (spec.name == 'local') {
          prefs = FakePreferencesService();
          owner = await WordProgressRepository.load(prefs);
        } else {
          fake = FakeWordProgressRepository();
          owner = fake;
          prefs = null;
        }

        await owner.recordAnswer(id, correct: true, at: at);

        if (spec.name == 'local') {
          prefs!.failRemoves.add(ProgressStoreKeys.wordStats);
        } else {
          fake!.failWrites = true;
        }

        await expectLater(owner.reset(), throwsA(isA<StoreWriteFailure>()));

        if (spec.name == 'local') {
          final fresh = await WordProgressRepository.load(
            FakePreferencesService.restarted(prefs!),
          );
          expect(owner.statForItem(id).correctCount, 1);
          expect(fresh.statForItem(id).correctCount, 1);
        } else {
          final beforeReload = owner.statForItem(id).correctCount;
          await owner.reloadFromPlatform();
          expect(owner.statForItem(id).correctCount, beforeReload);
        }
      });

      test('${spec.name}: reset succeeds once the fault clears', () async {
        late FakePreferencesService? prefs;
        late FakeWordProgressRepository? fake;
        final WordProgressRepository owner;
        if (spec.name == 'local') {
          prefs = FakePreferencesService();
          owner = await WordProgressRepository.load(prefs);
        } else {
          fake = FakeWordProgressRepository();
          owner = fake;
          prefs = null;
        }

        await owner.recordAnswer(id, correct: true, at: at);

        if (spec.name == 'local') {
          prefs!.failRemoves.add(ProgressStoreKeys.wordStats);
        } else {
          fake!.failWrites = true;
        }

        await expectLater(owner.reset(), throwsA(isA<StoreWriteFailure>()));

        if (spec.name == 'local') {
          prefs!.failRemoves.clear();
        } else {
          fake!.failWrites = false;
        }

        await owner.reset();
        expect(owner.statForItem(id).correctCount, 0);
        expect(owner.stats, isEmpty);
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

        final owner = tester
            .element(find.byType(KanaLoopApp))
            .read<WordProgressRepository>();
        expect(owner, isA<LocalWordProgressRepository>());
        expect(
          identical(
            owner,
            tester
                .element(find.byType(KanaLoopApp))
                .read<WordProgressRepository>(),
          ),
          isTrue,
        );
      },
    );

    testWidgets('an injected fake is the same instance the tree reads', (
      tester,
    ) async {
      final fake = FakeWordProgressRepository();
      await tester.pumpWidget(
        await bootstrap(
          prefs: FakePreferencesService(),
          speech: const SilentSpeechService(),
          analytics: InMemoryAnalyticsLog(),
          words: fake,
        ),
        duration: Duration.zero,
      );
      await tester.pump();

      final composed = tester
          .element(find.byType(KanaLoopApp))
          .read<WordProgressRepository>();
      expect(identical(composed, fake), isTrue);
      expect(composed, isNot(isA<LocalWordProgressRepository>()));
    });
  });
}
