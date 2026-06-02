// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A fixed clock so every state is deterministic.
  final now = DateTime(2026, 6, 1, 12);

  // The five kana of あ行 (the first learnable row), for seeding due reviews.
  List<Kana> aRow(KanaProgressRepository store) => store
      .gojuonForScript(KanaScript.hiragana)
      .where((k) => k.row == 0)
      .toList();

  test('A — nothing learned: start the lessons', () async {
    final store = await KanaProgressRepository.load();

    final step = Guidance.nextStep(store, now: now);

    expect(step, const GuidanceStep(GuidanceTarget.lessons));
    expect(step.dueCount, 0);
  });

  test('B — reviews due: today\'s session, carrying the count', () async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0'); // あ行
    // Make exactly two of the learned kana due (a missed answer an hour ago
    // schedules a soon review that has since elapsed).
    final past = now.subtract(const Duration(hours: 1));
    await store.recordAnswer(aRow(store)[0], correct: false, at: past);
    await store.recordAnswer(aRow(store)[1], correct: false, at: past);

    final step = Guidance.nextStep(store, now: now);

    expect(step.target, GuidanceTarget.daily);
    expect(step.dueCount, 2);
  });

  test('C — caught up but rows remain: keep learning', () async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0');
    // A fast, correct answer pushes dueAt a day out, so nothing is due now.
    await store.recordAnswer(
      aRow(store).first,
      correct: true,
      at: now.subtract(const Duration(minutes: 1)),
      latencyMs: 300,
    );

    final step = Guidance.nextStep(store, now: now);

    expect(step.target, GuidanceTarget.lessons);
    expect(step.dueCount, 0);
    expect(step.target, isNot(GuidanceTarget.daily)); // distinct from B
  });

  test('D — every row learned and nothing due: rest', () async {
    final store = await KanaProgressRepository.load();
    for (final lesson in Lessons.fromKana(store.allKana)) {
      await store.markUnitLearned(lesson.id);
    }

    final step = Guidance.nextStep(store, now: now);

    expect(step, const GuidanceStep(GuidanceTarget.rest));
    expect(step.dueCount, 0);
  });

  test('A wins over the reviewPool cold-start fallback', () async {
    final store = await KanaProgressRepository.load();
    // Nothing is learned, but make あ "due". reviewPool falls back to あ行(5),
    // so a naive due-check would fire B — A must short-circuit first.
    await store.recordAnswer(
      aRow(store).first,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );

    final step = Guidance.nextStep(store, now: now);

    expect(step.target, GuidanceTarget.lessons);
    expect(step.dueCount, 0);
  });

  test('B/C flip on the clock: due now is B, not-yet-due is C', () async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0');
    await store.recordAnswer(
      aRow(store).first,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );

    // At `now` the review has elapsed → due → B.
    expect(Guidance.nextStep(store, now: now).target, GuidanceTarget.daily);

    // Rewind before it was scheduled → nothing due → falls through to C.
    final earlier = now.subtract(const Duration(hours: 2));
    final step = Guidance.nextStep(store, now: earlier);
    expect(step.target, GuidanceTarget.lessons);
    expect(step.dueCount, 0);
  });

  test('GuidanceStep has value equality', () {
    expect(
      const GuidanceStep(GuidanceTarget.daily, dueCount: 2),
      const GuidanceStep(GuidanceTarget.daily, dueCount: 2),
    );
    expect(
      const GuidanceStep(GuidanceTarget.daily, dueCount: 2) ==
          const GuidanceStep(GuidanceTarget.daily, dueCount: 3),
      isFalse,
    );
    expect(
      const GuidanceStep(GuidanceTarget.lessons),
      const GuidanceStep(GuidanceTarget.lessons),
    );
  });
}
