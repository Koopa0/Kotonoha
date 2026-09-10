// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 1, 12);
  const id = 'word:いぬ';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty', () async {
    final repo = await WordProgressRepository.load();
    expect(repo.seenItemCount, 0);
    expect(repo.statForItem(id).isSeen, isFalse);
  });

  test('records an answer and persists across reloads', () async {
    final repo = await WordProgressRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    expect(repo.statForItem(id).correctCount, 1);
    expect(repo.seenItemCount, 1);

    final reloaded = await WordProgressRepository.load();
    expect(reloaded.statForItem(id).correctCount, 1);
    expect(reloaded.statForItem(id).lastReviewedAt, now);
  });

  test('wrong answer resets the level; correct advances it', () async {
    final repo = await WordProgressRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    expect(repo.statForItem(id).srsLevel, 1);
    await repo.recordAnswer(id, correct: false, at: now);
    expect(repo.statForItem(id).srsLevel, 0);
  });

  test('dueItemIds returns due items earliest-first', () async {
    final repo = await WordProgressRepository.load();
    const otherId = 'phrase:そらが あおい';
    // Insert the LATER-due item first, so a passing [id, otherId] result can
    // only come from the sort — insertion order alone would yield the
    // opposite order.
    await repo.recordAnswer(otherId, correct: true, at: now); // due +1 day
    await repo.recordAnswer(id, correct: false, at: now); // due +10 min

    expect(repo.dueItemIds(now), isEmpty); // nothing due yet
    expect(repo.dueItemIds(now.add(const Duration(minutes: 15))), [id]);
    expect(repo.dueItemIds(now.add(const Duration(days: 2))), [
      id,
      otherId,
    ]); // earliest dueAt first
  });

  test('reset clears everything', () async {
    final repo = await WordProgressRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    await repo.reset();
    expect(repo.seenItemCount, 0);
  });

  group('data-loss firewall', () {
    const statsKey = 'word_stats_v1';
    const lastGoodKey = 'word_stats_last_good_v1';
    const quarantineKey = 'word_stats_quarantine_v1';
    const otherId = 'phrase:そらが あおい';

    // Hand-typed JSON in WordStat's real encoding (this track was never
    // RT-gated, so unlike the kanji copy there is no retired legacy shape to
    // tolerate).
    const sampleStats =
        '{"word:いぬ":{"s":2,"c":2,"w":0,"l":1748509200000,"sl":2,'
        '"d":1748595600000},"phrase:そらが あおい":{"s":1,"c":0,"w":1,'
        '"l":1748509200000}}';

    test('hand-written JSON loads completely', () async {
      SharedPreferences.setMockInitialValues({statsKey: sampleStats});
      final repo = await WordProgressRepository.load();

      final inu = repo.statForItem(id);
      expect(inu.seenCount, 2);
      expect(inu.correctCount, 2);
      expect(inu.srsLevel, 2);
      expect(inu.dueAt, DateTime.fromMillisecondsSinceEpoch(1748595600000));
      final sora = repo.statForItem(otherId);
      expect(sora.wrongCount, 1);
      expect(repo.seenItemCount, 2);
      expect(repo.statsHealth, StoreHealth.loaded);
    });

    test('one corrupt entry is dropped, the rest survive', () async {
      const raw = '{"word:いぬ":{"s":2,"c":2,"w":0},"word:ねこ":42}';
      SharedPreferences.setMockInitialValues({statsKey: raw});
      final repo = await WordProgressRepository.load();

      expect(repo.statForItem(id).seenCount, 2);
      expect(repo.statForItem('word:ねこ').isSeen, isFalse);
      expect(repo.statsHealth, StoreHealth.salvaged);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(quarantineKey), raw);
    });

    test('a malformed primary restores from last-known-good', () async {
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        lastGoodKey: sampleStats,
      });
      final repo = await WordProgressRepository.load();

      expect(repo.statForItem(id).seenCount, 2);
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
      var repo = await WordProgressRepository.load();
      expect(repo.statsHealth, StoreHealth.recoveryRequired);
      expect(repo.seenItemCount, 0);

      // An invalid last-known-good is no better than a missing one.
      SharedPreferences.setMockInitialValues({
        statsKey: 'not json',
        lastGoodKey: 'also not json',
      });
      repo = await WordProgressRepository.load();
      expect(repo.statsHealth, StoreHealth.recoveryRequired);
      // The damaged payload is still exactly where it was.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(statsKey), 'not json');
    });

    test('a mutation preserves the valid primary to last-known-good before '
        'overwriting it', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, sampleStats);
      final repo = await WordProgressRepository.load(fake);

      await repo.recordAnswer('word:ねこ', correct: true, at: now);
      expect(fake.durable[lastGoodKey], sampleStats);
      expect(fake.writeLog, [lastGoodKey, statsKey]);
    });

    test('a failed preservation write leaves the primary untouched', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, sampleStats);
      fake.failWrites.add(lastGoodKey);
      final repo = await WordProgressRepository.load(fake);

      await expectLater(
        repo.recordAnswer(id, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
      expect(fake.durable[statsKey], sampleStats);
    });

    test('a false from setString is a failure, not a success', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(statsKey);
      final repo = await WordProgressRepository.load(fake);

      await expectLater(
        repo.recordAnswer(id, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
    });

    test(
      'near-simultaneous recordAnswers serialize and both persist',
      () async {
        final fake = FakePreferencesService();
        final repo = await WordProgressRepository.load(fake);

        final first = repo.recordAnswer(id, correct: true, at: now);
        final second = repo.recordAnswer(otherId, correct: false, at: now);
        await Future.wait([first, second]);

        expect(fake.sawOverlap, isFalse);
        final reloaded = await WordProgressRepository.load(fake);
        expect(reloaded.statForItem(id).seenCount, 1);
        expect(reloaded.statForItem(otherId).seenCount, 1);
      },
    );

    test('reset removes exactly the keys this repository owns', () async {
      final fake = FakePreferencesService();
      const owned = [statsKey, lastGoodKey, quarantineKey];
      for (final key in owned) {
        fake.seed(key, 'seeded');
      }
      // A sibling track's key must survive a 詞と句 reset untouched.
      fake.seed('kanji_stats_v1', 'not mine');
      final repo = await WordProgressRepository.load(fake);

      await repo.reset();
      for (final key in owned) {
        expect(fake.durable.containsKey(key), isFalse, reason: key);
      }
      expect(fake.durable['kanji_stats_v1'], 'not mine');
    });

    test('a failed remove during reset is reported', () async {
      final fake = FakePreferencesService();
      fake.seed(statsKey, sampleStats);
      fake.failRemoves.add(quarantineKey);
      final repo = await WordProgressRepository.load(fake);

      await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));
    });

    test('a failed primary remove during reset reconciles memory with disk '
        'instead of losing the still-durable answer', () async {
      final fake = FakePreferencesService();
      final repo = await WordProgressRepository.load(fake);
      await repo.recordAnswer(id, correct: true, at: now);
      fake.failRemoves.add(statsKey);

      await expectLater(repo.reset(), throwsA(isA<StoreWriteFailure>()));
      // The primary survived on disk — memory must not stay fake-empty.
      expect(repo.statForItem(id).seenCount, 1);

      final fresh = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.statForItem(id).seenCount, 1);
    });
  });

  group('flushPending — P0-B owner retry', () {
    const statsKey = 'word_stats_v1';

    test('re-persists a failed write exactly once, no new mutation', () async {
      final fake = FakePreferencesService();
      fake.failWrites.add(statsKey);
      final repo = await WordProgressRepository.load(fake);

      await expectLater(
        repo.recordAnswer(id, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
      // Fault cleared; retry with NO further domain mutation.
      fake.failWrites.clear();
      fake.writeLog.clear();
      await repo.flushPending();

      expect(fake.writeLog.where((k) => k == statsKey).length, 1);
      final fresh = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.statForItem(id).correctCount, 1); // exactly once
    });

    test('is a safe no-op when nothing is dirty', () async {
      final fake = FakePreferencesService();
      final repo = await WordProgressRepository.load(fake);
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
        final repo = await WordProgressRepository.load(fake);

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

        final fresh = await WordProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForItem(id).correctCount, 1);
      },
    );
  });

  group('introduce', () {
    const statsKey = 'word_stats_v1';

    test('an unseen item becomes seen at level 1 and persists', () async {
      final fake = FakePreferencesService();
      final repo = await WordProgressRepository.load(fake);

      await repo.introduce(id, at: now);

      expect(repo.statForItem(id).isSeen, isTrue);
      expect(repo.statForItem(id).srsLevel, 1);
      expect(repo.statForItem(id).seenCount, 1);
      expect(repo.statForItem(id).correctCount, 1);
      expect(fake.writeLog, hasLength(1)); // one flush landed on disk

      final reloaded = await WordProgressRepository.load(fake);
      expect(reloaded.statForItem(id).srsLevel, 1);
    });

    test(
      'a seen item is a no-op: unchanged state, no notification, no write',
      () async {
        final fake = FakePreferencesService();
        final repo = await WordProgressRepository.load(fake);
        await repo.recordAnswer(id, correct: true, at: now); // now seen

        final before = repo.statForItem(id);
        var notifications = 0;
        repo.addListener(() => notifications++);
        fake.writeLog.clear();

        final result = repo.introduce(id, at: now.add(const Duration(days: 1)));
        await expectLater(result, completes);

        // Same instance back — introduce's early return never touches the
        // stored stat, so this is stronger than a field-by-field comparison.
        expect(identical(repo.statForItem(id), before), isTrue);
        expect(notifications, 0);
        expect(fake.writeLog, isEmpty);
      },
    );

    test(
      'a seen item with a pending failed write flushes without a new mutation',
      () async {
        final fake = FakePreferencesService();
        fake.failWrites.add(statsKey);
        final repo = await WordProgressRepository.load(fake);

        await expectLater(
          repo.introduce(id, at: now),
          throwsA(isA<StoreWriteFailure>()),
        );
        final before = repo.statForItem(id);
        expect(before.seenCount, 1);
        expect(before.srsLevel, 1);

        await expectLater(
          repo.introduce(id, at: now.add(const Duration(minutes: 5))),
          throwsA(isA<StoreWriteFailure>()),
        );
        expect(identical(repo.statForItem(id), before), isTrue);
        // The primary never got a platform ack. last-good may hold the
        // cache-diverged snapshot RecoverableStore preserved before retrying.
        expect(fake.durable.containsKey(statsKey), isFalse);

        fake.failWrites.clear();
        await repo.introduce(id, at: now.add(const Duration(minutes: 10)));
        expect(identical(repo.statForItem(id), before), isTrue);

        final fresh = await WordProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.statForItem(id).seenCount, 1);
        expect(fresh.statForItem(id).correctCount, 1);
        expect(fresh.statForItem(id).srsLevel, 1);
      },
    );
  });
}
