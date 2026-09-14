// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 7, 24, 12);
  const codec = ProgressSnapshotCodec();
  const jinReading = 'reading:人#ジン';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Loads a kana + kanji + word repository over ONE shared fake, so all three
  // persist into the same platform double.
  Future<
    (KanaProgressRepository, KanjiReadingRepository, WordProgressRepository)
  >
  loadAll(FakePreferencesService fake) async {
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    return (kana, kanji, words);
  }

  test('captures all five in-memory canonical bodies at once', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    final a = kana.allKana.first;
    final b = kana.allKana[1];
    await kana.recordAnswer(a, correct: true, at: now);
    await kana.recordAnswer(b, correct: false, at: now);
    await kana.markUnitLearned('hira_row_0');
    await kana.markUnlockSeen('words');
    await kanji.recordAnswer(jinReading, correct: true, at: now);
    await words.recordAnswer('word:いぬ', correct: true, at: now);

    final snap = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).capture(createdAt: now);

    expect(snap.kanaStats, kana.stats);
    expect(snap.kanaStats.length, 2);
    expect(snap.learnedUnits, {'hira_row_0'});
    expect(snap.seenUnlocks, {'words'});
    expect(snap.kanjiReadingStats.keys, contains(jinReading));
    expect(snap.kanjiReadingStats.length, 1);
    expect(snap.wordStats, words.stats);
    expect(snap.wordStats['word:いぬ']!.seenCount, 1);
    expect(snap.createdAtUtc, now);
  });

  test('learnedUnits keeps an unknown/retired unit id — never re-derived from '
      'the current lesson dataset', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    await kana.markUnitLearned('a_unit_no_longer_in_any_dataset');

    final snap = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).capture(createdAt: now);
    expect(snap.learnedUnits, contains('a_unit_no_longer_in_any_dataset'));
  });

  test('a mutation whose platform write FAILED is captured from memory, not '
      'from durable state', () async {
    final fake = FakePreferencesService();
    fake.failWrites.add('kana_stats_v1');
    final (kana, kanji, words) = await loadAll(fake);
    final a = kana.allKana.first;

    // Confirm the platform write really failed BEFORE capturing.
    final mutation = kana.recordAnswer(a, correct: true, at: now);
    await expectLater(mutation, throwsA(isA<StoreWriteFailure>()));

    // The failed mutation still lives in memory → capture includes it.
    final snap = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).capture(createdAt: now);
    expect(snap.kanaStats[a.id]!.seenCount, 1);

    // A fresh restart never saw it durably — proving capture reads MEMORY, not
    // the persistence layer.
    final fresh = await KanaProgressRepository.load(
      FakePreferencesService.restarted(fake),
    );
    expect(fresh.statFor(a).isSeen, isFalse);
  });

  test('a mutation still gated mid-write (not yet platform-acked) is '
      'captured', () async {
    final fake = FakePreferencesService();
    final gate = PlatformGate();
    fake.writeGates['kana_stats_v1'] = gate;
    final (kana, kanji, words) = await loadAll(fake);
    final a = kana.allKana.first;

    final pending = kana.recordAnswer(a, correct: true, at: now);
    await gate.entered; // frozen inside the platform write, not yet acked

    final snap = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).capture(createdAt: now);
    expect(snap.kanaStats[a.id]!.seenCount, 1);

    gate.release();
    await pending;
  });

  test(
    'a snapshot captured earlier is unaffected by later mutations',
    () async {
      final fake = FakePreferencesService();
      final (kana, kanji, words) = await loadAll(fake);
      final a = kana.allKana.first;
      await kana.recordAnswer(a, correct: true, at: now);

      final repo = ProgressSnapshotCapture(
        kana: kana,
        kanji: kanji,
        words: words,
      );
      final snap = repo.capture(createdAt: now);
      final bytesBefore = codec.encode(snap);

      // Mutate everything after the capture.
      await kana.recordAnswer(a, correct: false, at: now);
      await kana.markUnitLearned('hira_row_9');

      expect(snap.kanaStats[a.id]!.seenCount, 1); // frozen
      expect(snap.learnedUnits, isEmpty);
      expect(codec.encode(snap), bytesBefore); // bytes stable
    },
  );

  test('legal empty stores export a valid empty snapshot', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    final repo = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    );

    final snap = repo.capture(createdAt: now);
    expect(snap.kanaStats, isEmpty);
    expect(snap.kanjiReadingStats, isEmpty);

    final bytes = repo.exportEncoded(createdAt: now);
    expect(codec.decodeAndValidate(bytes), isA<SnapshotDecodeSuccess>());
  });

  group('recoveryRequired blocks export', () {
    test(
      'a kana stats store needing recovery blocks export, naming it',
      () async {
        final fake = FakePreferencesService();
        fake.seed('kana_stats_v1', 'not json'); // corrupt, no last-good
        final (kana, kanji, words) = await loadAll(fake);
        expect(kana.statsHealth, StoreHealth.recoveryRequired);

        final repo = ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        );
        expect(
          () => repo.capture(createdAt: now),
          throwsA(
            isA<SnapshotExportBlocked>().having(
              (e) => e.stores,
              'stores',
              contains('kana_stats_v1'),
            ),
          ),
        );
      },
    );

    test(
      'a kanji stats store needing recovery blocks export, naming it',
      () async {
        final fake = FakePreferencesService();
        fake.seed('kanji_units_v1', 'not json');
        final (kana, kanji, words) = await loadAll(fake);
        expect(kanji.statsHealth, StoreHealth.recoveryRequired);

        final repo = ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        );
        expect(
          () => repo.capture(createdAt: now),
          throwsA(
            isA<SnapshotExportBlocked>().having(
              (e) => e.stores,
              'stores',
              contains('kanji_units_v1'),
            ),
          ),
        );
      },
    );

    test(
      'a word stats store needing recovery blocks export, naming it',
      () async {
        final fake = FakePreferencesService();
        // Both the primary AND last-good are corrupt — unlike the kana/kanji
        // cases above (no last-good key at all), this reaches recoveryRequired
        // via the present-but-undecodable branch, not the absent one.
        fake.seed('word_stats_v1', 'not json');
        fake.seed('word_stats_last_good_v1', 'not json');
        final (kana, kanji, words) = await loadAll(fake);
        expect(words.statsHealth, StoreHealth.recoveryRequired);

        final repo = ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        );
        expect(
          () => repo.capture(createdAt: now),
          throwsA(
            isA<SnapshotExportBlocked>().having(
              (e) => e.stores,
              'stores',
              contains('word_stats_v1'),
            ),
          ),
        );
      },
    );

    test('a salvaged store (a recovered value in use) still exports', () async {
      final fake = FakePreferencesService();
      // One corrupt entry among valid ones → salvaged, value still usable.
      fake.seed('kana_stats_v1', '{"あ":{"s":3,"c":2,"w":1},"い":"garbage"}');
      final (kana, kanji, words) = await loadAll(fake);
      expect(kana.statsHealth, StoreHealth.salvaged);

      final snap = ProgressSnapshotCapture(
        kana: kana,
        kanji: kanji,
        words: words,
      ).capture(createdAt: now);
      expect(snap.kanaStats.length, 1); // the salvaged-good entry survives
    });
  });

  test(
    'capture writes nothing, removes nothing, and notifies no one',
    () async {
      final fake = FakePreferencesService();
      final (kana, kanji, words) = await loadAll(fake);
      await kana.recordAnswer(kana.allKana.first, correct: true, at: now);
      await kanji.recordAnswer(jinReading, correct: true, at: now);

      var kanaNotified = false;
      var kanjiNotified = false;
      kana.addListener(() => kanaNotified = true);
      kanji.addListener(() => kanjiNotified = true);
      final durableBefore = Map<String, String>.of(fake.durable);
      final writeLogBefore = List<String>.of(fake.writeLog);

      ProgressSnapshotCapture(
        kana: kana,
        kanji: kanji,
        words: words,
      ).exportEncoded(createdAt: now);

      expect(kanaNotified, isFalse);
      expect(kanjiNotified, isFalse);
      expect(fake.durable, durableBefore);
      expect(fake.writeLog, writeLogBefore);
    },
  );

  test('a single synchronous capture reflects both tracks at one instant, '
      'even with both writes frozen mid-flight', () async {
    final fake = FakePreferencesService();
    final kanaGate = PlatformGate();
    final kanjiGate = PlatformGate();
    fake.writeGates['kana_stats_v1'] = kanaGate;
    fake.writeGates['kanji_units_v1'] = kanjiGate;
    final (kana, kanji, words) = await loadAll(fake);
    final a = kana.allKana.first;

    final kp = kana.recordAnswer(a, correct: true, at: now);
    final jp = kanji.recordAnswer(jinReading, correct: true, at: now);
    await kanaGate.entered;
    await kanjiGate.entered;

    // capture() returns a value synchronously (not a Future), so nothing can
    // interleave between reading the kana and the kanji memory.
    final snap = ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).capture(createdAt: now);
    expect(snap.kanaStats[a.id]!.seenCount, 1);
    expect(snap.kanjiReadingStats[jinReading]!.seenCount, 1);

    kanaGate.release();
    kanjiGate.release();
    await Future.wait([kp, jp]);
  });

  // -----------------------------------------------------------------------
  // Acceptance repair #1: full recovery-gate coverage + immutable stores
  // -----------------------------------------------------------------------

  group('recovery export gate — every canonical store', () {
    test('learned units needing recovery blocks export, naming it', () async {
      final fake = FakePreferencesService();
      fake.seed('learned_units_v1', 'not json');
      final (kana, kanji, words) = await loadAll(fake);
      expect(kana.learnedUnitsHealth, StoreHealth.recoveryRequired);
      expect(
        () => ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        ).capture(createdAt: now),
        throwsA(
          isA<SnapshotExportBlocked>().having(
            (e) => e.stores,
            'stores',
            contains('learned_units_v1'),
          ),
        ),
      );
    });

    test('seen unlocks needing recovery blocks export, naming it', () async {
      final fake = FakePreferencesService();
      fake.seed('seen_unlocks_v1', 'not json');
      final (kana, kanji, words) = await loadAll(fake);
      expect(kana.seenUnlocksHealth, StoreHealth.recoveryRequired);
      expect(
        () => ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        ).capture(createdAt: now),
        throwsA(
          isA<SnapshotExportBlocked>().having(
            (e) => e.stores,
            'stores',
            contains('seen_unlocks_v1'),
          ),
        ),
      );
    });

    test('multiple stores needing recovery are ALL named', () async {
      final fake = FakePreferencesService();
      fake.seed('kana_stats_v1', 'not json');
      fake.seed('learned_units_v1', 'not json');
      fake.seed('kanji_units_v1', 'not json');
      final (kana, kanji, words) = await loadAll(fake);
      expect(
        () => ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        ).capture(createdAt: now),
        throwsA(
          isA<SnapshotExportBlocked>().having(
            (e) => e.stores,
            'stores',
            allOf(
              contains('kana_stats_v1'),
              contains('learned_units_v1'),
              contains('kanji_units_v1'),
            ),
          ),
        ),
      );
    });

    test(
      'a restored store (recovered from last-known-good) still exports',
      () async {
        final fake = FakePreferencesService();
        fake.seed('kana_stats_v1', 'not json');
        fake.seed('kana_stats_last_good_v1', '{"あ":{"s":3,"c":2,"w":1}}');
        final (kana, kanji, words) = await loadAll(fake);
        expect(kana.statsHealth, StoreHealth.restored);
        final snap = ProgressSnapshotCapture(
          kana: kana,
          kanji: kanji,
          words: words,
        ).capture(createdAt: now);
        expect(snap.kanaStats['あ']!.seenCount, 3);
      },
    );

    test('a preservation-pending store still exports', () async {
      final fake = FakePreferencesService();
      fake.seed('kana_stats_v1', 'not json');
      fake.seed('kana_stats_last_good_v1', '{"あ":{"s":3,"c":2,"w":1}}');
      fake.failWrites.add('kana_stats_quarantine_v1');
      final (kana, kanji, words) = await loadAll(fake);
      expect(kana.statsHealth, StoreHealth.preservationPending);
      final snap = ProgressSnapshotCapture(
        kana: kana,
        kanji: kanji,
        words: words,
      ).capture(createdAt: now);
      expect(snap.kanaStats['あ']!.seenCount, 3);
    });

    test(
      'SnapshotExportBlocked.stores is unmodifiable by the caller',
      () async {
        final fake = FakePreferencesService();
        fake.seed('kana_stats_v1', 'not json');
        final (kana, kanji, words) = await loadAll(fake);
        try {
          ProgressSnapshotCapture(
            kana: kana,
            kanji: kanji,
            words: words,
          ).capture(createdAt: now);
          fail('expected SnapshotExportBlocked');
        } on SnapshotExportBlocked catch (e) {
          expect(() => e.stores.add('x'), throwsUnsupportedError);
        }
      },
    );

    test('blockedStores is unmodifiable by the caller', () async {
      final fake = FakePreferencesService();
      fake.seed('kana_stats_v1', 'not json');
      final (kana, kanji, words) = await loadAll(fake);
      final stores = ProgressSnapshotCapture(
        kana: kana,
        kanji: kanji,
        words: words,
      ).blockedStores;
      expect(stores, contains('kana_stats_v1'));
      expect(() => stores.add('x'), throwsUnsupportedError);
    });
  });

  test(
    'restore isolation on owners blocks export when the journal gate is clear',
    () async {
      final fake = FakePreferencesService();
      final (kana, kanji, words) = await loadAll(fake);
      kana.setRestoreJournalBlocked(true);
      kanji.setRestoreJournalBlocked(true);
      words.setRestoreJournalBlocked(true);
      expect(ProgressRestoreJournal.blocksExport(fake), isFalse);

      final capture = ProgressSnapshotCapture(
        kana: kana,
        kanji: kanji,
        words: words,
        prefs: fake,
      );
      expect(capture.blockedStores, contains(ProgressRestoreJournal.journalKey));
      expect(
        () => capture.exportEncoded(createdAt: now),
        throwsA(
          isA<SnapshotExportBlocked>().having(
            (e) => e.stores,
            'stores',
            contains(ProgressRestoreJournal.journalKey),
          ),
        ),
      );
    },
  );
}
