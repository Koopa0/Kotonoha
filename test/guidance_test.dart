// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<KanaProgressRepository> kanaGraduated() async {
    final store = await KanaProgressRepository.load();
    for (final lesson in Lessons.fromKana(store.allKana)) {
      await store.markUnitLearned(lesson.id);
    }
    return store;
  }

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

  test('F — every row learned and nothing due anywhere: rest', () async {
    final store = await kanaGraduated();

    final step = Guidance.nextStep(store, now: now);

    expect(step, const GuidanceStep(GuidanceTarget.rest));
    expect(step.dueCount, 0);
  });

  test(
    'D — reading-era due: the track whose oldest item waited longest wins',
    () async {
      final store = await KanaProgressRepository.load();
      for (final lesson in Lessons.fromKana(store.allKana)) {
        await store.markUnitLearned(lesson.id);
      }

      final step = Guidance.nextStep(
        store,
        now: now,
        words: TrackDue(
          dueCount: 5,
          oldestDue: now.subtract(const Duration(days: 2)),
        ),
        kanji: TrackDue(
          dueCount: 1,
          oldestDue: now.subtract(const Duration(days: 6)),
        ),
      );

      // Fewer due, but its oldest waited longest — kanji is not starved by the
      // words track's bigger backlog.
      expect(step.target, GuidanceTarget.kanji);
      expect(step.dueCount, 1);
    },
  );

  test('D — a full session of reviews outranks meeting new material', () async {
    final store = await kanaGraduated();

    final step = Guidance.nextStep(
      store,
      now: now,
      words: TrackDue(
        unmet: 200,
        lastMet: now.subtract(const Duration(days: 1)),
      ),
      sentences: TrackDue(
        dueCount: Guidance.kReviewFirstBacklog,
        oldestDue: now.subtract(const Duration(hours: 1)),
        lastMet: now.subtract(const Duration(days: 1)),
      ),
    );

    expect(step.target, GuidanceTarget.sentences);
    expect(step.dueCount, Guidance.kReviewFirstBacklog);
  });

  test(
    'a backlog smaller than a session yields to the neglected track',
    () async {
      final store = await kanaGraduated();

      // Two items due is not a day's work. Spending the slack on new material
      // costs nothing — what stays due is still due tomorrow — and it is the
      // only thing that keeps the words track (whose meeting beat is a separate
      // room) from going months without an introduction.
      final step = Guidance.nextStep(
        store,
        now: now,
        words: TrackDue(
          unmet: 200,
          lastMet: now.subtract(const Duration(days: 9)),
        ),
        sentences: TrackDue(
          dueCount: 2,
          oldestDue: now.subtract(const Duration(hours: 1)),
          lastMet: now.subtract(const Duration(hours: 1)),
        ),
      );

      expect(step.target, GuidanceTarget.ferry);
    },
  );

  test(
    'E — cold start: with nothing ever met, declaration order breaks the tie',
    () async {
      final store = await kanaGraduated();

      expect(
        Guidance.nextStep(
          store,
          now: now,
          words: const TrackDue(unmet: 3),
          sentences: const TrackDue(unmet: 9),
          kanji: const TrackDue(unmet: 100),
        ).target,
        GuidanceTarget.ferry,
      );
      expect(
        Guidance.nextStep(
          store,
          now: now,
          sentences: const TrackDue(unmet: 9),
          kanji: const TrackDue(unmet: 100),
        ).target,
        GuidanceTarget.sentences,
      );
      expect(
        Guidance.nextStep(
          store,
          now: now,
          kanji: const TrackDue(unmet: 100),
        ).target,
        GuidanceTarget.kanji,
      );
    },
  );

  test(
    'E — the track NEGLECTED longest gets the introduction, not the biggest',
    () async {
      final store = await kanaGraduated();

      // The words track is huge and was touched an hour ago; the sentence track
      // is small and has not been touched in a week. A first-match curriculum
      // chain would point at 渡し舟 for months — the whole reason E sorts.
      final step = Guidance.nextStep(
        store,
        now: now,
        words: TrackDue(
          unmet: 250,
          lastMet: now.subtract(const Duration(hours: 1)),
        ),
        kanjiSentences: TrackDue(
          unmet: 4,
          lastMet: now.subtract(const Duration(days: 7)),
        ),
      );

      expect(step.target, GuidanceTarget.kanjiSentences);
    },
  );

  test(
    'E — a track never touched at all outranks every track that has been',
    () async {
      final store = await kanaGraduated();

      final step = Guidance.nextStep(
        store,
        now: now,
        words: TrackDue(
          unmet: 250,
          lastMet: now.subtract(const Duration(days: 30)),
        ),
        kanji: const TrackDue(unmet: 100), // lastMet null — never met
      );

      expect(step.target, GuidanceTarget.kanji);
    },
  );

  test('D — a due mixed-script sentence routes to 名残の仮名', () async {
    final store = await kanaGraduated();

    final step = Guidance.nextStep(
      store,
      now: now,
      kanjiSentences: TrackDue(
        dueCount: 2,
        oldestDue: now.subtract(const Duration(days: 1)),
      ),
    );

    expect(step.target, GuidanceTarget.kanjiSentences);
    expect(step.dueCount, 2);
  });

  test(
    'the kana era always speaks first: kana due outranks every track',
    () async {
      final store = await KanaProgressRepository.load();
      for (final lesson in Lessons.fromKana(store.allKana)) {
        await store.markUnitLearned(lesson.id);
      }
      await store.recordAnswer(
        aRow(store).first,
        correct: false,
        at: now.subtract(const Duration(hours: 1)),
      );

      final step = Guidance.nextStep(
        store,
        now: now,
        words: TrackDue(
          dueCount: 50,
          oldestDue: now.subtract(const Duration(days: 30)),
        ),
      );

      expect(step.target, GuidanceTarget.daily);
    },
  );

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

  test('general mode is unchanged when no travel plan is set', () async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0');
    await store.recordAnswer(
      aRow(store).first,
      correct: true,
      at: now.subtract(const Duration(minutes: 1)),
      latencyMs: 300,
    );

    final step = Guidance.nextStep(store, now: now);
    expect(step.target, GuidanceTarget.lessons);
  });

  test('travel prep: one due kana boost then a readable scene, leftover rows do not block', () async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0');
    await store.markUnitLearned('hira_row_1');
    await store.recordAnswer(
      aRow(store).first,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    final plan = TravelFocusPlan.empty.withFocuses(const [
      TravelFocus(scene: TravelSceneId.transport),
    ]);
    final learnedChars = StudySet.learned(store)
        .map((k) => k.character)
        .toSet();
    final views = {
      TravelSceneId.transport: TravelScene.inspect(
        scene: TravelSceneId.transport,
        learnedChars: learnedChars,
        stats: const {},
        now: now,
      ),
    };

    final boost = Guidance.nextStep(
      store,
      now: now,
      travelPlan: plan,
      travelViews: views,
    );
    expect(boost.target, GuidanceTarget.daily);
    expect(boost.dueCount, greaterThan(0));

    final after = Guidance.nextStep(
      store,
      now: now,
      travelPlan: plan.markKanaBoost(now),
      travelViews: views,
    );
    expect(after.target, GuidanceTarget.travelMeet);
    expect(after.scene, TravelSceneId.transport);
    expect(after.isMeet, isTrue);
  });

  test(
    'travel prep hold is not rest-complete after both scenes ran today',
    () async {
      final store = await KanaProgressRepository.load();
      await store.markUnitLearned('hira_row_0');
      final plan = TravelFocusPlan.empty
          .withFocuses(const [
            TravelFocus(scene: TravelSceneId.transport),
            TravelFocus(scene: TravelSceneId.clothing),
          ])
          .markKanaBoost(now)
          .markServed(TravelSceneId.transport, now)
          .markServed(TravelSceneId.clothing, now);

      final step = Guidance.nextStep(store, now: now, travelPlan: plan);
      expect(step.target, GuidanceTarget.travelHold);
      expect(step.target, isNot(GuidanceTarget.rest));
    },
  );

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
