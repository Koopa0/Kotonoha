// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 1, 12);
  const id = 'unit:人#ジン';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty and knows the full kanji set', () async {
    final repo = await KanjiReadingRepository.load();
    expect(repo.seenUnitCount, 0);
    expect(repo.allKanji.length, 110);
    expect(repo.statForUnit(id).isSeen, isFalse);
  });

  test('records an answer and persists across reloads', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    expect(repo.statForUnit(id).correctCount, 1);
    expect(repo.seenUnitCount, 1);

    final reloaded = await KanjiReadingRepository.load();
    expect(reloaded.statForUnit(id).correctCount, 1);
    expect(reloaded.statForUnit(id).lastReviewedAt, now);
  });

  test('wrong answer resets the level; correct advances it', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    expect(repo.statForUnit(id).srsLevel, 1);
    await repo.recordAnswer(id, correct: false, at: now);
    expect(repo.statForUnit(id).srsLevel, 0);
  });

  test('dueUnitIds returns due readings earliest-first', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now); // due ~1 day later
    // Nothing is due at recording time.
    expect(repo.dueUnitIds(now), isEmpty);
    // A week later it's due.
    expect(repo.dueUnitIds(now.add(const Duration(days: 7))), [id]);
  });

  test('reset clears everything', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    await repo.reset();
    expect(repo.seenUnitCount, 0);
  });

  group('data-loss firewall', () {
    const statsKey = 'kanji_units_v1';
    const lastGoodKey = 'kanji_units_last_good_v1';
    const quarantineKey = 'kanji_units_quarantine_v1';
    const otherId = 'unit:人#ひと';

    // Hand-written legacy v1 payload (NOT produced by today's encoder); the
    // retired timed fields 'al'/'vl' must still be tolerated and ignored.
    const legacyStats =
        '{"unit:人#ジン":{"s":2,"c":2,"w":0,"l":1748509200000,"sl":2,'
        '"d":1748595600000,"al":700,"vl":900},'
        '"unit:人#ひと":{"s":1,"c":0,"w":1,"l":1748509200000}}';

    test('hand-written legacy v1 JSON loads completely', () async {
      SharedPreferences.setMockInitialValues({statsKey: legacyStats});
      final repo = await KanjiReadingRepository.load();

      final jin = repo.statForUnit(id);
      expect(jin.seenCount, 2);
      expect(jin.correctCount, 2);
      expect(jin.srsLevel, 2);
      expect(jin.dueAt, DateTime.fromMillisecondsSinceEpoch(1748595600000));
      final hito = repo.statForUnit(otherId);
      expect(hito.wrongCount, 1);
      expect(repo.seenUnitCount, 2);
      expect(repo.statsHealth, StoreHealth.loaded);
    });

    test('one corrupt entry is dropped, the rest survive', () async {
      const raw = '{"unit:人#ジン":{"s":2,"c":2,"w":0},"unit:日#ニチ":42}';
      SharedPreferences.setMockInitialValues({statsKey: raw});
      final repo = await KanjiReadingRepository.load();

      expect(repo.statForUnit(id).seenCount, 2);
      expect(repo.statForUnit('unit:日#ニチ').isSeen, isFalse);
      expect(repo.statsHealth, StoreHealth.salvaged);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(quarantineKey), raw);
    });

    test('a malformed primary restores from last-known-good', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        lastGoodKey: legacyStats,
      });
      final repo = await KanjiReadingRepository.load();

      expect(repo.statForUnit(id).seenCount, 2);
      expect(repo.statsHealth, StoreHealth.restored);
      final prefs = await SharedPreferences.getInstance();
      // Exact corrupt raw preserved; the primary is never rewritten by a load.
      expect(prefs.getString(quarantineKey), 'not json');
      expect(prefs.getString(statsKey), 'not json');
    });

    test('a malformed primary with no valid last-known-good is a typed '
        'recovery-required load', () async {
      // Missing last-known-good.
      SharedPreferences.setMockInitialValues({statsKey: 'not json'});
      var repo = await KanjiReadingRepository.load();
      expect(repo.statsHealth, StoreHealth.recoveryRequired);
      expect(repo.seenUnitCount, 0);

      // An invalid last-known-good is no better than a missing one.
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        lastGoodKey: 'also not json',
      });
      repo = await KanjiReadingRepository.load();
      expect(repo.statsHealth, StoreHealth.recoveryRequired);
      // The damaged payload is still exactly where it was.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(statsKey), 'not json');
    });

    test('a mutation preserves the valid primary to last-known-good before '
        'overwriting it', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, legacyStats);
      final repo = await KanjiReadingRepository.load(fake);

      await repo.recordAnswer('unit:日#ニチ', correct: true, at: now);
      expect(fake.durable[lastGoodKey], legacyStats);
      expect(fake.writeLog, [lastGoodKey, statsKey]);
    });

    test('a failed preservation write leaves the primary untouched', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, legacyStats);
      fake.failWrites.add(lastGoodKey);
      final repo = await KanjiReadingRepository.load(fake);

      await expectLater(
        repo.recordAnswer(id, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
      expect(fake.durable[statsKey], legacyStats);
    });

    test('a false from setString is a failure, not a success', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(statsKey);
      final repo = await KanjiReadingRepository.load(fake);

      await expectLater(
        repo.recordAnswer(id, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
    });

    test(
      'near-simultaneous recordAnswers serialize and both persist',
      () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);

        final first = repo.recordAnswer(id, correct: true, at: now);
        final second = repo.recordAnswer(otherId, correct: false, at: now);
        await Future.wait([first, second]);

        expect(fake.sawOverlap, isFalse);
        final reloaded = await KanjiReadingRepository.load(fake);
        expect(reloaded.statForUnit(id).seenCount, 1);
        expect(reloaded.statForUnit(otherId).seenCount, 1);
      },
    );

    test('reset removes exactly the keys this repository owns', () async {
      final fake = FakePreferencesService();
      const owned = [statsKey, lastGoodKey, quarantineKey];
      for (final key in owned) {
        fake.seed(key, 'seeded');
      }
      fake.seed('kana_stats_v1', 'not mine');
      final repo = await KanjiReadingRepository.load(fake);

      await repo.reset();
      for (final key in owned) {
        expect(fake.durable.containsKey(key), isFalse, reason: key);
      }
      expect(fake.durable['kana_stats_v1'], 'not mine');
    });

    test('a failed remove during reset is reported', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, legacyStats);
      fake.failRemoves.add(quarantineKey);
      final repo = await KanjiReadingRepository.load(fake);

      await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));
    });

    group('acceptance repair', () {
      test('the same reading answered twice near-simultaneously persists '
          'both', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);

        final first = repo.recordAnswer(id, correct: true, at: now);
        final second = repo.recordAnswer(id, correct: true, at: now);
        await Future.wait([first, second]);

        final reloaded = await KanjiReadingRepository.load(fake);
        expect(reloaded.statForUnit(id).seenCount, 2);
      });

      test('a reset remove failure reconciles memory with disk', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);
        await repo.recordAnswer(id, correct: true, at: now);
        fake.failRemoves.add(statsKey);

        await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));
        // The primary survived on disk — memory must not stay fake-empty.
        expect(repo.statForUnit(id).seenCount, 1);

        final reloaded = await KanjiReadingRepository.load(fake);
        expect(reloaded.statForUnit(id).seenCount, 1);
      });

      test('a failed reset can be retried once the fault clears', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);
        await repo.recordAnswer(id, correct: true, at: now);
        fake.failRemoves.add(statsKey);

        await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));
        fake.failRemoves.clear();
        await repo.reset();

        expect(repo.seenUnitCount, 0);
        final reloaded = await KanjiReadingRepository.load(fake);
        expect(reloaded.seenUnitCount, 0);
        expect(fake.durable.containsKey(statsKey), isFalse);
      });

      test('a false primary remove leaves same-process state equal to a '
          'durable restart', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);
        await repo.recordAnswer(id, correct: true, at: now);
        fake.failRemoves.add(statsKey);

        await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));

        final fresh = await KanjiReadingRepository.load(
          FakePreferencesService.restarted(fake),
        );
        // Durable truth: the primary survived the refused remove, and the
        // same process must agree with what a restart would see.
        expect(fresh.statForUnit(id).seenCount, 1);
        expect(repo.statForUnit(id).seenCount, 1);
      });

      test('a failed reload falls back to the pre-reset snapshot and '
          'stays dirty', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);
        await repo.recordAnswer(id, correct: true, at: now);
        fake.failRemoves.add(statsKey);
        fake.throwReloads = true;

        await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));
        // Unknown durable state: conservative pre-reset snapshot.
        expect(repo.statForUnit(id).seenCount, 1);

        // The unverified store stayed dirty: the next mutation flushes the
        // restored snapshot back to the platform.
        fake.failRemoves.clear();
        fake.throwReloads = false;
        fake.writeLog.clear();
        await repo.recordAnswer(otherId, correct: true, at: now);
        expect(fake.writeLog.where((key) => key == statsKey).length, 1);

        final fresh = await KanjiReadingRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForUnit(id).seenCount, 1);
        expect(fresh.statForUnit(otherId).seenCount, 1);
      });

      test('a listener recordAnswer during the reset notification survives '
          'a restart', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);
        await repo.recordAnswer(id, correct: true, at: now); // pre-existing

        // A one-shot synchronous listener that records a different reading
        // in reaction to the reset's notification. The guard stops that
        // record's own notification from re-entering it.
        late final void Function() listener;
        var fired = false;
        late final Future<void> later;
        listener = () {
          if (fired) return;
          fired = true;
          repo.removeListener(listener);
          later = repo.recordAnswer(otherId, correct: true, at: now);
        };
        repo.addListener(listener);

        final wipe = repo.reset();
        expect(fired, isTrue);
        await Future.wait([wipe, later]);

        // Same-process: the later answer stayed, the pre-reset one cleared.
        expect(repo.statForUnit(otherId).seenCount, 1);
        expect(repo.statForUnit(id).isSeen, isFalse);

        // A fresh restart must agree: the later answer chained AFTER the
        // reset removal, so it is durable.
        final fresh = await KanjiReadingRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForUnit(otherId).seenCount, 1);
        expect(fresh.statForUnit(id).isSeen, isFalse);
      });

      test('a flush queued before reset does not strand a listener '
          'recordAnswer as falsely clean across a restart', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);

        // Freeze the first mutation (D) inside its platform write so a second
        // mutation (A) is queued behind it: the queue becomes D -> A ->
        // reset -> B.
        final gate = PlatformGate();
        fake.writeGates[statsKey] = gate;
        final d = repo.recordAnswer(id, correct: true, at: now);
        await gate.entered;
        final a = repo.recordAnswer('unit:日#ニチ', correct: true, at: now);

        late final void Function() listener;
        var fired = false;
        late final Future<void> b;
        listener = () {
          if (fired) return;
          fired = true;
          repo.removeListener(listener);
          b = repo.recordAnswer(otherId, correct: true, at: now);
        };
        repo.addListener(listener);

        final r = repo.reset();
        expect(fired, isTrue);

        // Drain the queue: D writes, then A flushes the listener's CURRENT
        // memory and advances the persisted generation, then reset removes
        // the durable store, then B.
        fake.writeGates.remove(statsKey);
        gate.release();
        await Future.wait([d, a, r, b]);

        // Same-process memory keeps the later answer, drops the pre-reset
        // ones.
        expect(repo.statForUnit(otherId).seenCount, 1);
        expect(repo.statForUnit(id).isSeen, isFalse);
        expect(repo.statForUnit('unit:日#ニチ').isSeen, isFalse);

        // The successful reset removal must have invalidated A's stale
        // acknowledgement so B truly rewrote the store — durable across a
        // restart.
        final fresh = await KanjiReadingRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForUnit(otherId).seenCount, 1);
        expect(fresh.statForUnit(id).isSeen, isFalse);
        expect(fresh.statForUnit('unit:日#ニチ').isSeen, isFalse);
      });

      test('a stats primary remove that throws after taking effect still '
          'rewrites a listener recordAnswer', () async {
        final fake = FakePreferencesService();
        final repo = await KanjiReadingRepository.load(fake);

        // Backlog D -> A before reset (freeze D inside its stats write).
        final gate = PlatformGate();
        fake.writeGates[statsKey] = gate;
        final d = repo.recordAnswer(id, correct: true, at: now);
        await gate.entered;
        final a = repo.recordAnswer('unit:日#ニチ', correct: true, at: now);

        // The primary removal LANDS on durable storage, then the reply throws.
        fake.throwRemovesAfterEffect.add(statsKey);

        late final void Function() listener;
        var fired = false;
        late final Future<void> b;
        listener = () {
          if (fired) return;
          fired = true;
          repo.removeListener(listener);
          b = repo.recordAnswer(otherId, correct: true, at: now);
        };
        repo.addListener(listener);

        final r = repo.reset();
        expect(fired, isTrue);
        final rDone = expectLater(r, throwsA(isA<StateError>()));
        fake.writeGates.remove(statsKey);
        gate.release();
        await Future.wait([d, a, b, rDone]);

        // Same-process memory has B; the pre-reset answers are gone.
        expect(repo.statForUnit(otherId).seenCount, 1);
        expect(repo.statForUnit(id).isSeen, isFalse);
        expect(repo.statForUnit('unit:日#ニチ').isSeen, isFalse);

        // The removal may have erased the durable primary; its outcome was
        // unknown and a later mutation owned the store, so B must have been
        // forced to rewrite. A fresh restart must still show B.
        final fresh = await KanjiReadingRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForUnit(otherId).seenCount, 1);
        expect(fresh.statForUnit(id).isSeen, isFalse);
        expect(fresh.statForUnit('unit:日#ニチ').isSeen, isFalse);
      });
    });
  });

  group('flushPending — P0-B owner retry', () {
    const statsKey = 'kanji_units_v1';

    test('re-persists a failed write exactly once, no new mutation', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(statsKey);
      final repo = await KanjiReadingRepository.load(fake);

      await expectLater(
        repo.recordAnswer(id, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
      // Fault cleared; retry with NO further domain mutation.
      fake.failWrites.clear();
      fake.writeLog.clear();
      await repo.flushPending();

      expect(fake.writeLog.where((k) => k == statsKey).length, 1);
      final fresh = await KanjiReadingRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.statForUnit(id).correctCount, 1); // exactly once
    });

    test('is a safe no-op when nothing is dirty', () async {
      final fake = FakePreferencesService();
      final repo = await KanjiReadingRepository.load(fake);
      await repo.recordAnswer(id, correct: true, at: now); // persisted
      fake.writeLog.clear();

      await repo.flushPending();

      expect(fake.writeLog, isEmpty);
    });

    test(
      'a failed flushPending keeps the queue alive for a later retry',
      () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(statsKey);
        final repo = await KanjiReadingRepository.load(fake);

        await expectLater(
          repo.recordAnswer(id, correct: true, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        await expectLater(
          repo.flushPending(),
          throwsA(isA<StoreWriteFailure>()),
        );
        fake.failWrites.clear();
        await repo.flushPending();

        final fresh = await KanjiReadingRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForUnit(id).correctCount, 1);
      },
    );
  });
}
