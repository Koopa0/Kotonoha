// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';
import 'services/fake_snapshot_file_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 11, 7, 11, 3);
  const codec = ProgressSnapshotCodec();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    (KanaProgressRepository, KanjiReadingRepository, WordProgressRepository)
  >
  loadAll(FakePreferencesService fake) async {
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    return (kana, kanji, words);
  }

  ProgressSnapshotExporter exporterFor(
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
    FakeSnapshotFilePort files,
  ) {
    return ProgressSnapshotExporter(
      snapshots: ProgressSnapshotRepository(
        kana: kana,
        kanji: kanji,
        words: words,
      ),
      files: files,
      now: () => now,
    );
  }

  test('suggested file name is UTC second-precision json', () {
    expect(
      ProgressSnapshotExporter.suggestedFileName(now),
      'kotonoha-progress-20260911T071103Z.json',
    );
    expect(
      ProgressSnapshotExporter.suggestedFileName(
        DateTime.parse('2026-09-11T15:11:03+08:00'),
      ),
      'kotonoha-progress-20260911T071103Z.json',
    );
  });

  test('empty stores write a self-importable Snapshot v2 file', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    final files = FakeSnapshotFilePort();
    final exporter = exporterFor(kana, kanji, words, files);

    final result = await exporter.export();

    expect(result.status, SnapshotExportStatus.saved);
    expect(files.calls, 1);
    expect(files.lastName, 'kotonoha-progress-20260911T071103Z.json');
    final decoded = codec.decodeAndValidate(files.lastContents!);
    expect(decoded, isA<SnapshotDecodeSuccess>());
    final snap = (decoded as SnapshotDecodeSuccess).snapshot;
    expect(snap.kanaStats, isEmpty);
    expect(snap.learnedUnits, isEmpty);
    expect(snap.seenUnlocks, isEmpty);
    expect(snap.kanjiReadingStats, isEmpty);
    expect(snap.wordStats, isEmpty);
    expect(snap.createdAtUtc, now);
    expect(fake.writeLog, isEmpty);
  });

  test('populated five bodies round-trip through the offered file', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    await kana.recordAnswer(kana.allKana.first, correct: true, at: now);
    await kana.markUnitLearned('hira_row_0');
    await kana.markUnlockSeen('words');
    await kanji.recordAnswer('reading:人#ジン', correct: true, at: now);
    await words.recordAnswer('word:いぬ', correct: true, at: now);
    final files = FakeSnapshotFilePort();

    final result = await exporterFor(kana, kanji, words, files).export();

    expect(result.status, SnapshotExportStatus.saved);
    final snap = (codec.decodeAndValidate(
      files.lastContents!,
    ) as SnapshotDecodeSuccess).snapshot;
    expect(snap.kanaStats[kana.allKana.first.id]!.seenCount, 1);
    expect(snap.learnedUnits, contains('hira_row_0'));
    expect(snap.seenUnlocks, contains('words'));
    expect(snap.kanjiReadingStats.containsKey('reading:人#ジン'), isTrue);
    expect(snap.wordStats['word:いぬ']!.seenCount, 1);
  });

  test('unknown / retired unit id is kept in the offered file', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    await kana.markUnitLearned('a_unit_no_longer_in_any_dataset');
    final files = FakeSnapshotFilePort();

    await exporterFor(kana, kanji, words, files).export();

    final snap = (codec.decodeAndValidate(
      files.lastContents!,
    ) as SnapshotDecodeSuccess).snapshot;
    expect(snap.learnedUnits, contains('a_unit_no_longer_in_any_dataset'));
  });

  test('cancel never writes a file and never touches stores', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    await kana.recordAnswer(kana.allKana.first, correct: true, at: now);
    final durableBefore = Map<String, String>.of(fake.durable);
    final files = FakeSnapshotFilePort()..next = SnapshotSaveOutcome.cancelled;

    final result = await exporterFor(kana, kanji, words, files).export();

    expect(result.status, SnapshotExportStatus.cancelled);
    expect(files.calls, 1);
    expect(fake.durable, durableBefore);
  });

  test('a failed picker write does not mutate progress stores', () async {
    final fake = FakePreferencesService();
    final (kana, kanji, words) = await loadAll(fake);
    final durableBefore = Map<String, String>.of(fake.durable);
    final files = FakeSnapshotFilePort()..next = SnapshotSaveOutcome.failed;

    final result = await exporterFor(kana, kanji, words, files).export();

    expect(result.status, SnapshotExportStatus.failed);
    expect(fake.durable, durableBefore);
  });

  test('recoveryRequired never reaches the file port', () async {
    final fake = FakePreferencesService();
    fake.seed('kana_stats_v1', 'not json');
    final (kana, kanji, words) = await loadAll(fake);
    expect(kana.statsHealth, StoreHealth.recoveryRequired);
    final files = FakeSnapshotFilePort();
    final exporter = exporterFor(kana, kanji, words, files);

    expect(exporter.isBlocked, isTrue);
    expect(
      exporter.blockedStores,
      contains(ProgressSnapshotRepository.kanaStatsStore),
    );
    final result = await exporter.export();

    expect(result.status, SnapshotExportStatus.blocked);
    expect(result.stores, contains('kana_stats_v1'));
    expect(files.calls, 0);
  });

  test(
    'a memory-only mutation whose platform write failed is still offered',
    () async {
      final fake = FakePreferencesService();
      fake.failWrites.add('kana_stats_v1');
      final (kana, kanji, words) = await loadAll(fake);
      await expectLater(
        kana.recordAnswer(kana.allKana.first, correct: true, at: now),
        throwsA(isA<StoreWriteFailure>()),
      );
      final files = FakeSnapshotFilePort();

      final result = await exporterFor(kana, kanji, words, files).export();

      expect(result.status, SnapshotExportStatus.saved);
      final snap = (codec.decodeAndValidate(
        files.lastContents!,
      ) as SnapshotDecodeSuccess).snapshot;
      expect(snap.kanaStats[kana.allKana.first.id]!.seenCount, 1);
    },
  );
}
