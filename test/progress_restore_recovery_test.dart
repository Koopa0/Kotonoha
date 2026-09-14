// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_recovery.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

/// The cross-owner recovery use case and the app-scoped controller over it:
/// the journal's verdict becomes repository write blocking, a successful
/// recovery reloads the three owners from what is now on disk, and the
/// controller only records the outcome for the UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({
      FakePreferencesService fake,
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
      ProgressRestoreRecovery recovery,
    })
  >
  load(FakePreferencesService fake) async {
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    return (
      fake: fake,
      kana: kana,
      kanji: kanji,
      words: words,
      recovery: ProgressRestoreRecovery(
        prefs: fake,
        kana: kana,
        kanji: kanji,
        words: words,
      ),
    );
  }

  /// An `applying` journal whose rollback can land: learned_units_v1 was
  /// 'keep_me' before the interrupted restore overwrote the primaries.
  Future<FakePreferencesService> seedRollableJournal() async {
    final fake = FakePreferencesService();
    final seeded = await KanaProgressRepository.load(fake);
    await seeded.markUnitLearned('keep_me');
    final before = {
      for (final key in RestoreJournalStores.all) key: fake.durable[key],
    };
    for (final key in RestoreJournalStores.all) {
      fake.durable[key] = '{"partial":true}';
      fake.cache[key] = '{"partial":true}';
    }
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
    return fake;
  }

  test(
    'applyBlocking refuses and allows learning writes on all three owners',
    () async {
      final t = await load(FakePreferencesService());
      t.recovery.applyBlocking(true);
      expect(t.kana.isRestoreJournalBlocked, isTrue);
      expect(t.kanji.isRestoreJournalBlocked, isTrue);
      expect(t.words.isRestoreJournalBlocked, isTrue);
      await expectLater(
        t.words.introduce('word:あい', at: DateTime(2026, 9, 14)),
        throwsA(isA<ProgressRestoreJournalBlocked>()),
      );

      t.recovery.applyBlocking(false);
      expect(t.kana.isRestoreJournalBlocked, isFalse);
      expect(t.kanji.isRestoreJournalBlocked, isFalse);
      expect(t.words.isRestoreJournalBlocked, isFalse);
      await t.words.introduce('word:あい', at: DateTime(2026, 9, 14));
      expect(t.words.statForItem('word:あい').isSeen, isTrue);
    },
  );

  test('syncFromPlatform reads the journal the platform holds now', () async {
    final t = await load(FakePreferencesService());
    expect(await t.recovery.syncFromPlatform(), isFalse);
    expect(t.recovery.needsRecovery, isFalse);

    // Another writer (an aborted in-session restore) leaves a corrupt journal
    // on the platform; the cache has not seen it yet.
    t.fake.durable[ProgressRestoreJournal.journalKey] = 'not json';
    expect(t.recovery.needsRecovery, isFalse, reason: 'cached view');
    expect(await t.recovery.syncFromPlatform(), isTrue);
    expect(t.recovery.needsRecovery, isTrue);
    expect(t.kana.isRestoreJournalBlocked, isTrue);
    expect(t.words.isRestoreJournalBlocked, isTrue);

    t.fake.durable.remove(ProgressRestoreJournal.journalKey);
    expect(await t.recovery.syncFromPlatform(), isFalse);
    expect(t.words.isRestoreJournalBlocked, isFalse);
  });

  test(
    'recover keeps blocking while the journal cannot be rolled back',
    () async {
      final fake = await seedRollableJournal();
      fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {2};
      final t = await load(fake);
      t.recovery.applyBlocking(true);

      expect(await t.recovery.recover(), isTrue);
      expect(t.recovery.needsRecovery, isTrue);
      expect(t.kana.isRestoreJournalBlocked, isTrue);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNotNull);
    },
  );

  test(
    'recover rolls primaries back, reloads the owners and lifts blocking',
    () async {
      final fake = await seedRollableJournal();
      final t = await load(fake);
      t.recovery.applyBlocking(true);
      expect(t.kana.learnedUnits, isNot(contains('keep_me')));

      expect(await t.recovery.recover(), isFalse);
      expect(t.recovery.needsRecovery, isFalse);
      expect(fake.durable[ProgressRestoreJournal.journalKey], isNull);
      expect(t.kana.learnedUnits, contains('keep_me'));
      expect(t.kana.isRestoreJournalBlocked, isFalse);
      expect(t.kanji.isRestoreJournalBlocked, isFalse);
      expect(t.words.isRestoreJournalBlocked, isFalse);
    },
  );

  group('ProgressRestoreRecoveryController', () {
    test('construction applies the startup verdict to the owners', () async {
      final t = await load(FakePreferencesService());
      final controller = ProgressRestoreRecoveryController(
        recovery: t.recovery,
        needsRecovery: true,
      );
      expect(controller.needsRecovery, isTrue);
      expect(t.words.isRestoreJournalBlocked, isTrue);
      controller.dispose();
    });

    test('syncFromPlatform notifies only when the verdict moves', () async {
      final t = await load(FakePreferencesService());
      final controller = ProgressRestoreRecoveryController(
        recovery: t.recovery,
        needsRecovery: false,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.syncFromPlatform();
      expect(notifications, 0);

      t.fake.durable[ProgressRestoreJournal.journalKey] = 'not json';
      await controller.syncFromPlatform();
      expect(controller.needsRecovery, isTrue);
      expect(notifications, 1);
      await controller.syncFromPlatform();
      expect(notifications, 1);
      controller.dispose();
    });

    test(
      'retry clears needsRecovery once recovery lands, else keeps it',
      () async {
        final fake = await seedRollableJournal();
        fake.failWriteOnAttempt[ProgressStoreKeys.learnedUnits] = {2};
        final t = await load(fake);
        final controller = ProgressRestoreRecoveryController(
          recovery: t.recovery,
          needsRecovery: true,
        );
        final retrying = <bool>[];
        controller.addListener(() => retrying.add(controller.isRetrying));

        await controller.retry();
        expect(controller.needsRecovery, isTrue);
        expect(retrying, [true, false]);

        fake.failWriteOnAttempt.clear();
        await controller.retry();
        expect(controller.needsRecovery, isFalse);
        expect(t.kana.learnedUnits, contains('keep_me'));
        expect(t.words.isRestoreJournalBlocked, isFalse);
        controller.dispose();
      },
    );
  });
}
