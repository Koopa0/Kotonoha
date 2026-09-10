// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #36: a tiny learned row must not mint forced-correct Daily items, and a
/// lone valid option must not write recall evidence. 2–3 learned options
/// stay legal; unlearned kana stay out of the Daily target pool (#18).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime(2026, 9, 10, 12);

  test('isReady: ん／ン alone cannot discriminate; わ／や／あ can', () {
    expect(DailySession.isReady(_unit('hira_row_10')), isFalse);
    expect(DailySession.isReady(_unit('kata_row_10')), isFalse);
    expect(DailySession.isReady(_unit('hira_row_9')), isTrue);
    expect(DailySession.isReady(_unit('hira_row_7')), isTrue);
    expect(DailySession.isReady(_unit('hira_row_0')), isTrue);
    expect(DailySession.isReady(_unit('kata_row_9')), isTrue);
    expect(DailySession.isReady(_unit('kata_row_7')), isTrue);
    // Same sound, different scripts — each item still has no same-script peer.
    expect(
      DailySession.isReady([..._unit('hira_row_10'), ..._unit('kata_row_10')]),
      isFalse,
    );
    final n = _unit('hira_row_10').single;
    final wa = _unit('kata_row_9');
    expect(DailySession.canComposeItem(n, [n, ...wa]), isFalse);
    expect(DailySession.canDiscriminate(n, [n, ...wa]), isFalse);
    expect(DailySession.canComposeItem(wa.first, [n, ...wa]), isTrue);
  });

  test('compose: ん／ン yield no Daily items; わ=2, や=3, あ=4', () async {
    final cases = <(String, int?)>[
      ('hira_row_10', null),
      ('kata_row_10', null),
      ('hira_row_9', 2),
      ('kata_row_9', 2),
      ('hira_row_7', 3),
      ('kata_row_7', 3),
      ('hira_row_0', 4),
    ];
    for (final (unitId, optionCount) in cases) {
      final store = await _afterRowPass(unitId, now);
      final pool = StudySet.reviewPool(store);
      final items = DailySession.compose(
        pool: pool,
        stats: store.stats,
        newCandidates: const [],
        now: now,
        rng: Random(1),
      );
      final learnedIds = StudySet.learned(store).map((k) => k.id).toSet();
      if (optionCount == null) {
        expect(items, isEmpty, reason: '$unitId must not open a forced item');
        continue;
      }
      expect(items, isNotEmpty, reason: '$unitId should still open Daily');
      for (final item in items) {
        expect(item.question.isForcedCorrect, isFalse, reason: unitId);
        if (item.question.direction == QuizDirection.kanaRecall) {
          expect(item.question.options, isEmpty, reason: unitId);
        } else {
          expect(item.question.options.length, optionCount, reason: unitId);
        }
        expect(learnedIds.contains(item.question.target.id), isTrue);
      }
    }
  });

  test('forced-correct tap does not write count / SRS / due / speed', () async {
    final store = await _afterRowPass('hira_row_10', now);
    final n = store.allKana.firstWhere((k) => k.character == 'ん');
    final before = store.statFor(n);
    expect(before.correctCount, 2);
    expect(before.srsLevel, 2);

    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(
          question: QuizQuestion(
            target: n,
            direction: QuizDirection.romajiToKana,
            options: [n.character],
            correctIndex: 0,
          ),
          mode: PracticeMode.daily,
        ),
      ],
      repository: store,
      persistence: ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: () async {},
      ),
      analytics: log,
      clock: () => now.add(const Duration(minutes: 5)),
      monotonicMs: () => 400,
    );
    vm.selectAnswer(0);
    expect(vm.lastWasCorrect, isTrue);

    final after = store.statFor(n);
    expect(after.correctCount, before.correctCount);
    expect(after.seenCount, before.seenCount);
    expect(after.srsLevel, before.srsLevel);
    expect(after.dueAt, before.dueAt);
    expect(after.avgLatencyMs, before.avgLatencyMs);
    expect(after.varLatencyMs2, before.varLatencyMs2);
    expect(await log.all(), isEmpty);

    final reloaded = await KanaProgressRepository.load();
    final persisted = reloaded.statFor(n);
    expect(persisted.correctCount, before.correctCount);
    expect(persisted.srsLevel, before.srsLevel);
    expect(persisted.dueAt, before.dueAt);
    expect(persisted.avgLatencyMs, before.avgLatencyMs);
    expect(reloaded.isUnitLearned('hira_row_10'), isTrue);
  });

  test(
    '2-option わ still records a real choice, including after reload',
    () async {
      final store = await _afterRowPass('hira_row_9', now);
      final items = DailySession.compose(
        pool: StudySet.reviewPool(store),
        stats: store.stats,
        newCandidates: const [],
        now: now,
        rng: Random(1),
      );
      expect(items, isNotEmpty);
      expect(items.first.question.options.length, 2);

      final item = items.first;
      final kana = item.question.target;
      final before = store.statFor(kana);
      final answeredAt = now.add(const Duration(minutes: 5));
      final vm = QuizViewModel(
        items: [item],
        repository: store,
        persistence: ProgressPersistenceController(
          kanaFlush: store.flushPending,
          kanjiFlush: () async {},
          wordFlush: () async {},
        ),
        clock: () => answeredAt,
        monotonicMs: () => 400,
      );
      vm.selectAnswer(item.question.correctIndex);
      expect(store.statFor(kana).correctCount, before.correctCount + 1);
      expect(store.statFor(kana).srsLevel, greaterThan(before.srsLevel));

      await store.flushPending();
      final reloaded = await KanaProgressRepository.load();
      expect(reloaded.statFor(kana).correctCount, before.correctCount + 1);
      expect(reloaded.isUnitLearned('hira_row_9'), isTrue);
    },
  );

  test('guidance: due ん alone stays on 手解き, not 今日の稽古', () async {
    final store = await _afterRowPass('hira_row_10', now);
    final n = store.allKana.firstWhere((k) => k.character == 'ん');
    await store.recordAnswer(
      n,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    final step = Guidance.nextStep(store, now: now);
    expect(step.target, GuidanceTarget.lessons);
    expect(step.target, isNot(GuidanceTarget.daily));
  });

  test('strong-fast ん is ready as kanaRecall, not a forced MCQ', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_10');
    final n = store.allKana.firstWhere((k) => k.character == 'ん');
    var at = now;
    for (var i = 0; i < 8; i++) {
      await store.recordAnswer(n, correct: true, at: at, latencyMs: 500);
      at = at.add(const Duration(minutes: 1));
    }
    expect(DailySession.readyForRecall(store.statFor(n), now: now), isTrue);
    expect(
      DailySession.isReady(
        StudySet.learned(store),
        stats: store.stats,
        now: now,
      ),
      isTrue,
    );

    final items = DailySession.compose(
      pool: StudySet.reviewPool(store),
      stats: store.stats,
      newCandidates: const [],
      now: now,
      rng: Random(1),
    );
    expect(items, isNotEmpty);
    expect(
      items.every((i) => i.question.direction == QuizDirection.kanaRecall),
      isTrue,
    );
    expect(items.every((i) => i.question.options.isEmpty), isTrue);
    expect(items.every((i) => !i.question.isForcedCorrect), isTrue);

    final before = store.statFor(n);
    var elapsed = 0;
    var clock = now.add(const Duration(minutes: 5));
    final vm = QuizViewModel(
      items: items,
      repository: store,
      persistence: ProgressPersistenceController(
        kanaFlush: store.flushPending,
        kanjiFlush: () async {},
        wordFlush: () async {},
      ),
      clock: () => clock,
      monotonicMs: () => elapsed,
    );
    elapsed = 500;
    vm.captureUnpromptedRecall();
    clock = clock.add(const Duration(seconds: 10));
    elapsed = 10500;
    vm.gradeRecall(correct: true, unprompted: true);
    expect(store.statFor(n).correctCount, before.correctCount + 1);
    expect(store.statFor(n).avgLatencyMs, 500);
    expect(store.statFor(n).dueAt, isNot(before.dueAt));

    final hintedBefore = store.statFor(n);
    final hinted = QuizViewModel(
      items: items,
      repository: store,
      persistence: ProgressPersistenceController(
        kanaFlush: store.flushPending,
        kanjiFlush: () async {},
        wordFlush: () async {},
      ),
      clock: () => clock,
      monotonicMs: () => 400,
    );
    hinted.captureUnpromptedRecall();
    hinted.gradeRecall(correct: true, unprompted: false);
    expect(store.statFor(n).correctCount, hintedBefore.correctCount);
    expect(store.statFor(n).dueAt, hintedBefore.dueAt);
    expect(store.statFor(n).srsLevel, hintedBefore.srsLevel);
  });

  test('guidance: due ん with undued ワ row is not stuck on daily', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_10');
    await store.markUnitLearned('kata_row_9');
    for (final k in [..._unit('hira_row_10'), ..._unit('kata_row_9')]) {
      await store.recordAnswer(k, correct: true, at: now, latencyMs: 400);
      await store.recordAnswer(k, correct: true, at: now, latencyMs: 400);
    }
    final n = store.allKana.firstWhere((k) => k.character == 'ん');
    await store.recordAnswer(
      n,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );

    final learned = StudySet.learned(store);
    expect(
      DailySession.canComposeItem(n, learned, stats: store.stats, now: now),
      isFalse,
    );
    final step = Guidance.nextStep(store, now: now);
    expect(step.target, GuidanceTarget.lessons);
    expect(step.dueCount, 0);
    expect(step.target, isNot(GuidanceTarget.daily));

    final items = DailySession.compose(
      pool: learned,
      stats: store.stats,
      newCandidates: const [],
      now: now,
      rng: Random(1),
    );
    expect(items, isNotEmpty);
    expect(items.every((i) => i.question.target.character != 'ん'), isTrue);
    expect(
      items.every((i) => i.question.target.script == KanaScript.katakana),
      isTrue,
    );

    // Answering the only composable items must not keep Guidance on daily.
    for (final item in items) {
      await store.recordAnswer(
        item.question.target,
        correct: true,
        at: now.add(const Duration(minutes: 5)),
        latencyMs: 400,
      );
    }
    expect(Guidance.nextStep(store, now: now).target, GuidanceTarget.lessons);
  });

  test(
    'guidance: due strong-fast singleton ん still opens daily via kanaRecall',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await KanaProgressRepository.load();
      await store.markUnitLearned('hira_row_10');
      final n = store.allKana.firstWhere((k) => k.character == 'ん');
      var at = now.subtract(const Duration(days: 8));
      for (var i = 0; i < 3; i++) {
        await store.recordAnswer(n, correct: true, at: at, latencyMs: 500);
        at = at.add(const Duration(minutes: 1));
      }
      expect(DailySession.readyForRecall(store.statFor(n), now: now), isTrue);
      expect(
        DailySession.canComposeItem(
          n,
          StudySet.learned(store),
          stats: store.stats,
          now: now,
        ),
        isTrue,
      );
      final dueAt = store.statFor(n).dueAt;
      expect(dueAt, isNotNull);
      expect(!dueAt!.isAfter(now), isTrue);

      final step = Guidance.nextStep(store, now: now);
      expect(step.target, GuidanceTarget.daily);
      expect(step.dueCount, 1);

      final items = DailySession.compose(
        pool: StudySet.learned(store),
        stats: store.stats,
        newCandidates: const [],
        now: now,
        rng: Random(1),
      );
      expect(items, isNotEmpty);
      expect(items.single.question.direction, QuizDirection.kanaRecall);
      expect(items.single.question.options, isEmpty);
    },
  );

  test('guidance: due あ行 still opens 今日の稽古', () async {
    final store = await _afterRowPass('hira_row_0', now);
    final a = store.allKana.firstWhere((k) => k.character == 'あ');
    await store.recordAnswer(
      a,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    final step = Guidance.nextStep(store, now: now);
    expect(step.target, GuidanceTarget.daily);
    expect(step.dueCount, greaterThan(0));
  });
}

List<Kana> _unit(String unitId) =>
    Lessons.fromKana(kAllKana).firstWhere((l) => l.id == unitId).kana;

/// Lesson-pass equivalent: the unit is marked learned and each focus kana
/// has been answered correctly twice (the row test shows the row twice).
Future<KanaProgressRepository> _afterRowPass(String unitId, DateTime at) async {
  SharedPreferences.setMockInitialValues({});
  final store = await KanaProgressRepository.load();
  await store.markUnitLearned(unitId);
  for (final k in _unit(unitId)) {
    await store.recordAnswer(k, correct: true, at: at, latencyMs: 400);
    await store.recordAnswer(k, correct: true, at: at, latencyMs: 400);
  }
  return store;
}
