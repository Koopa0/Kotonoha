// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_restore_placement_discard.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_recovery.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_exporter.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
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

  ProgressSnapshotCapture snapshotsFor(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  ) {
    return ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
      prefs: fake,
    );
  }

  ProgressRestoreTransaction restoreFor(
    FakePreferencesService fake,
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words, {
    PlacementCheckRepository? placement,
  }) {
    return ProgressRestoreTransaction(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
      placement: placement,
    );
  }

  Future<PlacementCheckRepository> seedCompleteAoDraft(
    FakePreferencesService fake,
  ) async {
    final checks = await PlacementCheckRepository.load(fake);
    final kana = await KanaProgressRepository.load(fake);
    final ao = Lessons.fromKana(kana.allKana)
        .firstWhere((lesson) => lesson.id == 'hira_row_0');
    var draft = PlacementCheck.start([ao])!;
    for (final kanaRow in ao.kana) {
      draft = PlacementCheck.record(
        draft,
        kanaRow.id,
        PlacementOutcome.independent,
      );
    }
    await checks.save(draft);
    expect(checks.draft.isComplete, isTrue);
    return checks;
  }

  Future<(PlacementCheckRepository, PlacementDraft)> seedPartialAoDraft(
    FakePreferencesService fake, {
    required int answeredCount,
  }) async {
    final checks = await PlacementCheckRepository.load(fake);
    final kana = await KanaProgressRepository.load(fake);
    final ao = Lessons.fromKana(kana.allKana)
        .firstWhere((lesson) => lesson.id == 'hira_row_0');
    var draft = PlacementCheck.start([ao])!;
    final answered = ao.kana.take(answeredCount);
    for (final kanaRow in answered) {
      draft = PlacementCheck.record(
        draft,
        kanaRow.id,
        PlacementOutcome.independent,
      );
    }
    await checks.save(draft);
    expect(checks.draft.isComplete, isFalse);
    return (checks, draft);
  }

  Future<String> encodedBackupLearnedHiraRow1Only(
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
  ) async {
    await kana.markUnitLearned('hira_row_1');
    return ProgressSnapshotCapture(
      kana: kana,
      kanji: kanji,
      words: words,
    ).exportEncoded(createdAt: now);
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
    return ProgressSnapshotCapture(
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
      recovery: ProgressRestoreRecovery(
        prefs: fake,
        kana: kana,
        kanji: kanji,
        words: words,
      ),
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
      capture: snapshotsFor(fake, kana, kanji, words),
      transaction: restoreFor(fake, kana, kanji, words),
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

      fake.failWriteOnAttempt[ProgressStoreKeys.seenUnlocks] = {1};
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

      fake.failWriteOnAttempt[ProgressStoreKeys.seenUnlocks] = {1};
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {3};
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
        fake.durable[ProgressStoreKeys.learnedUnits],
        isNot(before[ProgressStoreKeys.learnedUnits]),
      );
      expect(
        kana.learnedUnits,
        containsAll(['hira_row_0', 'a_unit_no_longer_in_any_dataset']),
      );

      final restarted = FakePreferencesService.restarted(fake);
      await ProgressRestoreJournal.recoverIfNeeded(restarted);
      final reloaded = await KanaProgressRepository.load(restarted);
      expect(restarted.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(reloaded.learnedUnits, {'keep_me'});
    },
  );

  test('failed restore with blocking journal blocks learning; recovery owner syncs', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    await kana.markUnitLearned('keep_me');

    fake.failWriteOnAttempt[ProgressStoreKeys.seenUnlocks] = {1};
    fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {3};

    final recovery = recoveryFor(
      fake,
      kana,
      kanji,
      words,
      needsRecovery: false,
    );
    expect(recovery.needsRecovery, isFalse);
    expect(kana.isRestoreJournalBlocked, isFalse);

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      capture: snapshotsFor(fake, kana, kanji, words),
      transaction: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);
    // The view that issued the restore hands the outcome to the recovery
    // owner; the transaction itself already blocked the repositories.
    await recovery.syncFromPlatform();

    expect(result.status, SnapshotRestoreStatus.failed);
    expect(recovery.needsRecovery, isTrue);
    expect(kana.isRestoreJournalBlocked, isTrue);
    expect(kanji.isRestoreJournalBlocked, isTrue);
    expect(words.isRestoreJournalBlocked, isTrue);
    await expectLater(
      words.recordAnswer('word:いぬ', correct: true, at: now),
      throwsA(isA<ProgressRestoreJournalBlocked>()),
    );
  });

  test(
    'platform write throw during apply syncs recovery and blocks learning',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');

      fake.throwWrites.add(ProgressStoreKeys.seenUnlocks);
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {3};

      final recovery = recoveryFor(
        fake,
        kana,
        kanji,
        words,
        needsRecovery: false,
      );
      final files = FakeSnapshotFilePort()..pickContents = backup;
      final restorer = ProgressSnapshotRestorer(
        capture: snapshotsFor(fake, kana, kanji, words),
        transaction: restoreFor(fake, kana, kanji, words),
        files: files,
      );

      final result = await restorer.restore(confirm: (_) async => true);
      // The view that issued the restore hands the outcome to the recovery
      // owner; the transaction itself already blocked the repositories.
      await recovery.syncFromPlatform();

      expect(result.status, SnapshotRestoreStatus.failed);
      expect(recovery.needsRecovery, isTrue);
      expect(kana.isRestoreJournalBlocked, isTrue);
      expect(kanji.isRestoreJournalBlocked, isTrue);
      expect(words.isRestoreJournalBlocked, isTrue);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
      expect(words.statForItem('word:あい').seenCount, 0);

      await expectLater(
        words.introduce('word:あい', at: now),
        throwsA(isA<ProgressRestoreJournalBlocked>()),
      );
      expect(words.statForItem('word:あい').seenCount, 0);

      fake.throwWrites.clear();
      fake.failWriteOnAttempt.clear();
      await recovery.retry();

      expect(recovery.needsRecovery, isFalse);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(words.statForItem('word:あい').seenCount, 0);
      await words.introduce('word:あい', at: now);
      expect(words.statForItem('word:あい').seenCount, 1);
    },
  );

  test(
    'rollback failure blocks word learning until retry rolls back primaries',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');

      fake.failWriteOnAttempt[ProgressStoreKeys.seenUnlocks] = {1};
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {3};

      final recovery = recoveryFor(
        fake,
        kana,
        kanji,
        words,
        needsRecovery: false,
      );
      final files = FakeSnapshotFilePort()..pickContents = backup;
      final restorer = ProgressSnapshotRestorer(
        capture: snapshotsFor(fake, kana, kanji, words),
        transaction: restoreFor(fake, kana, kanji, words),
        files: files,
      );

      final result = await restorer.restore(confirm: (_) async => true);
      // The view that issued the restore hands the outcome to the recovery
      // owner; the transaction itself already blocked the repositories.
      await recovery.syncFromPlatform();

      expect(result.status, SnapshotRestoreStatus.failed);
      expect(recovery.needsRecovery, isTrue);
      expect(words.isRestoreJournalBlocked, isTrue);
      expect(words.statForItem('word:あい').seenCount, 0);

      await expectLater(
        words.introduce('word:あい', at: now),
        throwsA(isA<ProgressRestoreJournalBlocked>()),
      );
      expect(words.statForItem('word:あい').seenCount, 0);

      fake.failWriteOnAttempt.clear();
      await recovery.retry();

      expect(recovery.needsRecovery, isFalse);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(words.statForItem('word:あい').seenCount, 0);
      await words.introduce('word:あい', at: now);
      expect(words.statForItem('word:あい').seenCount, 1);
    },
  );

  test(
    'apply rollback failure blocks repos even without recovery controller',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');

      fake.failWriteOnAttempt[ProgressStoreKeys.seenUnlocks] = {1};
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {3};
      final restore = restoreFor(fake, kana, kanji, words);
      final preview = restore.previewEncoded(backup)!;

      await expectLater(
        restore.apply(preview.snapshot),
        throwsA(isA<RestoreJournalWriteFailure>()),
      );

      expect(ProgressRestoreJournal.blocksExport(fake), isTrue);
      expect(words.isRestoreJournalBlocked, isTrue);
      await expectLater(
        words.introduce('word:あい', at: now),
        throwsA(isA<ProgressRestoreJournalBlocked>()),
      );
    },
  );

  test('restore lock refuses mutation before memory changes', () async {
    final (fake, kana, kanji, words) = await loadAll();
    await kana.prepareForRestore();

    await expectLater(
      kana.recordAnswer(kana.allKana.first, correct: true, at: now),
      throwsA(isA<ProgressRestoreInProgress>()),
    );
    expect(kana.statFor(kana.allKana.first).correctCount, 0);

    kana.finishRestore();
  });

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
    fake.durable[ProgressStoreKeys.kanaStats] = '{"partial":true}';
    fake.durable[ProgressStoreKeys.learnedUnits] =
        '["hira_row_0","a_unit_no_longer_in_any_dataset"]';

    final restarted = FakePreferencesService.restarted(fake)
      ..failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {1};
    await ProgressRestoreJournal.recoverIfNeeded(restarted);

    expect(restarted.durable[ProgressRestoreJournal.journalKey], isNotNull);
    expect(ProgressRestoreJournal.blocksExport(restarted), isTrue);
    expect(
      restarted.durable[ProgressStoreKeys.learnedUnits],
      '["hira_row_0","a_unit_no_longer_in_any_dataset"]',
    );
  });

  test(
    'commit journal removal failure still reports restored with memory',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      fake.failRemoves.add(ProgressRestoreJournal.journalKey);

      final files = FakeSnapshotFilePort()..pickContents = backup;
      final restorer = ProgressSnapshotRestorer(
        capture: snapshotsFor(fake, kana, kanji, words),
        transaction: restoreFor(fake, kana, kanji, words),
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
    },
  );

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
        capture: snapshotsFor(fake, kana, kanji, words),
        transaction: restoreFor(fake, kana, kanji, words),
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
      fake.durable[ProgressStoreKeys.kanaStats] = '{"partial":true}';

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
      capture: snapshots,
      files: files,
      now: () => now,
    );
    final result = await exporter.export();
    expect(result.status, SnapshotExportStatus.blocked);
    expect(files.saveCalls, 0);
  });

  Future<void> staleGatedRestoreProbe({
    required String gatedStore,
    required Future<void> Function(
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
    )
    startPendingWrite,
    required int expectedZeroTrack,
  }) async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await backupWithCorrectCounts(
      sourceFake,
      sourceKana,
      sourceKanji,
      sourceWords,
    );

    final (fake, kana, kanji, words) = await loadAll();
    final gate = PlatformGate();
    fake.writeGates[gatedStore] = gate;

    final pending = startPendingWrite(kana, kanji, words);
    await gate.entered;

    final restore = restoreFor(fake, kana, kanji, words);
    final applyFuture = restore.apply(restore.previewEncoded(backup)!.snapshot);

    var applyCompleted = false;
    unawaited(applyFuture.then((_) => applyCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(applyCompleted, isFalse);

    gate.release();
    await pending;
    await applyFuture;

    final counts = correctCounts(kana, kanji, words);
    expect(counts, [3, 3, 3]);
    expect(counts[expectedZeroTrack], 3);

    final restarted = FakePreferencesService.restarted(fake);
    await ProgressRestoreJournal.recoverIfNeeded(restarted);
    final reloadedKana = await KanaProgressRepository.load(restarted);
    final reloadedKanji = await KanjiReadingRepository.load(restarted);
    final reloadedWords = await WordProgressRepository.load(restarted);
    expect(correctCounts(reloadedKana, reloadedKanji, reloadedWords), [
      3,
      3,
      3,
    ]);
  }

  test(
    'stale gated kana and word writes cannot overwrite restored progress',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
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
      fake.writeGates[ProgressStoreKeys.wordStats] = wordGate;
      fake.writeGates[ProgressStoreKeys.kanaStats] = kanaGate;

      final wordPending = words.recordAnswer(
        'word:いぬ',
        correct: false,
        at: now,
      );
      await wordGate.entered;
      final kanaPending = kana.recordAnswer(a, correct: false, at: now);
      await kanaGate.entered;

      final restore = restoreFor(fake, kana, kanji, words);
      final applyFuture = restore.apply(
        restore.previewEncoded(backup)!.snapshot,
      );
      var applyCompleted = false;
      unawaited(applyFuture.then((_) => applyCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(applyCompleted, isFalse);

      wordGate.release();
      kanaGate.release();
      await wordPending;
      await kanaPending;
      await applyFuture;

      expect(correctCounts(kana, kanji, words), [3, 3, 3]);

      final restarted = FakePreferencesService.restarted(fake);
      await ProgressRestoreJournal.recoverIfNeeded(restarted);
      final reloadedKana = await KanaProgressRepository.load(restarted);
      final reloadedKanji = await KanjiReadingRepository.load(restarted);
      final reloadedWords = await WordProgressRepository.load(restarted);
      expect(correctCounts(reloadedKana, reloadedKanji, reloadedWords), [
        3,
        3,
        3,
      ]);
    },
  );

  test(
    'stale gated word write alone cannot overwrite restored progress',
    () async {
      await staleGatedRestoreProbe(
        gatedStore: ProgressStoreKeys.wordStats,
        startPendingWrite: (kana, kanji, words) =>
            words.recordAnswer('word:いぬ', correct: false, at: now),
        expectedZeroTrack: 2,
      );
    },
  );

  test(
    'stale gated kana write alone cannot overwrite restored progress',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final a = sourceKana.allKana.first;
      await staleGatedRestoreProbe(
        gatedStore: ProgressStoreKeys.kanaStats,
        startPendingWrite: (kana, kanji, words) =>
            kana.recordAnswer(a, correct: false, at: now),
        expectedZeroTrack: 0,
      );
    },
  );

  test(
    'restore without pending writes keeps correct counts after restart',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
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
      expect(correctCounts(reloadedKana, reloadedKanji, reloadedWords), [
        3,
        3,
        3,
      ]);
    },
  );

  test(
    'committed cleanup failure keeps memory durable and allows learning writes',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
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
      expect(snapshotsFor(fake, kana, kanji, words).blockedStores, isEmpty);

      final a = kana.allKana.first;
      await kana.recordAnswer(
        a,
        correct: true,
        at: now.add(const Duration(hours: 1)),
      );
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

      fake.durable[ProgressStoreKeys.kanaStats] = '{"partial":true}';
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
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {2};

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
      await expectLater(
        reloadedKana.markUnitLearned('blocked_unit'),
        throwsA(isA<ProgressRestoreJournalBlocked>()),
      );
      expect(reloadedKana.isUnitLearned('blocked_unit'), isFalse);

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

  test(
    'committed marker write failure rolls back and syncs memory from durable',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      fake.failWriteOnAttempt[ProgressRestoreJournal.journalKey] = {7};

      final files = FakeSnapshotFilePort()..pickContents = backup;
      final restorer = ProgressSnapshotRestorer(
        capture: snapshotsFor(fake, kana, kanji, words),
        transaction: restoreFor(fake, kana, kanji, words),
        files: files,
      );

      final result = await restorer.restore(confirm: (_) async => true);

      expect(result.status, SnapshotRestoreStatus.failed);
      expect(kana.learnedUnits, isEmpty);
      expect(fake.durable[ProgressStoreKeys.learnedUnits], isNull);
      expect(ProgressRestoreJournal.blocksExport(fake), isFalse);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
    },
  );

  test('journal remove before-effect throw still restores memory when committed durable', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    fake.throwRemoves.add(ProgressRestoreJournal.journalKey);

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      capture: snapshotsFor(fake, kana, kanji, words),
      transaction: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);

    expect(result.status, SnapshotRestoreStatus.restored);
    expect(kana.learnedUnits, contains('hira_row_0'));
    expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
    expect(ProgressRestoreJournal.blocksExport(fake), isFalse);
  });

  test(
    'journal remove after-effect still restores memory when committed durable',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

      final (fake, kana, kanji, words) = await loadAll();
      fake.throwRemovesAfterEffect.add(ProgressRestoreJournal.journalKey);

      final files = FakeSnapshotFilePort()..pickContents = backup;
      final restorer = ProgressSnapshotRestorer(
        capture: snapshotsFor(fake, kana, kanji, words),
        transaction: restoreFor(fake, kana, kanji, words),
        files: files,
      );

      final result = await restorer.restore(confirm: (_) async => true);

      expect(result.status, SnapshotRestoreStatus.restored);
      expect(kana.learnedUnits, contains('hira_row_0'));
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(ProgressRestoreJournal.blocksExport(fake), isFalse);
    },
  );

  test(
    'recoverIfNeeded keeps primaries when rollback map is schema-invalid',
    () async {
      final (fake, kana, kanji, words) = await loadAll();
      await kana.markUnitLearned('keep_me');
      final before = primaryRaws(fake);

      fake.seed(
        ProgressRestoreJournal.journalKey,
        jsonEncode(<String, Object?>{
          'phase': RestoreJournalPhase.applying.name,
          'rollback': <String, Object?>{},
          'staging': <String, String>{},
        }),
      );

      final recovery = await ProgressRestoreJournal.recoverIfNeeded(fake);

      expect(recovery.needsRecovery, isTrue);
      expect(primaryRaws(fake), before);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
      expect(kana.learnedUnits, {'keep_me'});
    },
  );

  test('restorer reports restored through pick and confirm', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackup(sourceKana, sourceKanji, sourceWords);

    final (fake, kana, kanji, words) = await loadAll();
    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      capture: snapshotsFor(fake, kana, kanji, words),
      transaction: restoreFor(fake, kana, kanji, words),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);

    expect(result.status, SnapshotRestoreStatus.restored);
    expect(kana.stats.length, 1);
    expect(files.pickCalls, 1);
  });

  test('successful restore discards a complete placement draft from disk and memory', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackupLearnedHiraRow1Only(
      sourceKana,
      sourceKanji,
      sourceWords,
    );

    final (fake, kana, kanji, words) = await loadAll();
    final checks = await seedCompleteAoDraft(fake);
    expect(kana.isUnitLearned('hira_row_0'), isFalse);

    final restore = restoreFor(fake, kana, kanji, words, placement: checks);
    await restore.apply(restore.previewEncoded(backup)!.snapshot);

    expect(checks.draft.hasProgress, isFalse);
    expect(fake.durable['placement_check_v1'], isNull);
    expect(kana.learnedUnits, {'hira_row_1'});
    expect(kana.isUnitLearned('hira_row_0'), isFalse);
  });

  test('cancelled restore keeps a complete placement draft', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackupLearnedHiraRow1Only(
      sourceKana,
      sourceKanji,
      sourceWords,
    );

    final (fake, kana, kanji, words) = await loadAll();
    final checks = await seedCompleteAoDraft(fake);
    final beforePlacement = fake.durable['placement_check_v1'];

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      capture: snapshotsFor(fake, kana, kanji, words),
      transaction: restoreFor(fake, kana, kanji, words, placement: checks),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => false);

    expect(result.status, SnapshotRestoreStatus.cancelled);
    expect(checks.draft.isComplete, isTrue);
    expect(fake.durable['placement_check_v1'], beforePlacement);
    expect(kana.learnedUnits, isEmpty);
  });

  test('placement discard pending survives restart and clears stale draft on bootstrap', () async {
    final (fake, kana, kanji, words) = await loadAll();
    await seedCompleteAoDraft(fake);
    fake.durable[ProgressStoreKeys.learnedUnits] = '["hira_row_1"]';
    fake.seed(ProgressRestorePlacementDiscard.pendingKey, 'pending');

    final restarted = FakePreferencesService.restarted(fake);
    await ProgressRestorePlacementDiscard.recoverIfNeeded(restarted);
    final reloadedChecks = await PlacementCheckRepository.load(restarted);
    final reloadedKana = await KanaProgressRepository.load(restarted);

    expect(ProgressRestorePlacementDiscard.isPending(restarted), isFalse);
    expect(reloadedChecks.draft.hasProgress, isFalse);
    expect(restarted.durable['placement_check_v1'], isNull);
    expect(reloadedKana.learnedUnits, {'hira_row_1'});
    expect(reloadedKana.isUnitLearned('hira_row_0'), isFalse);
  });

  test(
    'committed journal with placement discard flag migrates marker on restart',
    () async {
      final (fake, kana, kanji, words) = await loadAll();
      await seedCompleteAoDraft(fake);
      fake.durable[ProgressStoreKeys.learnedUnits] = '["hira_row_1"]';
      fake.seed(
        ProgressRestoreJournal.journalKey,
        jsonEncode(<String, Object?>{
          'phase': RestoreJournalPhase.committed.name,
          'placementDiscardPending': true,
          'rollback': <String, String?>{
            for (final key in RestoreJournalStores.all) key: null,
          },
        }),
      );

      await ProgressRestoreJournal.recoverIfNeeded(fake);
      await ProgressRestorePlacementDiscard.recoverIfNeeded(fake);

      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(ProgressRestorePlacementDiscard.isPending(fake), isFalse);
      expect(fake.durable['placement_check_v1'], isNull);
      final reloaded = await PlacementCheckRepository.load(fake);
      expect(reloaded.draft.hasProgress, isFalse);
    },
  );

  test(
    'failed restore before commit keeps a complete placement draft',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackupLearnedHiraRow1Only(
        sourceKana,
        sourceKanji,
        sourceWords,
      );

      final (fake, kana, kanji, words) = await loadAll();
      final checks = await seedCompleteAoDraft(fake);
      final beforePlacement = fake.durable['placement_check_v1'];
      fake.failWriteOnAttempt[ProgressRestoreJournal.journalKey] = {1};

      final restore = restoreFor(fake, kana, kanji, words, placement: checks);
      final preview = restore.previewEncoded(backup)!;

      await expectLater(
        restore.apply(preview.snapshot),
        throwsA(isA<RestoreJournalWriteFailure>()),
      );

      expect(checks.draft.isComplete, isTrue);
      expect(fake.durable['placement_check_v1'], beforePlacement);
      expect(kana.learnedUnits, isEmpty);
    },
  );

  test(
    'placement discard failure before commit rolls back primaries and draft',
    () async {
      final (sourceFake, sourceKana, sourceKanji, sourceWords) =
          await loadAll();
      final backup = await encodedBackupLearnedHiraRow1Only(
        sourceKana,
        sourceKanji,
        sourceWords,
      );

      final (fake, kana, kanji, words) = await loadAll();
      final checks = await seedCompleteAoDraft(fake);
      await kana.markUnitLearned('keep_me');
      final before = primaryRaws(fake);
      final beforePlacement = fake.durable['placement_check_v1'];
      fake.failRemoves.add(PlacementCheckRepository.storageKey);

      final restore = restoreFor(fake, kana, kanji, words, placement: checks);
      final preview = restore.previewEncoded(backup)!;

      await expectLater(
        restore.apply(preview.snapshot),
        throwsA(isA<RestoreJournalWriteFailure>()),
      );

      expect(primaryRaws(fake), before);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(fake.durable['placement_check_v1'], beforePlacement);
      expect(checks.draft.isComplete, isTrue);
      expect(kana.learnedUnits, {'keep_me'});
    },
  );

  test('placement discard failure reports failed restore without changing learned set', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackupLearnedHiraRow1Only(
      sourceKana,
      sourceKanji,
      sourceWords,
    );

    final (fake, kana, kanji, words) = await loadAll();
    final checks = await seedCompleteAoDraft(fake);
    fake.failRemoves.add(PlacementCheckRepository.storageKey);

    final files = FakeSnapshotFilePort()..pickContents = backup;
    final restorer = ProgressSnapshotRestorer(
      capture: snapshotsFor(fake, kana, kanji, words),
      transaction: restoreFor(fake, kana, kanji, words, placement: checks),
      files: files,
    );

    final result = await restorer.restore(confirm: (_) async => true);

    expect(result.status, SnapshotRestoreStatus.failed);
    expect(kana.learnedUnits, isEmpty);
    expect(checks.draft.isComplete, isTrue);
    expect(fake.durable['placement_check_v1'], isNotNull);
  });

  test('recoverIfNeeded rolls back primaries and placement after interrupted discard', () async {
    final (fake, kana, kanji, words) = await loadAll();
    final checks = await seedCompleteAoDraft(fake);
    await kana.markUnitLearned('keep_me');
    final before = primaryRaws(fake);
    final beforePlacement = fake.durable['placement_check_v1'];

    fake.seed(
      ProgressRestoreJournal.journalKey,
      jsonEncode(<String, Object?>{
        'phase': RestoreJournalPhase.applying.name,
        'rollback': before,
        'staging': <String, String>{
          for (final key in RestoreJournalStores.all) key: '{"partial":true}',
        },
        'placementRollback': {
          for (final key in PlacementCheckRepository.durableKeys)
            key: fake.durable[key],
        },
      }),
    );
    fake.durable[ProgressStoreKeys.learnedUnits] = '["hira_row_1"]';
    await checks.discardForRestore();

    await ProgressRestoreJournal.recoverIfNeeded(fake);

    expect(primaryRaws(fake), before);
    expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
    expect(fake.durable['placement_check_v1'], beforePlacement);

    final reloadedChecks = await PlacementCheckRepository.load(
      FakePreferencesService.restarted(fake),
    );
    expect(reloadedChecks.draft.isComplete, isTrue);
  });

  test('failed restore after pending placement save keeps complete draft on disk and memory', () async {
    final (sourceFake, sourceKana, sourceKanji, sourceWords) = await loadAll();
    final backup = await encodedBackupLearnedHiraRow1Only(
      sourceKana,
      sourceKanji,
      sourceWords,
    );

    final (fake, kana, kanji, words) = await loadAll();
    final (checks, partialDraft) = await seedPartialAoDraft(
      fake,
      answeredCount: 4,
    );
    final kanaRepo = await KanaProgressRepository.load(fake);
    final ao = Lessons.fromKana(kanaRepo.allKana)
        .firstWhere((lesson) => lesson.id == 'hira_row_0');
    final fifth = ao.kana[4];
    final completeDraft = PlacementCheck.record(
      partialDraft,
      fifth.id,
      PlacementOutcome.independent,
    );
    expect(completeDraft.isComplete, isTrue);

    final lastGoodGate = PlatformGate();
    fake.writeGates[PlacementCheckRepository.lastGoodKey] = lastGoodGate;
    final save = checks.save(completeDraft);
    await lastGoodGate.entered;

    fake.failRemoves.add(PlacementCheckRepository.storageKey);
    final restore = restoreFor(fake, kana, kanji, words, placement: checks);
    final preview = restore.previewEncoded(backup)!;
    final restoreFuture = restore.apply(preview.snapshot);

    lastGoodGate.release();
    await expectLater(save, completes);
    await expectLater(
      restoreFuture,
      throwsA(isA<RestoreJournalWriteFailure>()),
    );

    expect(checks.draft.isComplete, isTrue);
    expect(fake.durable['placement_check_v1'], isNotNull);
    final restarted = FakePreferencesService.restarted(fake);
    final freshChecks = await PlacementCheckRepository.load(restarted);
    expect(freshChecks.draft.isComplete, isTrue);
    expect(kana.learnedUnits, isEmpty);
  });
}
