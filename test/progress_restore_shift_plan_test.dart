// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';
import 'services/fake_snapshot_file_port.dart';

/// #178: a portable snapshot carries the five progress bodies and never the
/// answer log, so restoring one rolls mastery back while the 換句 lanes keep
/// following what this device actually recorded. That is the intended scope —
/// the answer log is device-local, and wiping it to make the lanes agree
/// would destroy every 歩み observation and every other practice record with
/// it — but nothing pinned the consequence, and `grep shift.*restore` found
/// no test at all.
///
/// These probes state it: a restore moves the word gate and leaves the
/// reservation alone, and it mints no answer evidence of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final capturedAt = DateTime.utc(2026, 9, 10, 9);
  final day0 = DateTime(2026, 9, 10, 10);
  final day1 = DateTime(2026, 9, 11, 9);
  const word = 'word:いぬ';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({
      FakePreferencesService prefs,
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
      InMemoryAnalyticsLog analytics,
    })
  >
  loadAll() async {
    final prefs = FakePreferencesService();
    return (
      prefs: prefs,
      kana: await KanaProgressRepository.load(prefs),
      kanji: await KanjiReadingRepository.load(prefs),
      words: await WordProgressRepository.load(prefs),
      analytics: InMemoryAnalyticsLog(),
    );
  }

  test(
    'a restore rolls the word gate back and leaves the reservation standing',
    () async {
      final app = await loadAll();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;

      // The snapshot is taken before any of this session's work.
      final backup = ProgressSnapshotCapture(
        kana: app.kana,
        kanji: app.kanji,
        words: app.words,
      ).exportEncoded(createdAt: capturedAt);

      // Then the learner practises and reserves the shift for tomorrow.
      await app.words.recordAnswer(word, correct: true, at: day0);
      await app.analytics.record(
        ShiftSession.reservation(drill: drill, sessionId: 'hold', at: day0),
      );
      expect(app.words.statForItem(word).correctCount, 1);

      final beforeRestore = ShiftSession.plan(
        drill: drill,
        now: day1,
        attempts: await app.analytics.all(),
      );
      expect(beforeRestore.lane, ShiftLane.confirm);

      final restorer = ProgressSnapshotRestorer(
        capture: ProgressSnapshotCapture(
          kana: app.kana,
          kanji: app.kanji,
          words: app.words,
        ),
        transaction: ProgressRestoreTransaction(
          prefs: app.prefs,
          kana: app.kana,
          kanji: app.kanji,
          words: app.words,
        ),
        files: FakeSnapshotFilePort()..pickContents = await backup,
      );
      final result = await restorer.restore(confirm: (_) async => true);
      expect(result.status, SnapshotRestoreStatus.restored);

      expect(
        app.words.statForItem(word).correctCount,
        0,
        reason: 'the restore did not replace the word body',
      );
      final afterRestore = ShiftSession.plan(
        drill: drill,
        now: day1,
        attempts: await app.analytics.all(),
      );
      expect(
        afterRestore.lane,
        ShiftLane.confirm,
        reason:
            'the restore reached into the answer log the snapshot never '
            'carried, and the reservation belongs to this device alone',
      );
      expect(afterRestore.holdUntil, beforeRestore.holdUntil);
    },
  );

  test('a restore mints no answer evidence of its own', () async {
    final app = await loadAll();

    await app.words.recordAnswer(word, correct: true, at: day0);
    final backup = await ProgressSnapshotCapture(
      kana: app.kana,
      kanji: app.kanji,
      words: app.words,
    ).exportEncoded(createdAt: capturedAt);

    final before = await app.analytics.all();
    expect(before, isEmpty, reason: 'the fixture wrote an attempt by itself');

    final restorer = ProgressSnapshotRestorer(
      capture: ProgressSnapshotCapture(
        kana: app.kana,
        kanji: app.kanji,
        words: app.words,
      ),
      transaction: ProgressRestoreTransaction(
        prefs: app.prefs,
        kana: app.kana,
        kanji: app.kanji,
        words: app.words,
      ),
      files: FakeSnapshotFilePort()..pickContents = backup,
    );
    expect(
      (await restorer.restore(confirm: (_) async => true)).status,
      SnapshotRestoreStatus.restored,
    );

    expect(
      await app.analytics.all(),
      isEmpty,
      reason: 'the restore wrote answers of its own into the log',
    );
    expect(app.words.statForItem(word).correctCount, 1);
  });

  test('the reservation survives because it is not in the snapshot', () async {
    final app = await loadAll();
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    await app.analytics.record(
      ShiftSession.reservation(drill: drill, sessionId: 'hold', at: day0),
    );
    await app.words.recordAnswer(word, correct: true, at: day0);

    final encoded = await ProgressSnapshotCapture(
      kana: app.kana,
      kanji: app.kanji,
      words: app.words,
    ).exportEncoded(createdAt: capturedAt);

    // The positive control: the snapshot is plain JSON and this probe can
    // find an id that really is in it, so the two absences below mean
    // absence rather than a search that never matches anything.
    expect(
      encoded.contains(word),
      isTrue,
      reason: 'the word body did not reach the portable snapshot',
    );
    expect(
      encoded.contains(drill.id),
      isFalse,
      reason: 'the drill reservation reached the portable snapshot',
    );
    expect(
      encoded.contains(AttemptMeta.holdUntil),
      isFalse,
      reason: 'a hold cursor reached the portable snapshot',
    );
  });

  // The copy is the only place a learner learns this, so it is pinned in the
  // same file as the behaviour it describes. #178 asks for the two to agree.
  test('the restore copy says the reservation is not rolled back', () {
    expect(
      AppStrings.restoreNotIncluded,
      contains('換句的預留'),
      reason: 'the restore screen no longer names what the log keeps',
    );
    expect(
      AppStrings.restorePreviewBody(capturedAt),
      contains('換句的預留'),
      reason: 'the preview promised less than the screen it came from',
    );
  });
}
