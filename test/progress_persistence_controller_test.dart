// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// P0-B — the app-scoped persistence owner's logic: observable saving/retry
// state, exactly-one failure surface, per-repository isolation, stale/newer
// completion ordering, retry that only flushes (never replays a domain
// mutation), best-effort drain, and the guarantee that every tracked error is
// observed rather than left uncaught.
//
// Deterministic by construction — no wall-clock waits and no zero-delay hops.
// Completion order is controlled with Completers; the controller is awaited
// either by holding a tracked future (`settled`) or by waiting on a real
// notification (`nextWhere`), never by guessing the event loop.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

void main() {
  // Awaiting a tracked future resumes AFTER the controller's own handler on it
  // (registered first, FIFO microtask order) — so the controller has settled it.
  Future<void> settled(Future<void> tracked) =>
      tracked.catchError((Object _) {});

  // Resolve once the controller reaches a state, driven by a real notification.
  Future<void> nextWhere(
    ProgressPersistenceController c,
    bool Function() ready,
  ) {
    if (ready()) return Future<void>.value();
    final done = Completer<void>();
    void listener() {
      if (ready() && !done.isCompleted) {
        c.removeListener(listener);
        done.complete();
      }
    }

    c.addListener(listener);
    return done.future;
  }

  ProgressPersistenceController owner({
    Future<void> Function()? kanaFlush,
    Future<void> Function()? kanjiFlush,
    Future<void> Function()? wordFlush,
    List<StoreHealth> health = const [],
  }) {
    return ProgressPersistenceController(
      kanaFlush: kanaFlush ?? () async {},
      kanjiFlush: kanjiFlush ?? () async {},
      wordFlush: wordFlush ?? () async {},
      health: health,
    );
  }

  StoreWriteFailure fail() => const StoreWriteFailure('k');

  test(
    'a write in flight reads as saving, then idle — never a failure',
    () async {
      final gate = Completer<void>();
      final c = owner();
      c.trackKana(gate.future);
      expect(c.status, PersistenceStatus.saving); // in flight
      expect(c.isSaving, isTrue);
      gate.complete();
      await settled(gate.future);
      expect(c.status, PersistenceStatus.idle);
      expect(c.hasWriteFailure, isFalse);
    },
  );

  test('saving is observable — it notifies on the in-flight edges', () async {
    final gate = Completer<void>();
    final c = owner();
    final seen = <PersistenceStatus>[];
    c.addListener(() => seen.add(c.status));
    c.trackKana(gate.future);
    gate.complete();
    await settled(gate.future);
    expect(seen, contains(PersistenceStatus.saving)); // idle → saving notified
    expect(seen.last, PersistenceStatus.idle); // saving → idle notified
  });

  test(
    'multiple failures in an epoch read as a single failure state',
    () async {
      final c = owner();
      final f1 = Future<void>.error(fail());
      final f2 = Future<void>.error(fail());
      c.trackKana(f1);
      c.trackKana(f2);
      await settled(f1);
      await settled(f2);
      expect(c.hasWriteFailure, isTrue);
      expect(c.status, PersistenceStatus.failedNeedsRetry);
    },
  );

  test(
    'a later confirmed write clears the same repo\'s older failure',
    () async {
      final c = owner();
      final f1 = Future<void>.error(fail()); // seq 1 fails
      c.trackKana(f1);
      await settled(f1);
      expect(c.hasWriteFailure, isTrue);
      final f2 = Future<void>.value(); // seq 2 confirms → flushed all dirty
      c.trackKana(f2);
      await settled(f2);
      expect(c.hasWriteFailure, isFalse);
    },
  );

  test('a stale older success does not clear a newer failure', () async {
    final c = owner();
    final older = Completer<void>();
    final newer = Completer<void>();
    c.trackKana(older.future); // seq 1
    c.trackKana(newer.future); // seq 2
    newer.completeError(fail()); // newer fails first
    await settled(newer.future);
    expect(c.hasWriteFailure, isTrue);
    older.complete(); // older succeeds late
    await settled(older.future);
    expect(c.hasWriteFailure, isTrue); // newer failure survives
  });

  test('an older failure does not overwrite a newer confirmed flush', () async {
    final c = owner();
    final older = Completer<void>();
    final newer = Completer<void>();
    c.trackKana(older.future); // seq 1
    c.trackKana(newer.future); // seq 2
    newer.complete(); // newer confirms first
    await settled(newer.future);
    expect(c.hasWriteFailure, isFalse);
    older.completeError(fail()); // older fails late → stale
    await settled(older.future);
    expect(c.hasWriteFailure, isFalse); // stays clean
  });

  test(
    'kana success does not clear a kanji failure (and vice versa)',
    () async {
      final c = owner();
      final kf = Future<void>.error(fail());
      c.trackKanji(kf);
      await settled(kf);
      expect(c.hasWriteFailure, isTrue);
      final ks = Future<void>.value(); // a kana success
      c.trackKana(ks);
      await settled(ks);
      expect(c.hasWriteFailure, isTrue); // the kanji failure is untouched
    },
  );

  test('retry flushes the failing repo and clears on success', () async {
    var kanaFlushes = 0;
    final c = owner(
      kanaFlush: () async {
        kanaFlushes++;
      },
    );
    final f = Future<void>.error(fail());
    c.trackKana(f);
    await settled(f);
    expect(c.hasWriteFailure, isTrue);

    await c.retry();
    expect(kanaFlushes, 1); // flushed once — no domain mutation replayed
    expect(c.hasWriteFailure, isFalse);
  });

  test('retry keeps the surface up when the flush fails again', () async {
    var shouldFail = true;
    final c = owner(
      kanaFlush: () async {
        if (shouldFail) throw fail();
      },
    );
    final f = Future<void>.error(fail());
    c.trackKana(f);
    await settled(f);

    await c.retry();
    expect(c.hasWriteFailure, isTrue); // still failing

    shouldFail = false;
    await c.retry();
    expect(c.hasWriteFailure, isFalse); // recovers on a later successful retry
  });

  test(
    'retry only flushes the repositories that are actually failing',
    () async {
      var kanaFlushes = 0;
      var kanjiFlushes = 0;
      var wordFlushes = 0;
      final c = owner(
        kanaFlush: () async {
          kanaFlushes++;
        },
        kanjiFlush: () async {
          kanjiFlushes++;
        },
        wordFlush: () async {
          wordFlushes++;
        },
      );
      final f = Future<void>.error(fail());
      c.trackKanji(f);
      await settled(f);

      await c.retry();
      expect(kanjiFlushes, 1);
      expect(kanaFlushes, 0); // kana was clean — not touched
      expect(wordFlushes, 0); // word was clean — not touched
      expect(c.hasWriteFailure, isFalse);
    },
  );

  test('a retry already in flight ignores rapid repeats', () async {
    final gate = Completer<void>();
    var calls = 0;
    final c = owner(
      kanaFlush: () {
        calls++;
        return gate.future;
      },
    );
    final f = Future<void>.error(fail());
    c.trackKana(f);
    await settled(f);

    final r1 = c.retry(); // starts the flush, parks on the gate
    final r2 = c.retry(); // in flight → ignored
    gate.complete();
    await Future.wait([r1, r2]);
    expect(calls, 1); // flushed once despite two taps
    expect(c.hasWriteFailure, isFalse);
  });

  test('retry start and finish both notify the UI', () async {
    final gate = Completer<void>();
    final c = owner(kanaFlush: () => gate.future);
    final f = Future<void>.error(fail());
    c.trackKana(f);
    await settled(f);

    var sawRetrying = false;
    c.addListener(() {
      if (c.isRetrying) sawRetrying = true;
    });
    final r = c.retry();
    expect(c.isRetrying, isTrue); // synchronous start
    gate.complete();
    await r;
    expect(sawRetrying, isTrue); // notified during retry
    expect(c.isRetrying, isFalse); // notified at the end
  });

  test('the failure state persists while a retry is in flight', () async {
    final gate = Completer<void>();
    final c = owner(kanaFlush: () => gate.future);
    final f = Future<void>.error(fail());
    c.trackKana(f);
    await settled(f);

    final r = c.retry();
    expect(c.hasWriteFailure, isTrue); // still failing during the retry
    expect(c.isRetrying, isTrue);
    gate.complete();
    await r;
    expect(c.hasWriteFailure, isFalse);
  });

  test('drain flushes every repository best-effort', () async {
    var kanaFlushes = 0;
    var kanjiFlushes = 0;
    var wordFlushes = 0;
    final c = owner(
      kanaFlush: () async {
        kanaFlushes++;
      },
      kanjiFlush: () async {
        kanjiFlushes++;
      },
      wordFlush: () async {
        wordFlushes++;
      },
    );
    c.drain();
    expect(kanaFlushes, 1); // all three invoked synchronously by drain
    expect(kanjiFlushes, 1);
    expect(wordFlushes, 1);
    await nextWhere(c, () => c.status == PersistenceStatus.idle);
    expect(
      c.hasWriteFailure,
      isFalse,
    ); // a clean drain never raises the surface
  });

  test('a drain whose flush fails is surfaced, then retryable', () async {
    var shouldFail = true;
    final c = owner(
      kanaFlush: () async {
        if (shouldFail) throw fail();
      },
    );
    c.drain();
    await nextWhere(c, () => c.hasWriteFailure);
    expect(c.hasWriteFailure, isTrue);

    shouldFail = false;
    await c.retry();
    expect(c.hasWriteFailure, isFalse);
  });

  test(
    'a repository success never clears a preservation-pending notice',
    () async {
      // The controller can't know WHICH store completed preservation (the kana
      // repository has three), so a later success must not silence the notice.
      final c = owner(health: [StoreHealth.preservationPending]);
      expect(c.recoveryNotice, RecoveryNotice.preservationPending);
      final f = Future<void>.value();
      c.trackKana(f);
      await settled(f);
      expect(c.recoveryNotice, RecoveryNotice.preservationPending); // unchanged
      c.acknowledgeRecovery(); // only an explicit ack clears it
      expect(c.recoveryNotice, RecoveryNotice.none);
    },
  );

  test(
    'every tracked error is observed — none reaches the uncaught zone',
    () async {
      Object? uncaught;
      await runZonedGuarded(() async {
        final c = owner();
        final f1 = Future<void>.error(fail());
        final f2 = Future<void>.error(fail());
        c.trackKana(f1);
        c.trackKanji(f2);
        c.drain(); // clean flushes here
        await settled(f1);
        await settled(f2);
        await nextWhere(c, () => c.status != PersistenceStatus.saving);
      }, (error, _) => uncaught = error);
      expect(uncaught, isNull);
    },
  );

  test(
    'a lifecycle drain is what makes an unpersisted write durable',
    () async {
      // Causal: the mutation's OWN write fails, so nothing is durable and the
      // owner holds the failure. Durability can therefore only come from the
      // drain's flush — a no-op drain leaves the answer un-persisted.
      SharedPreferences.setMockInitialValues({});
      final fake = FakePreferencesService();
      final kana = kHiraganaGojuon.first;
      fake.failWrites.add('kana_stats_v1'); // the mutation's write will fail
      final repo = await KanaProgressRepository.load(fake);

      // A thin kanaFlush wrapper: count the calls and capture the future
      // kana.flushPending() returns, passing it back verbatim.
      var kanaFlushCalls = 0;
      Future<void>? capturedFlush;
      final controller = ProgressPersistenceController(
        kanaFlush: () {
          kanaFlushCalls++;
          final flush = repo.flushPending();
          capturedFlush = flush;
          return flush;
        },
        kanjiFlush: () async {},
        wordFlush: () async {},
      );

      // The answer applies in memory, but its write fails; the owner takes it.
      final mutation = repo.recordAnswer(
        kana,
        correct: true,
        at: DateTime(2026),
      );
      controller.trackKana(mutation);
      await expectLater(mutation, throwsA(isA<StoreWriteFailure>()));
      expect(controller.hasWriteFailure, isTrue);
      // Nothing reached disk — a cold restart sees no answer.
      final afterFail = await KanaProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(afterFail.statFor(kana).seenCount, 0);

      // Clear the fault; gate the retry write so it can be frozen mid-flight.
      fake.failWrites.clear();
      final gate = PlatformGate();
      fake.writeGates['kana_stats_v1'] = gate;

      controller.drain();
      // Synchronous proof the drain actually flushed: a no-op drain fails HERE,
      // rather than hanging forever on gate.entered below.
      expect(kanaFlushCalls, 1);
      expect(capturedFlush, isNotNull);

      await gate.entered; // the flush's primary write is frozen mid-flight
      // Not committed yet: a cold restart before release still sees no answer.
      final beforeRelease = await KanaProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(beforeRelease.statFor(kana).seenCount, 0);

      fake.writeGates.remove('kana_stats_v1');
      gate.release();
      await capturedFlush!; // the drain's flush is what lands the write

      expect(controller.hasWriteFailure, isFalse);
      final fresh = await KanaProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.statFor(kana).seenCount, 1);
      // The primary was platform-acknowledged exactly once; never interleaved.
      expect(fake.writeLog.where((k) => k == 'kana_stats_v1').length, 1);
      expect(fake.sawOverlap, isFalse);
    },
  );

  group('word introduce — seen no-op vs persistence contract', () {
    const inu = 'word:いぬ';
    const neko = 'word:ねこ';
    final firstAt = DateTime(2026, 9, 10);
    final laterAt = DateTime(2026, 9, 10, 0, 5);
    final recoveredAt = DateTime(2026, 9, 10, 0, 10);

    test(
      'repeating a seen introduce does not clear a still-unpersisted failure',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fake = FakePreferencesService();
        fake.failWrites.add('word_stats_v1');
        final repo = await WordProgressRepository.load(fake);
        final controller = ProgressPersistenceController(
          kanaFlush: () async {},
          kanjiFlush: () async {},
          wordFlush: repo.flushPending,
        );

        final first = repo.introduce(inu, at: firstAt);
        controller.trackWord(first);
        await expectLater(first, throwsA(isA<StoreWriteFailure>()));
        expect(controller.hasWriteFailure, isTrue);
        expect(controller.status, PersistenceStatus.failedNeedsRetry);
        expect(fake.durable, isEmpty);
        expect(repo.seenItemCount, 1);

        final before = repo.statForItem(inu);
        final repeated = repo.introduce(inu, at: laterAt);
        controller.trackWord(repeated);
        await expectLater(repeated, throwsA(isA<StoreWriteFailure>()));

        expect(identical(repo.statForItem(inu), before), isTrue);
        expect(controller.hasWriteFailure, isTrue);
        expect(controller.status, PersistenceStatus.failedNeedsRetry);
        // Flush retried and failed again — the primary is still not durable.
        expect(fake.durable.containsKey('word_stats_v1'), isFalse);
        expect(repo.seenItemCount, 1);

        final fresh = await WordProgressRepository.load(
          FakePreferencesService.restarted(fake),
        );
        expect(fresh.seenItemCount, 0);
      },
    );

    test('a recovered write on a later seen introduce persists exactly one '
        'introduction', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = FakePreferencesService();
      fake.failWrites.add('word_stats_v1');
      final repo = await WordProgressRepository.load(fake);
      final controller = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: repo.flushPending,
      );

      final first = repo.introduce(inu, at: firstAt);
      controller.trackWord(first);
      await expectLater(first, throwsA(isA<StoreWriteFailure>()));

      final stillFailing = repo.introduce(inu, at: laterAt);
      controller.trackWord(stillFailing);
      await expectLater(stillFailing, throwsA(isA<StoreWriteFailure>()));
      expect(controller.hasWriteFailure, isTrue);

      fake.failWrites.clear();
      final recovered = repo.introduce(inu, at: recoveredAt);
      controller.trackWord(recovered);
      await recovered;

      expect(controller.hasWriteFailure, isFalse);
      expect(controller.status, PersistenceStatus.idle);
      expect(repo.statForItem(inu).seenCount, 1);
      expect(repo.statForItem(inu).correctCount, 1);
      expect(repo.statForItem(inu).srsLevel, 1);

      final fresh = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.seenItemCount, 1);
      expect(fresh.statForItem(inu).seenCount, 1);
      expect(fresh.statForItem(inu).correctCount, 1);
      expect(fresh.statForItem(inu).srsLevel, 1);
    });

    test('re-ferrying a different seen item cannot clear another word\'s '
        'unpersisted failure', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = FakePreferencesService();
      final repo = await WordProgressRepository.load(fake);
      await repo.introduce(neko, at: firstAt);
      expect(repo.statForItem(neko).seenCount, 1);

      fake.failWrites.add('word_stats_v1');
      final controller = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: repo.flushPending,
      );

      final first = repo.introduce(inu, at: laterAt);
      controller.trackWord(first);
      await expectLater(first, throwsA(isA<StoreWriteFailure>()));
      expect(controller.hasWriteFailure, isTrue);

      final nekoBefore = repo.statForItem(neko);
      final other = repo.introduce(neko, at: recoveredAt);
      controller.trackWord(other);
      await expectLater(other, throwsA(isA<StoreWriteFailure>()));

      expect(identical(repo.statForItem(neko), nekoBefore), isTrue);
      expect(controller.hasWriteFailure, isTrue);
      expect(controller.status, PersistenceStatus.failedNeedsRetry);
      expect(repo.statForItem(inu).seenCount, 1);
      expect(repo.statForItem(neko).seenCount, 1);

      final fresh = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(fresh.statForItem(neko).seenCount, 1);
      expect(fresh.statForItem(inu).isSeen, isFalse);
    });
  });

  group('recovery notice coalesces most-severe-wins', () {
    test('empty/loaded → none', () {
      final c = owner(health: [StoreHealth.empty, StoreHealth.loaded]);
      expect(c.recoveryNotice, RecoveryNotice.none);
    });

    test('salvaged + recoveryRequired → recoveryRequired', () {
      final c = owner(
        health: [StoreHealth.salvaged, StoreHealth.recoveryRequired],
      );
      expect(c.recoveryNotice, RecoveryNotice.recoveryRequired);
    });

    test('restored + preservationPending → preservationPending', () {
      final c = owner(
        health: [StoreHealth.restored, StoreHealth.preservationPending],
      );
      expect(c.recoveryNotice, RecoveryNotice.preservationPending);
    });

    test('acknowledgement silences it for the session', () {
      final c = owner(health: [StoreHealth.salvaged]);
      expect(c.recoveryNotice, RecoveryNotice.salvaged);
      c.acknowledgeRecovery();
      expect(c.recoveryNotice, RecoveryNotice.none);
    });
  });
}
