// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/main.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_kana_progress_repository.dart';
import 'services/fake_preferences_service.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// #149 B9: the kana progress contract is replaceable. These tests prove
/// runtime identity and the notify / save-retry / snapshot rules on a fake
/// — they are not the source-registration guard in
/// [test/architecture/pure_layer_imports_test.dart].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 9, 15, 12);
  final first = kHiraganaGojuon.first;

  group('fake snapshot ownership', () {
    test('constructor inputs cannot alias the owner', () {
      final stats = <String, KanaStat>{first.id: const KanaStat(seenCount: 1)};
      final learned = <String>{'hira_row_0'};
      final unlocks = <String>{'unlock'};
      final fake = FakeKanaProgressRepository(
        stats: stats,
        learnedUnits: learned,
        seenUnlocks: unlocks,
      );

      stats[first.id] = const KanaStat();
      learned.add('made up');
      unlocks.add('other');

      expect(fake.statFor(first).seenCount, 1);
      expect(fake.learnedUnits, {'hira_row_0'});
      expect(fake.seenUnlocks, {'unlock'});
    });

    test('stats is a snapshot the reader cannot write through', () async {
      final fake = FakeKanaProgressRepository();
      await fake.recordAnswer(first, correct: true, at: at, latencyMs: 300);

      final snapshot = fake.stats;
      expect(snapshot, isNotEmpty);
      expect(snapshot.clear, throwsUnsupportedError);
      expect(
        () => snapshot[first.id] = const KanaStat(),
        throwsUnsupportedError,
      );

      final before = Map<String, KanaStat>.of(snapshot);
      await fake.recordAnswer(
        kHiraganaGojuon[1],
        correct: true,
        at: at,
        latencyMs: 300,
      );
      expect(snapshot.keys, before.keys, reason: 'the handed-out map moved');
      expect(fake.stats.keys, isNot(before.keys));
    });

    test(
      'learnedUnits is a snapshot the reader cannot write through',
      () async {
        final fake = FakeKanaProgressRepository();
        final rows = Lessons.fromKana(fake.allKana);
        await fake.markUnitLearned(rows.first.id);

        final snapshot = fake.learnedUnits;
        expect(snapshot.clear, throwsUnsupportedError);
        expect(() => snapshot.add('made up'), throwsUnsupportedError);

        await fake.markUnitLearned(rows[1].id);
        expect(snapshot, hasLength(1), reason: 'the handed-out set moved');
        expect(fake.learnedUnits, hasLength(2));
      },
    );
  });

  group('fake notify, save and retry', () {
    test('a mutation notifies before the flush lands', () async {
      final fake = FakeKanaProgressRepository();
      final gate = FakeRepositoryWriteGate();
      fake.writeGate = gate;
      var notifications = 0;
      fake.addListener(() => notifications++);

      final write = fake.recordAnswer(first, correct: true, at: at);
      expect(fake.statFor(first).isSeen, isTrue);
      expect(notifications, 1);
      await gate.entered;
      expect(notifications, 1);
      gate.release();
      await write;
      expect(notifications, 1);
    });

    test('a failed flush keeps memory and retry does not re-climb', () async {
      final fake = FakeKanaProgressRepository();
      fake.failWrites = true;
      final persist = ProgressPersistenceController(
        kanaFlush: fake.flushPending,
        kanjiFlush: () async {},
        wordFlush: () async {},
      );

      persist.trackKana(fake.recordAnswer(first, correct: true, at: at));
      expect(fake.statFor(first).srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites = false;
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(fake.statFor(first).srsLevel, 1);
      expect(fake.statFor(first).correctCount, 1);

      await fake.reloadFromPlatform();
      expect(fake.statFor(first).srsLevel, 1);
    });
  });

  group('flushPending contract', () {
    // The same three probes against Local and Fake. A substitute that
    // marks flush dirty or ignores restore / journal blocks would let
    // later retry tests pass on one owner and fail on the other.
    final cases =
        <
          ({
            String name,
            Future<({KanaProgressRepository owner, void Function() failWrites})>
            Function()
            create,
          })
        >[
          (
            name: 'local',
            create: () async {
              final prefs = FakePreferencesService();
              final owner = await KanaProgressRepository.load(prefs);
              return (
                owner: owner,
                failWrites: () {
                  prefs.failWrites.addAll(const [
                    ProgressStoreKeys.kanaStats,
                    ProgressStoreKeys.learnedUnits,
                    ProgressStoreKeys.seenUnlocks,
                  ]);
                },
              );
            },
          ),
          (
            name: 'fake',
            create: () async {
              final owner = FakeKanaProgressRepository();
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

  // #149 leaves one parity gap open by name: the fake and the production
  // owner must schedule ordinary and confusable kana the same way. Both
  // shrink a confusable kana's next interval by half (kConfusableChars), and
  // both restate that rule in their own recordAnswer, so a change to one can
  // silently diverge. These probes read the schedule the two owners actually
  // produce rather than the constant they contain.
  group('schedule parity for ordinary and confusable kana', () {
    final ordinary = kHiraganaGojuon.firstWhere((k) => k.character == 'う');
    final confusable = kHiraganaGojuon.firstWhere((k) => k.character == 'あ');

    final cases =
        <({String name, Future<KanaProgressRepository> Function() create})>[
          (
            name: 'local',
            create: () => KanaProgressRepository.load(FakePreferencesService()),
          ),
          (name: 'fake', create: () async => FakeKanaProgressRepository()),
        ];

    for (final spec in cases) {
      group(spec.name, () {
        test(
          'a correct answer halves the interval for a confusable kana',
          () async {
            final owner = await spec.create();

            await owner.recordAnswer(ordinary, correct: true, at: at);
            await owner.recordAnswer(confusable, correct: true, at: at);

            final ordinaryMins = owner
                .statFor(ordinary)
                .dueAt!
                .difference(at)
                .inMinutes;
            final confusableMins = owner
                .statFor(confusable)
                .dueAt!
                .difference(at)
                .inMinutes;

            expect(
              ordinaryMins,
              const Duration(days: 1).inMinutes,
              reason:
                  'the first correct answer no longer schedules one day out',
            );
            expect(
              confusableMins,
              ordinaryMins ~/ 2,
              reason:
                  'a confusable kana was not scheduled at half the interval',
            );
            expect(
              owner.statFor(confusable).srsLevel,
              owner.statFor(ordinary).srsLevel,
              reason: 'the scale changed the level rather than the interval',
            );
          },
        );

        test('a wrong answer halves the relearn interval too', () async {
          final owner = await spec.create();

          await owner.recordAnswer(ordinary, correct: false, at: at);
          await owner.recordAnswer(confusable, correct: false, at: at);

          final ordinaryMins = owner
              .statFor(ordinary)
              .dueAt!
              .difference(at)
              .inMinutes;
          final confusableMins = owner
              .statFor(confusable)
              .dueAt!
              .difference(at)
              .inMinutes;

          expect(
            ordinaryMins,
            10,
            reason: 'level 0 no longer relearns in 10 minutes',
          );
          expect(
            confusableMins,
            ordinaryMins ~/ 2,
            reason: 'a confusable kana was not relearned at half the interval',
          );
        });

        test('prompted practice renews no schedule on either kana', () async {
          final owner = await spec.create();

          await owner.recordAnswer(ordinary, correct: true, at: at);
          await owner.recordAnswer(confusable, correct: true, at: at);
          final ordinaryDue = owner.statFor(ordinary).dueAt;
          final confusableDue = owner.statFor(confusable).dueAt;

          await owner.recordPromptedPractice(
            ordinary,
            at: at.add(const Duration(hours: 1)),
          );
          await owner.recordPromptedPractice(
            confusable,
            at: at.add(const Duration(hours: 1)),
          );

          expect(owner.statFor(ordinary).dueAt, ordinaryDue);
          expect(owner.statFor(confusable).dueAt, confusableDue);
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

        final owner = tester
            .element(find.byType(KanaLoopApp))
            .read<KanaProgressRepository>();
        expect(owner, isA<LocalKanaProgressRepository>());
        expect(
          identical(
            owner,
            tester
                .element(find.byType(KanaLoopApp))
                .read<KanaProgressRepository>(),
          ),
          isTrue,
        );
      },
    );

    testWidgets('an injected fake is the same instance the tree reads', (
      tester,
    ) async {
      final fake = FakeKanaProgressRepository();
      await tester.pumpWidget(
        await bootstrap(
          prefs: FakePreferencesService(),
          speech: const SilentSpeechService(),
          analytics: InMemoryAnalyticsLog(),
          kana: fake,
        ),
        duration: Duration.zero,
      );
      await tester.pump();

      final composed = tester
          .element(find.byType(KanaLoopApp))
          .read<KanaProgressRepository>();
      expect(identical(composed, fake), isTrue);
      expect(composed, isNot(isA<LocalKanaProgressRepository>()));
    });
  });
}
