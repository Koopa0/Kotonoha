// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/home/home_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/restore_recovery_test_support.dart';

/// Reads the home's ViewModel contract without pumping a widget: which doors
/// the derived state opens, the ambient next step for a new and an older
/// learner, the tiny-pool gate on 今日の稽古, the unlock acknowledgement, the
/// travel plan's daily cursor, and the recovery hold.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 6, 10, 12);

  Future<
    ({
      HomeViewModel vm,
      KanaProgressRepository kana,
      WordProgressRepository words,
      TravelFocusRepository travel,
    })
  >
  makeVm({DateTime Function()? clock, bool needsRecovery = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await PreferencesService.create();
    final kana = await KanaProgressRepository.load(prefs);
    final kanji = await KanjiReadingRepository.load(prefs);
    final words = await WordProgressRepository.load(prefs);
    final travel = await TravelFocusRepository.load(prefs);
    final vm = HomeViewModel(
      kana: kana,
      words: words,
      kanji: kanji,
      travel: travel,
      persistence: ProgressPersistenceController(
        kanaFlush: kana.flushPending,
        kanjiFlush: kanji.flushPending,
        wordFlush: words.flushPending,
      ),
      recovery: recoveryForRepos(
        prefs: prefs,
        kana: kana,
        kanji: kanji,
        words: words,
        needsRecovery: needsRecovery,
      ),
      clock: clock ?? () => at,
      rng: Random(0),
    );
    return (vm: vm, kana: kana, words: words, travel: travel);
  }

  /// Learns every row of both syllabaries, which is what opens the reading
  /// tracks. Nothing is answered, so no kana is met.
  Future<void> learnEveryRow(KanaProgressRepository kana) async {
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
  }

  test('a cold start is sent to be taught, with every door shut', () async {
    final t = await makeVm();
    final home = t.vm.state;
    expect(home.isColdStart, isTrue);
    expect(home.hasLearnedUnit, isFalse);
    expect(home.gojuonSeen, 0);
    expect(home.gojuonTotal, 92);
    expect(home.gojuonCoverage, 0);
    expect(home.step.target, GuidanceTarget.lessons);
    expect(home.wordsReadable, isFalse);
    expect(home.phrasesReadable, isFalse);
    expect(home.kanjiPhrasesReadable, isFalse);
    expect(home.dictationReady, isFalse);
    expect(home.listeningReady, isFalse);
    expect(home.confusableReady, isFalse);
    expect(home.dailyReady, isFalse);
    expect(home.travelActive, isFalse);
    expect(home.pendingUnlock, isNull);
    expect(t.vm.composeConfusable(), isEmpty);
    t.vm.dispose();
  });

  test('a lone ん is learned but cannot open 今日の稽古', () async {
    final t = await makeVm();
    await t.kana.markUnitLearned('hira_row_10'); // ん alone
    final home = t.vm.state;
    expect(home.hasLearnedUnit, isTrue);
    // A single kana can neither discriminate nor be recalled cold.
    expect(home.dailyReady, isFalse);
    expect(home.step.target, GuidanceTarget.lessons);
    t.vm.dispose();
  });

  test('a met あ行 opens the review door and the look-alike drill', () async {
    final t = await makeVm();
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    await t.kana.markUnitLearned('hira_row_0');
    for (final k in t.kana.gojuonForScript(KanaScript.hiragana).take(5)) {
      await t.kana.recordAnswer(k, correct: true, at: at, latencyMs: 300);
    }
    final home = t.vm.state;
    expect(home.isColdStart, isFalse);
    expect(home.gojuonSeen, 5);
    expect(home.dailyReady, isTrue);
    expect(home.confusableReady, isTrue);
    expect(notifications, greaterThan(0));
    // 今日の稽古 only ever reviews what has been met — never a cold kana.
    final met = StudySet.reviewPool(t.kana).map((k) => k.id).toSet();
    final targets = t.vm
        .composeDaily()
        .kana
        .map((i) => i.question.target.id)
        .toSet();
    expect(targets, isNotEmpty);
    expect(targets.difference(met), isEmpty);
    t.vm.dispose();
  });

  test('手習い draws at most a dozen, all from the review pool', () async {
    final t = await makeVm();
    await learnEveryRow(t.kana);
    final pool = StudySet.reviewPool(t.kana).map((k) => k.id).toSet();
    final drawn = t.vm.composeWriting();
    expect(drawn, hasLength(12));
    expect(drawn.map((k) => k.id).toSet().difference(pool), isEmpty);
    t.vm.dispose();
  });

  test('the words track opens with one unlock line, then settles', () async {
    final t = await makeVm();
    await learnEveryRow(t.kana);
    expect(t.vm.state.wordsReadable, isTrue);
    expect(t.vm.state.pendingUnlock, Unlock.words);
    // 文字起こし stays shut until a readable word has actually been met.
    expect(t.vm.state.dictationReady, isFalse);

    t.vm.markUnlockSeen(Unlock.words);
    await t.kana.flushPending();
    expect(t.vm.state.pendingUnlock, isNot(Unlock.words));
    t.vm.dispose();
  });

  test('a met word opens 文字起こし and the ambient line moves on', () async {
    final t = await makeVm();
    await learnEveryRow(t.kana);
    for (final unlock in Unlock.values) {
      await t.kana.markUnlockSeen(unlock.id);
    }
    await t.words.recordAnswer('word:あい', correct: true, at: at);
    final home = t.vm.state;
    expect(home.dictationReady, isTrue);
    expect(home.pendingUnlock, isNull);
    expect(home.step.target, isNot(GuidanceTarget.lessons));
    t.vm.dispose();
  });

  test('a served travel step holds for the day, then reopens', () async {
    var now = at;
    final t = await makeVm(clock: () => now);
    await learnEveryRow(t.kana);
    for (final unlock in Unlock.values) {
      await t.kana.markUnlockSeen(unlock.id);
    }
    await t.travel.saveFocuses([
      const TravelFocus(scene: TravelSceneId.transport),
    ]);
    expect(t.vm.state.step.target, GuidanceTarget.travelMeet);
    expect(t.vm.state.step.scene, TravelSceneId.transport);

    t.vm.markTravelServed(TravelSceneId.transport);
    expect(t.vm.state.step.target, GuidanceTarget.travelHold);

    // Nothing more is written; only the day moves. The derived state reads
    // the clock afresh, so tomorrow's step is open again.
    now = at.add(const Duration(days: 1));
    expect(t.vm.state.step.target, GuidanceTarget.travelMeet);
    expect(t.vm.state.step.scene, TravelSceneId.transport);
    t.vm.dispose();
  });

  test('a saved travel plan runs, and its cursor moves once served', () async {
    final t = await makeVm();
    expect(t.vm.travelActive, isFalse);
    await t.travel.saveFocuses([
      const TravelFocus(scene: TravelSceneId.transport),
    ]);
    expect(t.vm.travelActive, isTrue);
    expect(t.vm.state.travelActive, isTrue);

    expect(t.travel.plan.servedOn[TravelSceneId.transport], isNull);
    t.vm.markTravelServed(TravelSceneId.transport);
    expect(t.travel.plan.servedOn[TravelSceneId.transport], isNotNull);

    expect(t.travel.plan.kanaBoostOn, isNull);
    t.vm.markTravelBoost();
    expect(t.travel.plan.kanaBoostOn, isNotNull);
    t.vm.dispose();
  });

  test('a cleared plan takes no cursor writes at all', () async {
    final t = await makeVm();
    t.vm.markTravelServed(TravelSceneId.hotel);
    t.vm.markTravelBoost();
    expect(t.travel.plan.servedOn, isEmpty);
    expect(t.travel.plan.kanaBoostOn, isNull);
    t.vm.dispose();
  });

  test('unconfirmed durable state holds learning', () async {
    final blocked = await makeVm(needsRecovery: true);
    expect(blocked.vm.learningBlocked, isTrue);
    blocked.vm.dispose();

    final open = await makeVm();
    expect(open.vm.learningBlocked, isFalse);
    open.vm.dispose();
  });
}
