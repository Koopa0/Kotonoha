// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_restore_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/progress_snapshot_restorer.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';
import 'services/fake_snapshot_file_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 11, 9, 13);
  const jinReading = 'reading:人#ジン';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    (
      FakePreferencesService,
      KanaProgressRepository,
      KanjiReadingRepository,
      WordProgressRepository,
    )
  >
  loadAll() async {
    final fake = FakePreferencesService();
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    return (fake, kana, kanji, words);
  }

  ProgressSnapshotRepository snapshotsFor(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  ) {
    return ProgressSnapshotRepository(
      kana: kana,
      kanji: kanji,
      words: words,
      prefs: fake,
    );
  }

  ProgressSnapshotRestoreRepository restoreFor(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  ) {
    return ProgressSnapshotRestoreRepository(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
    );
  }

  Future<String> encodedBackup(
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words, {
    String retiredUnit = 'a_unit_no_longer_in_any_dataset',
  }) async {
    final a = kana.allKana.first;
    await kana.recordAnswer(a, correct: true, at: now);
    await kana.markUnitLearned('hira_row_0');
    await kana.markUnitLearned(retiredUnit);
    await kana.markUnlockSeen('words');
    await kanji.recordAnswer(jinReading, correct: true, at: now);
    await words.recordAnswer('word:いぬ', correct: true, at: now);
    return ProgressSnapshotRepository(
      kana: kana,
      kanji: kanji,
      words: words,
    ).exportEncoded(createdAt: now);
  }

  Map<String, String?> primaryRaws(FakePreferencesService fake) {
    return {for (final key in RestoreJournalStores.all) key: fake.durable[key]};
  }

  List<int> correctCounts(
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  ) {
    int sumCorrect<T>(Iterable<T> stats, int Function(T) count) =>
        stats.fold(0, (sum, stat) => sum + count(stat));
    return [
      sumCorrect(kana.stats.values, (s) => s.correctCount),
      sumCorrect(kanji.stats.values, (s) => s.correctCount),
      sumCorrect(words.stats.values, (s) => s.correctCount),
    ];
  }

  Future<String> backupWithCorrectCounts(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  ) async {
    final a = kana.allKana.first;
    for (var i = 0; i < 3; i++) {
      final at = now.add(Duration(minutes: i));
      await kana.recordAnswer(a, correct: true, at: at);
      await kanji.recordAnswer(jinReading, correct: true, at: at);
      await words.recordAnswer('word:いぬ', correct: true, at: at);
    }
    return snapshotsFor(fake, kana, kanji, words).exportEncoded(createdAt: now);
  }

  ProgressRestoreRecoveryController recoveryFor(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words, {
    required bool needsRecovery,
  }) {
    return ProgressRestoreRecoveryController(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
      needsRecovery: needsRecovery,
    );
  }

  test('successful restore replaces all five primaries and memory', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (targetFake, targetKana, targetKanji, targetWords) = await loadAll();
    final restore = restoreFor(
      targetFake,
      targetKana,
      targetKanji,
      targetWords,
    );
    final preview = restore.previewEncoded(backup)!;

    await restore.apply(preview.snapshot);

    expect(targetKana.stats.length, 1);
    expect(targetKana.learnedUnits, contains('hira_row_0'));
    expect(
      targetKana.learnedUnits,
      contains('a_unit_no_longer_in_any_dataset'),
    );
    expect(targetKana.seenUnlocks, {'words'});
    expect(targetKanji.stats.keys, contains(jinReading));
    expect(targetWords.stats['word:いぬ']!.seenCount, 1);
    expect(targetFake.durable[ProgressRestoreJournal.journalKey], isNull);
    for (final key in RestoreJournalStores.all) {
      expect(targetFake.durable[key], isNotNull);
    }
  });

  test('invalid file performs zero writes', () async {
    final (fake, kana, kanji, words) = await loadAll();
    await kana.recordAnswer(kana.allKana.first, correct: true, at: now);
    final before = primaryRaws(fake);

    final restore = restoreFor(fake, kana, kanji, words);
    expect(restore.previewEncoded('not json'), isNull);
    expect(primaryRaws(fake), before);
    expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
  });

  test('cancelled confirm performs zero writes', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    final before = primaryRaws(fake);

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      snapshots: snapshotsFor(fake, kana, kanji, words),
      restore: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => false);

    expect(result.status, SnapshotRestoreStatus.cancelled);
    expect(primaryRaws(fake), before);
    expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
  });

  test('journal write failure leaves primaries untouched', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    await kana.recordAnswer(kana.allKana.first, correct: true, at: now);
    final before = primaryRaws(fake);

    fake.failWriteOnAttempt[ProgressRestoreJournal.journalKey] = {1};
    final restore = restoreFor(fake, kana, kanji, words);
    final preview = restore.previewEncoded(backup)!;

    await expectLater(
      restore.apply(preview.snapshot),
      throwsA(isA<RestoreJournalWriteFailure>()),
    );
    expect(primaryRaws(fake), before);
  });

  test(
    'failure while applying third primary rolls back all primaries',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');
      final before = primaryRaws(fake);

      fake.failWriteOnAttempt[ProgressSnapshotRepository.seenUnlocksStore] = {
        1,
      };
      final restore = restoreFor(fake, kana, kanji, words);
      final preview = restore.previewEncoded(backup)!;

      await expectLater(
        restore.apply(preview.snapshot),
        throwsA(isA<RestoreJournalWriteFailure>()),
      );
      expect(primaryRaws(fake), before);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(kana.learnedUnits, {'keep_me'});
    },
  );

  test(
    'rollback write failure keeps journal blocking and mixed durable state',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');
      final before = primaryRaws(fake);

      fake.failWriteOnAttempt[ProgressSnapshotRepository.seenUnlocksStore] = {
        1,
      };
      fake.failWriteOnAttempt[ProgressSnapshotRepository.learnedUnitsStore] = {
        3,
      };
      final restore = restoreFor(fake, kana, kanji, words);
      final preview = restore.previewEncoded(backup)!;

      await expectLater(
        restore.apply(preview.snapshot),
        throwsA(isA<RestoreJournalWriteFailure>()),
      );

      expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
      expect(
        snapshotsFor(fake, kana, kanji, words).blockedStores,
        contains(ProgressRestoreJournal.journalKey),
      );
      expect(
        fake.durable[ProgressSnapshotRepository.learnedUnitsStore],
        isNot(before[ProgressSnapshotRepository.learnedUnitsStore]),
      );
      expect(kana.learnedUnits, {'keep_me'});

      final restarted = FakePreferencesService.restarted(fake);
      await ProgressRestoreJournal.recoverIfNeeded(restarted);
      final reloaded = await KanaProgressRepository.load(restarted);
      expect(restarted.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(reloaded.learnedUnits, {'keep_me'});
    },
  );

  test('failed rollback on restart keeps journal instead of mixed durable progress', () async {
    final (fake, kana, kanji, words) = await loadAll();
    await kana.markUnitLearned('keep_me');
    final before = primaryRaws(fake);

    fake.seed(
      ProgressRestoreJournal.journalKey,
      jsonEncode(<String, Object?>{
        'phase': RestoreJournalPhase.applying.name,
        'rollback': before,
        'staging': <String, String>{
          for (final key in RestoreJournalStores.all) key: '{"partial":true}',
        },
      }),
    );
    fake.durable[ProgressSnapshotRepository.kanaStatsStore] =
        '{"partial":true}';
    fake.durable[ProgressSnapshotRepository.learnedUnitsStore] =
        '["hira_row_0","a_unit_no_longer_in_any_dataset"]';

    final restarted = FakePreferencesService.restarted(fake)
      ..failWriteOnAttempt[ProgressSnapshotRepository.learnedUnitsStore] = {1};
    await ProgressRestoreJournal.recoverIfNeeded(restarted);

    expect(restarted.durable[ProgressRestoreJournal.journalKey], isNotNull);
    expect(ProgressRestoreJournal.blocksExport(restarted), isTrue);
    expect(
      restarted.durable[ProgressSnapshotRepository.learnedUnitsStore],
      '["hira_row_0","a_unit_no_longer_in_any_dataset"]',
    );
  });

  test('commit journal removal failure still reports restored with memory', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    fake.failRemoves.add(ProgressRestoreJournal.journalKey);

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      snapshots: snapshotsFor(fake, kana, kanji, words),
      restore: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);

    expect(result.status, SnapshotRestoreStatus.restored);
    expect(kana.learnedUnits, contains('hira_row_0'));
    expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
    expect(
      RestoreJournalPhase.committed.name,
      isIn(fake.durable[ProgressRestoreJournal.journalKey]!),
    );
    expect(ProgressRestoreJournal.blocksExport(fake), isFalse);
    await kana.recordAnswer(kana.allKana.first, correct: true, at: now);
  });

  test(
    'committed marker survives restart and preserves restored primaries',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      fake.failRemoves.add(ProgressRestoreJournal.journalKey);

      final files = FakeSnapshotFilePort()..pickContents = backup;
      final restorer = ProgressSnapshotRestorer(
        snapshots: snapshotsFor(fake, kana, kanji, words),
        restore: restoreFor(fake, kana, kanji, words),
        files: files,
      );
      final result = await restorer.restore(confirm: (_) async => true);
      expect(result.status, SnapshotRestoreStatus.restored);

      final restarted = FakePreferencesService.restarted(fake);
      await ProgressRestoreJournal.recoverIfNeeded(restarted);
      expect(restarted.durable[ProgressRestoreJournal.journalKey], isNull);

      final rKana = await KanaProgressRepository.load(restarted);
      final rKanji = await KanjiReadingRepository.load(restarted);
      final rWords = await WordProgressRepository.load(restarted);

      expect(rKana.learnedUnits, contains('hira_row_0'));
      expect(rKana.learnedUnits, contains('a_unit_no_longer_in_any_dataset'));
      expect(rKanji.stats.keys, contains(jinReading));
      expect(rWords.stats['word:いぬ']!.seenCount, 1);
    },
  );

  test(
    'recoverIfNeeded rolls back interrupted applying journal on restart',
    () async {
      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('local_only');
      final before = primaryRaws(fake);

      fake.seed(
        ProgressRestoreJournal.journalKey,
        jsonEncode(<String, Object?>{
          'phase': RestoreJournalPhase.applying.name,
          'rollback': before,
          'staging': <String, String>{
            for (final key in RestoreJournalStores.all) key: '{"partial":true}',
          },
        }),
      );
      fake.durable[ProgressSnapshotRepository.kanaStatsStore] =
          '{"partial":true}';

      await ProgressRestoreJournal.recoverIfNeeded(fake);

      expect(primaryRaws(fake), before);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
    },
  );

  test('corrupt journal is not cleared and keeps blocking export', () async {
    final (fake, kana, kanji, words) = await loadAll();
    fake.seed(ProgressRestoreJournal.journalKey, 'not json');

    await ProgressRestoreJournal.recoverIfNeeded(fake);

    expect(fake.durable[ProgressRestoreJournal.journalKey], 'not json');
    expect(
      snapshotsFor(fake, kana, kanji, words).blockedStores,
      contains(ProgressRestoreJournal.journalKey),
    );
  });

  test('unfinished journal blocks export', () async {
    final (fake, kana, kanji, words) = await loadAll();
    fake.seed(
      ProgressRestoreJournal.journalKey,
      jsonEncode(<String, Object?>{
        'phase': RestoreJournalPhase.staging.name,
        'rollback': primaryRaws(fake),
        'staging': <String, String>{},
      }),
    );

    final snapshots = snapshotsFor(fake, kana, kanji, words);
    expect(
      snapshots.blockedStores,
      contains(ProgressRestoreJournal.journalKey),
    );

    final files = FakeSnapshotFilePort();
    final exporter = ProgressSnapshotExporter(
      snapshots: snapshots,
      files: files,
      now: () => now,
    );
    final result = await exporter.export();
    expect(result.status, SnapshotExportStatus.blocked);
    expect(files.saveCalls, 0);
  });

  test(
    'stale gated kana and word writes cannot overwrite restored progress',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
      final backup = await backupWithCorrectCounts(
        sourceFake,
        sourceKana,
        sourceKanji,
        sourceWords,
      );

      final (fake, kana, kanji, words) = await loadAll();
      final a = kana.allKana.first;
      final wordGate = PlatformGate();
      final kanaGate = PlatformGate();
      fake.writeGates[ProgressSnapshotRepository.wordStatsStore] = wordGate;
      fake.writeGates[ProgressSnapshotRepository.kanaStatsStore] = kanaGate;

      final wordPending = words.recordAnswer(
        'word:いぬ',
        correct: false,
        at: now,
      );
      await wordGate.entered;
      final kanaPending = kana.recordAnswer(a, correct: false, at: now);
      await kanaGate.entered;
      // In-flight flushes stay parked on their gate objects; dropping the map
      // entry lets the restore journal write primaries without waiting.
      fake.writeGates.remove(ProgressSnapshotRepository.wordStatsStore);
      fake.writeGates.remove(ProgressSnapshotRepository.kanaStatsStore);

      final restore = restoreFor(fake, kana, kanji, words);
      await restore.apply(restore.previewEncoded(backup)!.snapshot);

      expect(correctCounts(kana, kanji, words), [3, 3, 3]);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);

      wordGate.release();
      kanaGate.release();
      await wordPending;
      await kanaPending;

      expect(correctCounts(kana, kanji, words), [3, 3, 3]);

      final restarted = FakePreferencesService.restarted(fake);
      await ProgressRestoreJournal.recoverIfNeeded(restarted);
      final reloadedKana = await KanaProgressRepository.load(restarted);
      final reloadedKanji = await KanjiReadingRepository.load(restarted);
      final reloadedWords = await WordProgressRepository.load(restarted);
      expect(
        correctCounts(reloadedKana, reloadedKanji, reloadedWords),
        [3, 3, 3],
      );
    },
  );

  test('restore without pending writes keeps correct counts after restart', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await backupWithCorrectCounts(
      sourceFake,
      sourceKana,
      sourceKanji,
      sourceWords,
    );

    final (fake, kana, kanji, words) = await loadAll();
    final restore = restoreFor(fake, kana, kanji, words);
    await restore.apply(restore.previewEncoded(backup)!.snapshot);

    expect(correctCounts(kana, kanji, words), [3, 3, 3]);

    final restarted = FakePreferencesService.restarted(fake);
    await ProgressRestoreJournal.recoverIfNeeded(restarted);
    final reloadedKana = await KanaProgressRepository.load(restarted);
    final reloadedKanji = await KanjiReadingRepository.load(restarted);
    final reloadedWords = await WordProgressRepository.load(restarted);
    expect(
      correctCounts(reloadedKana, reloadedKanji, reloadedWords),
      [3, 3, 3],
    );
  });

  test(
    'committed cleanup failure keeps memory durable and allows learning writes',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
      final backup = await backupWithCorrectCounts(
        sourceFake,
        sourceKana,
        sourceKanji,
        sourceWords,
      );

      final (fake, kana, kanji, words) = await loadAll();
      fake.failRemoves.add(ProgressRestoreJournal.journalKey);

      final restore = restoreFor(fake, kana, kanji, words);
      await restore.apply(restore.previewEncoded(backup)!.snapshot);

      expect(correctCounts(kana, kanji, words), [3, 3, 3]);
      expect(
        snapshotsFor(fake, kana, kanji, words).blockedStores,
        isEmpty,
      );

      final a = kana.allKana.first;
      await kana.recordAnswer(a, correct: true, at: now.add(const Duration(hours: 1)));
      expect(correctCounts(kana, kanji, words)[0], 4);

      final restarted = FakePreferencesService.restarted(fake);
      await ProgressRestoreJournal.recoverIfNeeded(restarted);
      final reloadedKana = await KanaProgressRepository.load(restarted);
      expect(reloadedKana.statFor(a).correctCount, 4);
    },
  );

  test(
    'unfinished journal blocks learning writes until retry recovery succeeds',
    () async {
      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');
      final before = primaryRaws(fake);

      fake.durable[ProgressSnapshotRepository.kanaStatsStore] =
          '{"partial":true}';
      fake.seed(
        ProgressRestoreJournal.journalKey,
        jsonEncode(<String, Object?>{
          'phase': RestoreJournalPhase.applying.name,
          'rollback': before,
          'staging': <String, String>{
            for (final key in RestoreJournalStores.all) key: '{"partial":true}',
          },
        }),
      );
      fake.failWriteOnAttempt[ProgressSnapshotRepository.learnedUnitsStore] = {
        2,
      };

      final recovery = await ProgressRestoreJournal.recoverIfNeeded(fake);
      expect(recovery.needsRecovery, isTrue);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);

      final reloadedKana = await KanaProgressRepository.load(fake);
      final reloadedKanji = await KanjiReadingRepository.load(fake);
      final reloadedWords = await WordProgressRepository.load(fake);
      final controller = recoveryFor(
        fake,
        reloadedKana,
        reloadedKanji,
        reloadedWords,
        needsRecovery: true,
      );
      expect(reloadedKana.isRestoreJournalBlocked, isTrue);

      await expectLater(
        reloadedKana.recordAnswer(
          reloadedKana.allKana.first,
          correct: true,
          at: now,
        ),
        throwsA(isA<ProgressRestoreJournalBlocked>()),
      );

      fake.failWriteOnAttempt.clear();
      await controller.retry();

      expect(controller.needsRecovery, isFalse);
      expect(reloadedKana.isRestoreJournalBlocked, isFalse);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(reloadedKana.learnedUnits, {'keep_me'});
      await reloadedKana.recordAnswer(
        reloadedKana.allKana.first,
        correct: true,
        at: now,
      );
    },
  );

  test('restorer reports restored through pick and confirm', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      snapshots: snapshotsFor(fake, kana, kanji, words),
      restore: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);

    expect(result.status, SnapshotRestoreStatus.restored);
    expect(kana.stats.length, 1);
    expect(files.pickCalls, 1);
  });
}
