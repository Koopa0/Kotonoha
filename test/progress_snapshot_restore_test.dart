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

  test('commit journal removal failure does not report restored', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    final before = primaryRaws(fake);
    fake.failRemoves.add(ProgressRestoreJournal.journalKey);

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      snapshots: snapshotsFor(fake, kana, kanji, words),
      restore: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);

    expect(result.status, SnapshotRestoreStatus.failed);
    expect(kana.learnedUnits, isEmpty);
    expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
    expect(
      RestoreJournalPhase.committed.name,
      isIn(fake.durable[ProgressRestoreJournal.journalKey]!),
    );
    expect(
      fake.durable[ProgressSnapshotRepository.learnedUnitsStore],
      isNot(before[ProgressSnapshotRepository.learnedUnitsStore]),
    );
    expect(ProgressRestoreJournal.blocksExport(fake), isFalse);
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
      expect(result.status, SnapshotRestoreStatus.failed);

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
