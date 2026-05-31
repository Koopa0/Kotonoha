// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('learned is empty before any lesson is passed', () async {
    final store = await KanaProgressRepository.load();
    expect(StudySet.learned(store), isEmpty);
  });

  test('reviewPool falls back to あ行 (5) at cold start', () async {
    final store = await KanaProgressRepository.load();
    final pool = StudySet.reviewPool(store);
    expect(pool.length, 5);
    expect(pool.every((k) => k.script == KanaScript.hiragana), isTrue);
    expect(pool.every((k) => k.row == 0), isTrue);
  });

  test('learned/reviewPool reflect passed lessons', () async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0'); // あ行
    await store.markUnitLearned('hira_row_1'); // か行

    final learned = StudySet.learned(store);
    expect(learned.length, 10); // two rows of 5
    expect(learned.map((k) => k.character), containsAll(['あ', 'か']));
    // Once anything is learned, reviewPool is exactly the learned set.
    expect(StudySet.reviewPool(store).length, learned.length);
  });
}
