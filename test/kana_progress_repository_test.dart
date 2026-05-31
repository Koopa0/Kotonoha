// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const all = kHiraganaGojuon;
  final now = DateTime(2026, 5, 29, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty', () async {
    final store = await KanaProgressRepository.load();
    expect(store.seenCount, 0);
    expect(store.totalCount, 208); // 92 gojūon + 116 extended
    expect(store.statFor(all.first).isSeen, isFalse);
  });

  test('recordAnswer updates seen/correct/wrong and lastReviewedAt', () async {
    final store = await KanaProgressRepository.load();
    final kana = all.first;

    await store.recordAnswer(kana, correct: true, at: now);
    await store.recordAnswer(kana, correct: false, at: now);

    final stat = store.statFor(kana);
    expect(stat.seenCount, 2);
    expect(stat.correctCount, 1);
    expect(stat.wrongCount, 1);
    expect(stat.lastReviewedAt, now);
    expect(store.seenCount, 1);
  });

  test('persists across reloads', () async {
    final store = await KanaProgressRepository.load();
    await store.recordAnswer(all[5], correct: true, at: now);

    final reloaded = await KanaProgressRepository.load();
    final stat = reloaded.statFor(all[5]);
    expect(stat.seenCount, 1);
    expect(stat.correctCount, 1);
    expect(stat.lastReviewedAt, now);
  });

  test('status classification reflects accuracy', () async {
    final store = await KanaProgressRepository.load();
    final kana = all[2];
    for (var i = 0; i < 5; i++) {
      await store.recordAnswer(kana, correct: true, at: now);
    }
    expect(store.statFor(kana).status, KanaStatus.strong);
    expect(store.countWithStatus(KanaStatus.strong), 1);
    expect(store.countWithStatus(KanaStatus.unseen), 207);
  });

  test('reset clears everything', () async {
    final store = await KanaProgressRepository.load();
    await store.recordAnswer(all[0], correct: true, at: now);
    await store.markUnitLearned('hira_row_0');
    await store.reset();
    expect(store.seenCount, 0);
    expect(store.isUnitLearned('hira_row_0'), isFalse);
  });

  group('learned units', () {
    test('marks a unit learned and persists across reloads', () async {
      final store = await KanaProgressRepository.load();
      expect(store.isUnitLearned('hira_row_1'), isFalse);

      await store.markUnitLearned('hira_row_1');
      expect(store.isUnitLearned('hira_row_1'), isTrue);
      expect(store.learnedUnitCount, 1);

      final reloaded = await KanaProgressRepository.load();
      expect(reloaded.isUnitLearned('hira_row_1'), isTrue);
    });

    test('marking the same unit twice is idempotent', () async {
      final store = await KanaProgressRepository.load();
      await store.markUnitLearned('hira_row_2');
      await store.markUnitLearned('hira_row_2');
      expect(store.learnedUnitCount, 1);
    });
  });

  test('confusable kana get a halved review interval', () async {
    final store = await KanaProgressRepository.load();
    final ki = all.firstWhere((k) => k.character == 'き'); // き is in a set
    await store.recordAnswer(ki, correct: true, at: now, latencyMs: 200);
    // level 1 base = 1 day (1440 min); confusable scale 0.5 → 720.
    expect(store.statFor(ki).dueAt!.difference(now).inMinutes, 720);
  });
}
