// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const all = kHiraganaGojuon;
  final now = DateTime(2026, 5, 29, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty', () async {
    final store = await KanaProgressRepository.load();
    expect(store.seenCount, 0);
    expect(store.totalCount, 208); // 92 gojūon + 116 extended
    expect(store.statFor(all.first).isSeen, isFalse);
  });

  test('recordAnswer updates seen/correct/wrong and lastReviewedAt', () async {
    final store = await KanaProgressRepository.load();
    final kana = all.first;

    await store.recordAnswer(kana, correct: true, at: now);
    await store.recordAnswer(kana, correct: false, at: now);

    final stat = store.statFor(kana);
    expect(stat.seenCount, 2);
    expect(stat.correctCount, 1);
    expect(stat.wrongCount, 1);
    expect(stat.lastReviewedAt, now);
    expect(store.seenCount, 1);
  });

  test('persists across reloads', () async {
    final store = await KanaProgressRepository.load();
    await store.recordAnswer(all[5], correct: true, at: now);

    final reloaded = await KanaProgressRepository.load();
    final stat = reloaded.statFor(all[5]);
    expect(stat.seenCount, 1);
    expect(stat.correctCount, 1);
    expect(stat.lastReviewedAt, now);
  });

  test('scored listening freshness survives reload and still ages', () async {
    final store = await KanaProgressRepository.load();
    final kana = all[5];
    await store.recordAnswer(
      kana,
      correct: true,
      at: now,
      latencyMs: 400,
      listening: true,
    );
    await store.recordAnswer(
      kana,
      correct: true,
      at: now.add(const Duration(minutes: 1)),
      latencyMs: 400,
      listening: true,
    );

    final reloaded = await KanaProgressRepository.load();
    final stat = reloaded.statFor(kana);
    expect(stat.listenSeenCount, 2);
    expect(stat.listenCorrectCount, 2);
    expect(stat.lastListenAt, now.add(const Duration(minutes: 1)));
    expect(
      stat.hasRecentListening(now: now.add(const Duration(days: 1))),
      isTrue,
    );
    expect(
      stat.listeningPendingRecheck(now: now.add(const Duration(days: 8))),
      isTrue,
    );
    expect(
      stat.hasReliableListening(now: now.add(const Duration(days: 40))),
      isTrue,
    );
  });

  test('status classification reflects accuracy', () async {
    final store = await KanaProgressRepository.load();
    final kana = all[2];
    for (var i = 0; i < 5; i++) {
      await store.recordAnswer(kana, correct: true, at: now);
    }
    expect(store.statFor(kana).status, KanaStatus.strong);
    expect(store.countWithStatus(KanaStatus.strong), 1);
    expect(store.countWithStatus(KanaStatus.unseen), 207);
  });

  test('reset clears everything', () async {
    final store = await KanaProgressRepository.load();
    await store.recordAnswer(all[0], correct: true, at: now);
    await store.markUnitLearned('hira_row_0');
    await store.markUnlockSeen('words');
    await store.reset();
    expect(store.seenCount, 0);
    expect(store.isUnitLearned('hira_row_0'), isFalse);
    expect(store.isUnlockSeen('words'), isFalse);
    expect(store.seenUnlocks, isEmpty);
  });

  group('seen unlocks', () {
    test('marks an unlock seen and persists across reloads', () async {
      final store = await KanaProgressRepository.load();
      expect(store.isUnlockSeen('words'), isFalse);

      await store.markUnlockSeen('words');
      expect(store.isUnlockSeen('words'), isTrue);
      expect(store.seenUnlocks, {'words'});

      final reloaded = await KanaProgressRepository.load();
      expect(reloaded.isUnlockSeen('words'), isTrue);
    });

    test('marking the same unlock twice is idempotent', () async {
      final store = await KanaProgressRepository.load();
      await store.markUnlockSeen('phrases');
      await store.markUnlockSeen('phrases');
      expect(store.seenUnlocks, {'phrases'});
    });

    test('a malformed stored value is recovery-required, not silently '
        'empty', () async {
      SharedPreferences.setMockInitialValues({'seen_unlocks_v1': 'not json'});
      final store = await KanaProgressRepository.load();
      expect(store.seenUnlocks, isEmpty);
      expect(store.seenUnlocksHealth, StoreHealth.recoveryRequired);
    });
  });

  group('learned units', () {
    test('marks a unit learned and persists across reloads', () async {
      final store = await KanaProgressRepository.load();
      expect(store.isUnitLearned('hira_row_1'), isFalse);

      await store.markUnitLearned('hira_row_1');
      expect(store.isUnitLearned('hira_row_1'), isTrue);
      expect(store.learnedUnitCount, 1);

      final reloaded = await KanaProgressRepository.load();
      expect(reloaded.isUnitLearned('hira_row_1'), isTrue);
    });

    test('marking the same unit twice is idempotent', () async {
      final store = await KanaProgressRepository.load();
      await store.markUnitLearned('hira_row_2');
      await store.markUnitLearned('hira_row_2');
      expect(store.learnedUnitCount, 1);
    });
  });

  test('confusable kana get a halved review interval', () async {
    final store = await KanaProgressRepository.load();
    final ki = all.firstWhere((k) => k.character == 'き'); // き is in a set
    await store.recordAnswer(ki, correct: true, at: now, latencyMs: 200);
    // level 1 base = 1 day (1440 min); confusable scale 0.5 → 720.
    expect(store.statFor(ki).dueAt!.difference(now).inMinutes, 720);
  });

  group('data-loss firewall', () {
    const statsKey = 'kana_stats_v1';
    const statsLastGoodKey = 'kana_stats_last_good_v1';
    const statsQuarantineKey = 'kana_stats_quarantine_v1';
    const learnedKey = 'learned_units_v1';
    const learnedQuarantineKey = 'learned_units_quarantine_v1';
    const unlocksKey = 'seen_unlocks_v1';
    const unlocksQuarantineKey = 'seen_unlocks_quarantine_v1';

    // Hand-written legacy v1 payload (NOT produced by today's encoder) so the
    // wire format itself stays pinned.
    const legacyStats =
        '{"あ":{"s":3,"c":2,"w":1,"l":1748509200000},'
        '"い":{"s":5,"c":5,"w":0,"l":1748509200000,"sl":2,"d":1748595600000,'
        '"al":650,"vl":1200}}';

    Kana kana(String char) => all.firstWhere((k) => k.character == char);

    test('hand-written legacy v1 JSON loads completely', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: legacyStats,
        learnedKey: '["hira_row_0","hira_row_1"]',
        unlocksKey: '["words"]',
      });
      final store = await KanaProgressRepository.load();

      final a = store.statFor(kana('あ'));
      expect(a.seenCount, 3);
      expect(a.correctCount, 2);
      expect(a.wrongCount, 1);
      expect(
        a.lastReviewedAt,
        DateTime.fromMillisecondsSinceEpoch(1748509200000),
      );
      final i = store.statFor(kana('い'));
      expect(i.srsLevel, 2);
      expect(i.dueAt, DateTime.fromMillisecondsSinceEpoch(1748595600000));
      expect(i.avgLatencyMs, 650);
      expect(i.varLatencyMs2, 1200);
      expect(store.isUnitLearned('hira_row_0'), isTrue);
      expect(store.isUnitLearned('hira_row_1'), isTrue);
      expect(store.isUnlockSeen('words'), isTrue);
      expect(store.statsHealth, StoreHealth.loaded);
      expect(store.learnedUnitsHealth, StoreHealth.loaded);
      expect(store.seenUnlocksHealth, StoreHealth.loaded);
    });

    test('one corrupt stats entry is dropped, the rest survive', () async {
      const raw =
          '{"あ":{"s":3,"c":2,"w":1},"い":"garbage","う":{"s":1,"c":1,"w":0}}';
      SharedPreferences.setMockInitialValues({statsKey: raw});
      final store = await KanaProgressRepository.load();

      expect(store.statFor(kana('あ')).seenCount, 3);
      expect(store.statFor(kana('う')).seenCount, 1);
      expect(store.statFor(kana('い')).isSeen, isFalse);
      expect(store.statsHealth, StoreHealth.salvaged);
      // The exact damaged payload was preserved before anything replaces it.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(statsQuarantineKey), raw);
    });

    test('one non-string learned unit id keeps the other ids', () async {
      const raw = '["hira_row_0",7,"hira_row_1"]';
      SharedPreferences.setMockInitialValues({learnedKey: raw});
      final store = await KanaProgressRepository.load();

      expect(store.isUnitLearned('hira_row_0'), isTrue);
      expect(store.isUnitLearned('hira_row_1'), isTrue);
      expect(store.learnedUnitCount, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(learnedQuarantineKey), raw);
    });

    test('one non-string seen unlock keeps the other ids', () async {
      const raw = '["words",3]';
      SharedPreferences.setMockInitialValues({unlocksKey: raw});
      final store = await KanaProgressRepository.load();

      expect(store.seenUnlocks, {'words'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(unlocksQuarantineKey), raw);
    });

    test('a malformed stats primary restores from last-known-good', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        statsLastGoodKey: legacyStats,
      });
      final store = await KanaProgressRepository.load();

      expect(store.statFor(kana('あ')).seenCount, 3);
      expect(store.statFor(kana('い')).srsLevel, 2);
      expect(store.statsHealth, StoreHealth.restored);
      final prefs = await SharedPreferences.getInstance();
      // Exact corrupt raw preserved; the primary itself is never rewritten
      // by a load.
      expect(prefs.getString(statsQuarantineKey), 'not json');
      expect(prefs.getString(statsKey), 'not json');
    });

    test(
      'an empty-string primary is corruption, not a fresh install',
      () async {
        SharedPreferences.setMockInitialValues({
          statsKey: '',
          statsLastGoodKey: legacyStats,
        });
        final store = await KanaProgressRepository.load();

        expect(store.statFor(kana('あ')).seenCount, 3);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(statsQuarantineKey), '');
      },
    );

    test('a wrong top-level type restores from last-known-good', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: '[1,2,3]',
        statsLastGoodKey: legacyStats,
      });
      final store = await KanaProgressRepository.load();
      expect(store.statFor(kana('あ')).seenCount, 3);
    });

    test('a mutation after restore persists the restored state', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        statsLastGoodKey: legacyStats,
      });
      final store = await KanaProgressRepository.load();
      await store.recordAnswer(kana('か'), correct: true, at: now);

      final reloaded = await KanaProgressRepository.load();
      expect(reloaded.statFor(kana('あ')).seenCount, 3); // from last-good
      expect(reloaded.statFor(kana('か')).seenCount, 1); // the new answer
    });

    test('a malformed primary with no last-known-good is quarantined before '
        'the next write replaces it', () async {
      SharedPreferences.setMockInitialValues({statsKey: 'not json'});
      final store = await KanaProgressRepository.load();
      expect(store.seenCount, 0);
      final prefs = await SharedPreferences.getInstance();
      // The load itself must leave the damaged payload in place.
      expect(prefs.getString(statsKey), 'not json');

      await store.recordAnswer(kana('あ'), correct: true, at: now);
      expect(prefs.getString(statsQuarantineKey), 'not json');
      expect(prefs.getString(statsKey), isNot('not json'));
    });

    test('a mutation preserves the valid primary to last-known-good before '
        'overwriting it', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, legacyStats);
      final store = await KanaProgressRepository.load(fake);

      await store.recordAnswer(kana('か'), correct: true, at: now);
      expect(fake.durable[statsLastGoodKey], legacyStats);
      expect(fake.writeLog, [statsLastGoodKey, statsKey]);
    });

    test(
      'a failed last-known-good write leaves the primary untouched',
      () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, legacyStats);
        fake.failWrites.add(statsLastGoodKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.recordAnswer(kana('か'), correct: true, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        expect(fake.durable[statsKey], legacyStats);
        expect(fake.durable.containsKey(statsLastGoodKey), isFalse);
      },
    );

    test(
      'a failed quarantine write leaves the corrupt primary untouched',
      () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, 'not json');
        fake.failWrites.add(statsQuarantineKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.recordAnswer(kana('あ'), correct: true, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        expect(fake.durable[statsKey], 'not json');
      },
    );

    test('a false from setString is a failure, not a success', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(statsKey);
      final store = await KanaProgressRepository.load(fake);

      await expectLater(
        store.recordAnswer(kana('あ'), correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
    });

    test('a failed persist is retried by the next mutation', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(statsKey);
      final store = await KanaProgressRepository.load(fake);

      await expectLater(
        store.recordAnswer(kana('あ'), correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
      fake.failWrites.clear();
      await store.recordAnswer(kana('い'), correct: true, at: now);

      final reloaded = await KanaProgressRepository.load(fake);
      expect(reloaded.statFor(kana('あ')).seenCount, 1);
      expect(reloaded.statFor(kana('い')).seenCount, 1);
    });

    test('near-simultaneous mutations serialize and both persist', () async {
      final fake = FakePreferencesService();
      final store = await KanaProgressRepository.load(fake);

      final first = store.recordAnswer(kana('あ'), correct: true, at: now);
      final second = store.recordAnswer(kana('い'), correct: false, at: now);
      await Future.wait([first, second]);

      expect(fake.sawOverlap, isFalse);
      final reloaded = await KanaProgressRepository.load(fake);
      expect(reloaded.statFor(kana('あ')).seenCount, 1);
      expect(reloaded.statFor(kana('い')).seenCount, 1);
    });

    test('mutations persist in submission order across stores', () async {
      final fake = FakePreferencesService();
      final store = await KanaProgressRepository.load(fake);

      await Future.wait([
        store.recordAnswer(kana('あ'), correct: true, at: now),
        store.markUnitLearned('hira_row_0'),
        store.markUnlockSeen('words'),
      ]);
      expect(fake.writeLog, [statsKey, learnedKey, unlocksKey]);
    });

    test('reset removes exactly the keys this repository owns', () async {
      final fake = FakePreferencesService();
      const owned = [
        statsKey,
        statsLastGoodKey,
        statsQuarantineKey,
        learnedKey,
        'learned_units_last_good_v1',
        learnedQuarantineKey,
        unlocksKey,
        'seen_unlocks_last_good_v1',
        unlocksQuarantineKey,
      ];
      for (final key in owned) {
        fake.seed(key, 'seeded');
      }
      fake.seed('kanji_stats_v1', 'not mine');
      fake.seed('some_other_key', 'not mine either');
      final store = await KanaProgressRepository.load(fake);

      await store.reset();
      for (final key in owned) {
        expect(fake.durable.containsKey(key), isFalse, reason: key);
      }
      expect(fake.durable['kanji_stats_v1'], 'not mine');
      expect(fake.durable['some_other_key'], 'not mine either');
    });

    test('a failed remove during reset is reported', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, legacyStats);
      fake.failRemoves.add(statsQuarantineKey);
      final store = await KanaProgressRepository.load(fake);

      await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
    });

    test('a malformed primary with no valid last-known-good is a typed '
        'recovery-required load', () async {
      // Missing last-known-good.
      SharedPreferences.setMockInitialValues({statsKey: 'not json'});
      var store = await KanaProgressRepository.load();
      expect(store.statsHealth, StoreHealth.recoveryRequired);
      expect(store.learnedUnitsHealth, StoreHealth.empty);
      expect(store.seenUnlocksHealth, StoreHealth.empty);
      expect(store.seenCount, 0);

      // An invalid last-known-good is no better than a missing one.
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        statsLastGoodKey: 'also not json',
      });
      store = await KanaProgressRepository.load();
      expect(store.statsHealth, StoreHealth.recoveryRequired);
      // The damaged payload is still exactly where it was.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(statsKey), 'not json');
    });

    group('dirty-store flush', () {
      test('a failed learned write is retried by the same id', () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(learnedKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.markUnitLearned('hira_row_0'),
          throwsA(isA<StoreWriteFailure>()),
        );
        fake.failWrites.clear();
        await store.markUnitLearned('hira_row_0'); // same id — must flush

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.isUnitLearned('hira_row_0'), isTrue);
      });

      test('a failed unlock write is retried by the same id', () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(unlocksKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.markUnlockSeen('words'),
          throwsA(isA<StoreWriteFailure>()),
        );
        fake.failWrites.clear();
        await store.markUnlockSeen('words'); // same id — must flush

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.isUnlockSeen('words'), isTrue);
      });

      test(
        'a stats mutation flushes an earlier failed learned write',
        () async {
          final fake = FakePreferencesService();
          fake.failWrites.add(learnedKey);
          final store = await KanaProgressRepository.load(fake);

          await expectLater(
            store.markUnitLearned('hira_row_0'),
            throwsA(isA<StoreWriteFailure>()),
          );
          fake.failWrites.clear();
          await store.recordAnswer(kana('あ'), correct: true, at: now);

          final reloaded = await KanaProgressRepository.load(fake);
          expect(reloaded.isUnitLearned('hira_row_0'), isTrue);
          expect(reloaded.statFor(kana('あ')).seenCount, 1);
        },
      );

      test(
        'a learned mutation flushes an earlier failed unlock write',
        () async {
          final fake = FakePreferencesService();
          fake.failWrites.add(unlocksKey);
          final store = await KanaProgressRepository.load(fake);

          await expectLater(
            store.markUnlockSeen('words'),
            throwsA(isA<StoreWriteFailure>()),
          );
          fake.failWrites.clear();
          await store.markUnitLearned('hira_row_0');

          final reloaded = await KanaProgressRepository.load(fake);
          expect(reloaded.isUnlockSeen('words'), isTrue);
          expect(reloaded.isUnitLearned('hira_row_0'), isTrue);
        },
      );

      test('a duplicate call does not fake success while the first write '
          'is pending', () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(learnedKey);
        final store = await KanaProgressRepository.load(fake);

        final first = store.markUnitLearned('hira_row_0');
        final second = store.markUnitLearned('hira_row_0');
        await expectLater(first, throwsA(isA<StoreWriteFailure>()));
        await expectLater(second, throwsA(isA<StoreWriteFailure>()));
      });

      test('the same kana answered twice near-simultaneously persists '
          'both', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);

        final first = store.recordAnswer(kana('あ'), correct: true, at: now);
        final second = store.recordAnswer(kana('あ'), correct: false, at: now);
        await Future.wait([first, second]);

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.statFor(kana('あ')).seenCount, 2);
      });

      test('a mutation submitted while a primary write is gated still '
          'persists durably', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);
        final gate = PlatformGate();
        fake.writeGates[statsKey] = gate;

        final first = store.recordAnswer(kana('あ'), correct: true, at: now);
        // Wait until the flush is INSIDE the gated platform write, then
        // submit the second mutation mid-write.
        await gate.entered;
        final second = store.recordAnswer(kana('い'), correct: true, at: now);
        gate.release();
        await Future.wait([first, second]);

        // The captured generation must not mark the mid-write mutation
        // clean: both answers reach the durable platform layer.
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('あ')).seenCount, 1);
        expect(fresh.statFor(kana('い')).seenCount, 1);
      });
    });

    group('load preservation honesty', () {
      const partialRaw = '{"あ":{"s":3,"c":2,"w":1},"い":"garbage"}';

      test('a quarantine false downgrades salvage to '
          'preservation-pending', () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, partialRaw);
        fake.failWrites.add(statsQuarantineKey);
        final store = await KanaProgressRepository.load(fake);

        expect(store.statsHealth, StoreHealth.preservationPending);
        expect(store.statFor(kana('あ')).seenCount, 3); // value still usable
        expect(fake.durable[statsKey], partialRaw); // primary untouched
        expect(fake.durable.containsKey(statsQuarantineKey), isFalse);
      });

      test('a quarantine exception downgrades salvage to '
          'preservation-pending', () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, partialRaw);
        fake.throwWrites.add(statsQuarantineKey);
        final store = await KanaProgressRepository.load(fake);

        expect(store.statsHealth, StoreHealth.preservationPending);
        expect(store.statFor(kana('あ')).seenCount, 3);
        expect(fake.durable[statsKey], partialRaw);
        expect(fake.durable.containsKey(statsQuarantineKey), isFalse);
      });

      test('a quarantine false downgrades restore to '
          'preservation-pending', () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, 'not json');
        fake.seed(statsLastGoodKey, legacyStats);
        fake.failWrites.add(statsQuarantineKey);
        final store = await KanaProgressRepository.load(fake);

        expect(store.statsHealth, StoreHealth.preservationPending);
        expect(store.statFor(kana('あ')).seenCount, 3); // restored value
        expect(fake.durable[statsKey], 'not json');
        expect(fake.durable.containsKey(statsQuarantineKey), isFalse);
      });

      test('a quarantine exception downgrades restore to '
          'preservation-pending', () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, 'not json');
        fake.seed(statsLastGoodKey, legacyStats);
        fake.throwWrites.add(statsQuarantineKey);
        final store = await KanaProgressRepository.load(fake);

        expect(store.statsHealth, StoreHealth.preservationPending);
        expect(store.statFor(kana('あ')).seenCount, 3);
        expect(fake.durable[statsKey], 'not json');
        expect(fake.durable.containsKey(statsQuarantineKey), isFalse);
      });
    });

    group('reset failure parity', () {
      /// Seeds one persisted entry per store so a failed reset has real
      /// data to reconcile against.
      Future<KanaProgressRepository> seeded(FakePreferencesService fake) async {
        final store = await KanaProgressRepository.load(fake);
        await store.recordAnswer(kana('あ'), correct: true, at: now);
        await store.markUnitLearned('hira_row_0');
        await store.markUnlockSeen('words');
        return store;
      }

      test('a reset failing at the unlocks stage reconciles memory with '
          'disk', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(unlocksKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
        // stats + learned really were removed; unlocks survived on disk —
        // memory must agree with the persistence layer on all three.
        expect(store.seenCount, 0);
        expect(store.isUnitLearned('hira_row_0'), isFalse);
        expect(store.isUnlockSeen('words'), isTrue);

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.seenCount, 0);
        expect(reloaded.isUnitLearned('hira_row_0'), isFalse);
        expect(reloaded.isUnlockSeen('words'), isTrue);
      });

      test('a reset failing at the learned stage reconciles memory with '
          'disk', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(learnedKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
        expect(store.seenCount, 0); // stats really removed
        expect(store.isUnitLearned('hira_row_0'), isTrue); // survived
        expect(store.isUnlockSeen('words'), isTrue); // never attempted

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.seenCount, 0);
        expect(reloaded.isUnitLearned('hira_row_0'), isTrue);
        expect(reloaded.isUnlockSeen('words'), isTrue);
      });

      test('a reset failing with an exception reconciles memory with '
          'disk', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.throwRemoves.add(statsKey);

        await expectLater(store.reset(), throwsA(isA<StateError>()));
        // Nothing was fully removed: memory shows the survivors again.
        expect(store.statFor(kana('あ')).seenCount, 1);
        expect(store.isUnitLearned('hira_row_0'), isTrue);
        expect(store.isUnlockSeen('words'), isTrue);

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.statFor(kana('あ')).seenCount, 1);
        expect(reloaded.isUnitLearned('hira_row_0'), isTrue);
        expect(reloaded.isUnlockSeen('words'), isTrue);
      });

      test('a failed reset can be retried once the fault clears', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(learnedKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
        fake.failRemoves.clear();
        await store.reset();

        expect(store.seenCount, 0);
        expect(store.isUnitLearned('hira_row_0'), isFalse);
        expect(store.isUnlockSeen('words'), isFalse);
        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.seenCount, 0);
        expect(reloaded.isUnitLearned('hira_row_0'), isFalse);
        expect(reloaded.isUnlockSeen('words'), isFalse);
        expect(fake.durable.containsKey(statsKey), isFalse);
        expect(fake.durable.containsKey(learnedKey), isFalse);
        expect(fake.durable.containsKey(unlocksKey), isFalse);
      });

      test('a failed reset never reconciles over a later-submitted '
          'mutation', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.throwRemoves.add(statsKey);

        final wipe = store.reset();
        final answer = store.recordAnswer(kana('か'), correct: true, at: now);
        await expectLater(wipe, throwsA(isA<StateError>()));
        await answer;

        // The later-submitted answer survives the reconcile, in memory and
        // on disk; the stores the reset failed to clear are reconciled.
        expect(store.statFor(kana('か')).seenCount, 1);
        expect(store.isUnitLearned('hira_row_0'), isTrue);
        expect(store.isUnlockSeen('words'), isTrue);
        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.statFor(kana('か')).seenCount, 1);
        expect(reloaded.statFor(kana('あ')).isSeen, isFalse);
      });

      test('recordAnswer then reset ends empty', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);

        final answer = store.recordAnswer(kana('い'), correct: true, at: now);
        final wipe = store.reset();
        await Future.wait([answer, wipe]);

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.seenCount, 0);
        expect(reloaded.isUnitLearned('hira_row_0'), isFalse);
      });

      test('reset then recordAnswer keeps only the answer', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);

        final wipe = store.reset();
        final answer = store.recordAnswer(kana('か'), correct: true, at: now);
        await Future.wait([wipe, answer]);

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.statFor(kana('か')).seenCount, 1);
        expect(reloaded.statFor(kana('あ')).isSeen, isFalse);
        expect(reloaded.isUnitLearned('hira_row_0'), isFalse);
        expect(reloaded.isUnlockSeen('words'), isFalse);
      });

      test('a false primary remove leaves same-process state equal to a '
          'durable restart', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(statsKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));

        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        // Durable truth: the stats primary survived the refused remove.
        expect(fresh.statFor(kana('あ')).seenCount, 1);
        // The same process must agree with what a restart would see — the
        // legacy cache (which already dropped the key) is not disk.
        expect(store.statFor(kana('あ')).seenCount, 1);
        expect(
          store.isUnitLearned('hira_row_0'),
          fresh.isUnitLearned('hira_row_0'),
        );
        expect(store.isUnlockSeen('words'), fresh.isUnlockSeen('words'));
      });

      test('an exception primary remove leaves same-process state equal to '
          'a durable restart', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.throwRemoves.add(statsKey);

        await expectLater(store.reset(), throwsA(isA<StateError>()));

        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('あ')).seenCount, 1);
        expect(store.statFor(kana('あ')).seenCount, 1);
        expect(store.isUnlockSeen('words'), fresh.isUnlockSeen('words'));
      });

      test('a partial reset keeps removed stores empty and matches durable '
          'state for the rest', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(learnedKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));

        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        // Stats really were removed — everywhere, restart included.
        expect(store.seenCount, 0);
        expect(fresh.seenCount, 0);
        // Learned survived durably; unlocks were never attempted.
        expect(fresh.isUnitLearned('hira_row_0'), isTrue);
        expect(store.isUnitLearned('hira_row_0'), isTrue);
        expect(fresh.isUnlockSeen('words'), isTrue);
        expect(store.isUnlockSeen('words'), isTrue);
      });

      test('a mutation submitted during reset reconciliation is not '
          'overwritten', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(statsKey);
        final reloadGate = PlatformGate();
        fake.reloadGate = reloadGate;

        final wipe = store.reset();
        // Wait until reconciliation is INSIDE its fresh platform reload,
        // then submit the mutation mid-await.
        await reloadGate.entered;
        final answer = store.recordAnswer(kana('か'), correct: true, at: now);
        reloadGate.release();

        await expectLater(wipe, throwsA(isA<StoreWriteFailure>()));
        await answer;

        // The later-submitted answer is never clobbered — and it reaches
        // the durable layer.
        expect(store.statFor(kana('か')).seenCount, 1);
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('か')).seenCount, 1);
        expect(fresh.statFor(kana('あ')).isSeen, isFalse);
      });

      test('a failed reload falls back to the pre-reset snapshot and stays '
          'dirty', () async {
        final fake = FakePreferencesService();
        final store = await seeded(fake);
        fake.failRemoves.add(learnedKey);
        fake.throwReloads = true;

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
        // Unknown durable state: conservative pre-reset snapshot, never a
        // fake-empty view.
        expect(store.isUnitLearned('hira_row_0'), isTrue);
        expect(store.isUnlockSeen('words'), isTrue);
        expect(store.seenCount, 0); // stats removal really succeeded

        // The unverified stores stayed dirty: the next mutation must
        // re-acknowledge each of them on the platform, exactly once.
        fake.throwReloads = false;
        fake.writeLog.clear();
        await store.recordAnswer(kana('か'), correct: true, at: now);
        expect(fake.writeLog.where((key) => key == learnedKey).length, 1);
        expect(fake.writeLog.where((key) => key == unlocksKey).length, 1);
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.isUnitLearned('hira_row_0'), isTrue);
        expect(fresh.isUnlockSeen('words'), isTrue);
      });

      test('an unawaited mutation racing reset must not mark the '
          'fallback-restored stores clean', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);
        await store.markUnitLearned('hira_row_0');
        await store.markUnlockSeen('words');
        fake.failRemoves.add(learnedKey);
        fake.throwReloads = true;

        // The answer's flush is queued BEFORE the reset removals, so it
        // runs first and persists the post-reset empty state — catching
        // every persisted generation up to the reset generation.
        final answer = store.recordAnswer(kana('あ'), correct: true, at: now);
        final wipe = store.reset();
        await answer; // the older flush completes fine
        await expectLater(wipe, throwsA(isA<StoreWriteFailure>()));

        // The double failure (remove + reload) restored the snapshot.
        expect(store.isUnitLearned('hira_row_0'), isTrue);
        expect(store.isUnlockSeen('words'), isTrue);

        // The restored stores must be DIRTY, not silently clean: the next
        // mutation has to re-acknowledge them on the platform.
        fake.writeLog.clear();
        fake.failRemoves.clear();
        fake.throwReloads = false;
        await store.recordAnswer(kana('い'), correct: true, at: now);
        expect(fake.writeLog, contains(learnedKey));
        expect(fake.writeLog, contains(unlocksKey));

        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.isUnitLearned('hira_row_0'), isTrue);
        expect(fresh.isUnlockSeen('words'), isTrue);
        // The stats store WAS fully removed — the reset must stick there.
        expect(fresh.statFor(kana('あ')).isSeen, isFalse);
        expect(fresh.statFor(kana('い')).seenCount, 1);
      });

      test('reconciliation after a failed reset applies full recovery '
          'semantics', () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, 'not json');
        fake.seed(statsLastGoodKey, legacyStats);
        final store = await KanaProgressRepository.load(fake);
        expect(store.statFor(kana('あ')).seenCount, 3); // from last-good
        // Fail before anything of the stats store is removed.
        fake.failRemoves.add(statsQuarantineKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
        // The corrupt primary + valid last-good must not collapse into a
        // fake-empty store during reconciliation.
        expect(store.statFor(kana('あ')).seenCount, 3);
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('あ')).seenCount, 3);
      });
    });

    group('legacy optimistic cache', () {
      test('a failed learned write is really flushed on retry', () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(learnedKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.markUnitLearned('hira_row_0'),
          throwsA(isA<StoreWriteFailure>()),
        );
        // The legacy cache already shows the value the platform refused —
        // the retry must still reach the platform, not trust the cache.
        expect(fake.cache[learnedKey], contains('hira_row_0'));
        expect(fake.durable.containsKey(learnedKey), isFalse);
        expect(fake.writeLog, isNot(contains(learnedKey)));

        fake.failWrites.clear();
        await store.markUnitLearned('hira_row_0');
        expect(fake.writeLog, contains(learnedKey));

        final reloaded = await KanaProgressRepository.load(fake);
        expect(reloaded.isUnitLearned('hira_row_0'), isTrue);
      });

      test('a preservation failure still leaves the primary intact', () async {
        final fake = FakePreferencesService();
        fake.seed(statsKey, legacyStats);
        fake.failWrites.add(statsLastGoodKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.recordAnswer(kana('か'), correct: true, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        expect(fake.durable[statsKey], legacyStats);
      });

      test('a reset remove failure keeps memory consistent with '
          'reload', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);
        await store.markUnlockSeen('words');
        fake.failRemoves.add(unlocksKey);

        await expectLater(store.reset(), throwsA(isA<StoreWriteFailure>()));
        // The legacy cache dropped the key before the platform refused —
        // memory and a reload through the same cache must agree.
        final reloaded = await KanaProgressRepository.load(fake);
        expect(store.isUnlockSeen('words'), reloaded.isUnlockSeen('words'));
        // And both must agree with what a process restart would see: the
        // platform never acknowledged the removal.
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.isUnlockSeen('words'), isTrue);
        expect(store.isUnlockSeen('words'), fresh.isUnlockSeen('words'));
      });
    });

    group('reset notification reentrancy', () {
      test('mutations submitted by a listener during the reset notification '
          'survive a restart', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);
        // Pre-existing data the reset will clear.
        await store.recordAnswer(kana('さ'), correct: true, at: now);
        await store.markUnitLearned('hira_row_0');
        await store.markUnlockSeen('words');

        // A one-shot synchronous listener that reacts to the reset's
        // notification by submitting one mutation to each store. The guard
        // stops the mutations' own notifications from re-entering it.
        late final void Function() listener;
        var fired = false;
        late final Future<void> laterAnswer;
        late final Future<void> laterLearned;
        late final Future<void> laterUnlock;
        listener = () {
          if (fired) return;
          fired = true;
          store.removeListener(listener);
          laterAnswer = store.recordAnswer(kana('あ'), correct: true, at: now);
          laterLearned = store.markUnitLearned('hira_row_5');
          laterUnlock = store.markUnlockSeen('phrases');
        };
        store.addListener(listener);

        final wipe = store.reset();
        // The listener fired synchronously inside reset()'s notification, so
        // its futures are already assigned by the time reset() returns.
        expect(fired, isTrue);
        await Future.wait([wipe, laterAnswer, laterLearned, laterUnlock]);

        // Same-process memory keeps the three later mutations and drops the
        // pre-reset data.
        expect(store.statFor(kana('あ')).seenCount, 1);
        expect(store.isUnitLearned('hira_row_5'), isTrue);
        expect(store.isUnlockSeen('phrases'), isTrue);
        expect(store.statFor(kana('さ')).isSeen, isFalse);
        expect(store.isUnitLearned('hira_row_0'), isFalse);
        expect(store.isUnlockSeen('words'), isFalse);

        // A fresh restart must see exactly the same durable state: the three
        // later mutations present, the pre-reset data gone. The later
        // mutations chained AFTER the reset removal, so they were never
        // clobbered.
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('あ')).seenCount, 1);
        expect(fresh.isUnitLearned('hira_row_5'), isTrue);
        expect(fresh.isUnlockSeen('phrases'), isTrue);
        expect(fresh.statFor(kana('さ')).isSeen, isFalse);
        expect(fresh.isUnitLearned('hira_row_0'), isFalse);
        expect(fresh.isUnlockSeen('words'), isFalse);
      });
    });

    group('reset removal invalidates a stale flush acknowledgement', () {
      test('a flush queued before reset does not strand a listener mutation '
          'as falsely clean across a restart', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);

        // Freeze the first mutation (D) inside its platform write so a second
        // mutation (A) is provably queued behind it and un-executed by the
        // time reset runs — the queue becomes D -> A -> reset -> B.
        final gate = PlatformGate();
        fake.writeGates[statsKey] = gate;
        final d = store.recordAnswer(kana('さ'), correct: true, at: now);
        await gate.entered;
        final a = store.recordAnswer(kana('き'), correct: true, at: now);

        // A one-shot listener submits one mutation per store during reset's
        // notification.
        late final void Function() listener;
        var fired = false;
        late final Future<void> bStats;
        late final Future<void> bLearned;
        late final Future<void> bUnlock;
        listener = () {
          if (fired) return;
          fired = true;
          store.removeListener(listener);
          bStats = store.recordAnswer(kana('あ'), correct: true, at: now);
          bLearned = store.markUnitLearned('hira_row_5');
          bUnlock = store.markUnlockSeen('phrases');
        };
        store.addListener(listener);

        final r = store.reset();
        expect(fired, isTrue);

        // Drain the queue: D writes, then A flushes the listener's CURRENT
        // memory and advances every persisted generation, then reset removes
        // the durable stores, then B.
        fake.writeGates.remove(statsKey);
        gate.release();
        await Future.wait([d, a, r, bStats, bLearned, bUnlock]);

        // Same-process memory keeps the three listener mutations and none of
        // the pre-reset data.
        expect(store.statFor(kana('あ')).seenCount, 1);
        expect(store.isUnitLearned('hira_row_5'), isTrue);
        expect(store.isUnlockSeen('phrases'), isTrue);
        expect(store.statFor(kana('さ')).isSeen, isFalse);
        expect(store.statFor(kana('き')).isSeen, isFalse);

        // The successful reset removal must have invalidated A's stale
        // acknowledgement (re-dirtied each store) so B truly rewrote it —
        // a fresh restart must show the three later mutations, not the empty
        // durable state the removal left behind.
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('あ')).seenCount, 1);
        expect(fresh.isUnitLearned('hira_row_5'), isTrue);
        expect(fresh.isUnlockSeen('phrases'), isTrue);
        expect(fresh.statFor(kana('さ')).isSeen, isFalse);
        expect(fresh.statFor(kana('き')).isSeen, isFalse);
      });

      test('a partial reset re-dirties an already-removed store that holds a '
          'post-reset mutation', () async {
        final fake = FakePreferencesService();
        final store = await KanaProgressRepository.load(fake);

        // Backlog D -> A before reset (same freeze technique).
        final gate = PlatformGate();
        fake.writeGates[statsKey] = gate;
        final d = store.recordAnswer(kana('さ'), correct: true, at: now);
        await gate.entered;
        final a = store.recordAnswer(kana('き'), correct: true, at: now);

        // Stats removes successfully; the learned stage then fails.
        fake.failRemoves.add(learnedKey);

        late final void Function() listener;
        var fired = false;
        late final Future<void> bStats;
        listener = () {
          if (fired) return;
          fired = true;
          store.removeListener(listener);
          bStats = store.recordAnswer(kana('あ'), correct: true, at: now);
        };
        store.addListener(listener);

        final r = store.reset();
        expect(fired, isTrue);
        fake.writeGates.remove(statsKey);
        gate.release();

        // Reset honestly throws (learned removal failed); the backlog and the
        // later stats mutation still complete.
        await expectLater(r, throwsA(isA<StoreWriteFailure>()));
        await Future.wait([d, a, bStats]);

        // The stats store WAS successfully removed and held a post-reset
        // mutation, so it must have been re-dirtied and rewritten — durable
        // across a restart, despite the reset overall throwing.
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(kana('あ')).seenCount, 1);
        expect(fresh.statFor(kana('さ')).isSeen, isFalse);
        expect(fresh.statFor(kana('き')).isSeen, isFalse);
      });
    });

    group(
      'a remove that throws after taking effect re-dirties later state',
      () {
        test('stats primary remove-after-effect rewrites a listener mutation '
            'even when reload also throws', () async {
          final fake = FakePreferencesService();
          final store = await KanaProgressRepository.load(fake);

          // Backlog D -> A before reset (freeze D inside its stats write).
          final gate = PlatformGate();
          fake.writeGates[statsKey] = gate;
          final d = store.recordAnswer(kana('さ'), correct: true, at: now);
          await gate.entered;
          final a = store.recordAnswer(kana('き'), correct: true, at: now);

          // The stats primary removal LANDS on durable storage, then the reply
          // throws; reload also throws, so durable truth is unconfirmable.
          fake.throwRemovesAfterEffect.add(statsKey);
          fake.throwReloads = true;

          late final void Function() listener;
          var fired = false;
          late final Future<void> bStats;
          listener = () {
            if (fired) return;
            fired = true;
            store.removeListener(listener);
            bStats = store.recordAnswer(kana('あ'), correct: true, at: now);
          };
          store.addListener(listener);

          final r = store.reset();
          expect(fired, isTrue);
          final rDone = expectLater(r, throwsA(isA<StateError>()));
          fake.writeGates.remove(statsKey);
          gate.release();
          await Future.wait([d, a, bStats, rDone]);

          // Same-process memory has B; the pre-reset data is gone.
          expect(store.statFor(kana('あ')).seenCount, 1);
          expect(store.statFor(kana('さ')).isSeen, isFalse);
          expect(store.statFor(kana('き')).isSeen, isFalse);

          // The removal may have erased the durable primary; its outcome was
          // unknown and a later mutation owned the store, so B must have been
          // forced to rewrite. A fresh restart must still show B.
          final fresh = await KanaProgressRepository.load(
            FakePreferencesService.restarted(fake),
          );
          expect(fresh.statFor(kana('あ')).seenCount, 1);
          expect(fresh.statFor(kana('さ')).isSeen, isFalse);
          expect(fresh.statFor(kana('き')).isSeen, isFalse);
        });

        test('learned primary remove-after-effect rewrites a listener '
            'mutation', () async {
          final fake = FakePreferencesService();
          final store = await KanaProgressRepository.load(fake);

          final gate = PlatformGate();
          fake.writeGates[statsKey] = gate;
          final d = store.recordAnswer(kana('さ'), correct: true, at: now);
          await gate.entered;
          final a = store.recordAnswer(kana('き'), correct: true, at: now);

          fake.throwRemovesAfterEffect.add(learnedKey);

          late final void Function() listener;
          var fired = false;
          late final Future<void> bLearned;
          listener = () {
            if (fired) return;
            fired = true;
            store.removeListener(listener);
            bLearned = store.markUnitLearned('hira_row_5');
          };
          store.addListener(listener);

          final r = store.reset();
          expect(fired, isTrue);
          final rDone = expectLater(r, throwsA(isA<StateError>()));
          fake.writeGates.remove(statsKey);
          gate.release();
          await Future.wait([d, a, bLearned, rDone]);

          expect(store.isUnitLearned('hira_row_5'), isTrue);
          expect(store.statFor(kana('さ')).isSeen, isFalse);

          final fresh = await KanaProgressRepository.load(
            FakePreferencesService.restarted(fake),
          );
          expect(fresh.isUnitLearned('hira_row_5'), isTrue);
          expect(fresh.statFor(kana('さ')).isSeen, isFalse);
          expect(fresh.statFor(kana('き')).isSeen, isFalse);
        });

        test('unlock primary remove-after-effect rewrites a listener '
            'mutation', () async {
          final fake = FakePreferencesService();
          final store = await KanaProgressRepository.load(fake);

          final gate = PlatformGate();
          fake.writeGates[statsKey] = gate;
          final d = store.recordAnswer(kana('さ'), correct: true, at: now);
          await gate.entered;
          final a = store.recordAnswer(kana('き'), correct: true, at: now);

          fake.throwRemovesAfterEffect.add(unlocksKey);

          late final void Function() listener;
          var fired = false;
          late final Future<void> bUnlock;
          listener = () {
            if (fired) return;
            fired = true;
            store.removeListener(listener);
            bUnlock = store.markUnlockSeen('phrases');
          };
          store.addListener(listener);

          final r = store.reset();
          expect(fired, isTrue);
          final rDone = expectLater(r, throwsA(isA<StateError>()));
          fake.writeGates.remove(statsKey);
          gate.release();
          await Future.wait([d, a, bUnlock, rDone]);

          expect(store.isUnlockSeen('phrases'), isTrue);
          expect(store.statFor(kana('さ')).isSeen, isFalse);

          final fresh = await KanaProgressRepository.load(
            FakePreferencesService.restarted(fake),
          );
          expect(fresh.isUnlockSeen('phrases'), isTrue);
          expect(fresh.statFor(kana('さ')).isSeen, isFalse);
          expect(fresh.statFor(kana('き')).isSeen, isFalse);
        });
      },
    );
  });

  group('flushPending — P0-B owner retry', () {
    const statsKey = 'kana_stats_v1';
    const learnedKey = 'learned_units_v1';
    const unlocksKey = 'seen_unlocks_v1';

    test(
      're-persists a failed stats write exactly once, no new mutation',
      () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(statsKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.recordAnswer(all.first, correct: true, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        // Fault cleared; retry with NO further domain mutation.
        fake.failWrites.clear();
        fake.writeLog.clear();
        await store.flushPending();

        expect(fake.writeLog.where((k) => k == statsKey).length, 1);
        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(all.first).seenCount, 1); // exactly once
      },
    );

    test('re-persists a failed learned-units write exactly once', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(learnedKey);
      final store = await KanaProgressRepository.load(fake);

      await expectLater(
        store.markUnitLearned('hira_row_0'),
        throwsA(isA<StoreWriteFailure>()),
      );
      fake.failWrites.clear();
      fake.writeLog.clear();
      await store.flushPending();

      expect(fake.writeLog.where((k) => k == learnedKey).length, 1);
      final fresh = await KanaProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.isUnitLearned('hira_row_0'), isTrue);
    });

    test('re-persists a failed seen-unlocks write exactly once', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(unlocksKey);
      final store = await KanaProgressRepository.load(fake);

      await expectLater(
        store.markUnlockSeen('words'),
        throwsA(isA<StoreWriteFailure>()),
      );
      fake.failWrites.clear();
      fake.writeLog.clear();
      await store.flushPending();

      expect(fake.writeLog.where((k) => k == unlocksKey).length, 1);
      final fresh = await KanaProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.isUnlockSeen('words'), isTrue);
    });

    test('is a safe no-op when nothing is dirty', () async {
      final fake = FakePreferencesService();
      final store = await KanaProgressRepository.load(fake);
      await store.recordAnswer(all.first, correct: true, at: now); // persisted
      fake.writeLog.clear();

      await store.flushPending();

      expect(fake.writeLog, isEmpty); // clean → writes nothing, still succeeds
    });

    test(
      'a failed flushPending keeps the queue alive for a later retry',
      () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(statsKey);
        final store = await KanaProgressRepository.load(fake);

        await expectLater(
          store.recordAnswer(all.first, correct: true, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        await expectLater(
          store.flushPending(), // still failing — surfaces honestly
          throwsA(isA<StoreWriteFailure>()),
        );
        fake.failWrites.clear();
        await store.flushPending(); // queue survived → now persists

        final fresh = await KanaProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statFor(all.first).seenCount, 1);
      },
    );

    test('queued behind a gated write, it does not interleave', () async {
      final fake = FakePreferencesService();
      final store = await KanaProgressRepository.load(fake);
      final gate = PlatformGate();
      fake.writeGates[statsKey] = gate;

      final mutation = store.recordAnswer(all.first, correct: true, at: now);
      await gate.entered; // frozen mid-write
      final flush = store.flushPending(); // queued strictly behind
      fake.writeGates.remove(statsKey);
      gate.release();
      await Future.wait([mutation, flush]);

      expect(fake.sawOverlap, isFalse);
    });
  });
}
