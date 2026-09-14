// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/ui/travel/travel_scene_hub_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the travel scene door ViewModel's contract without pumping a
/// widget: which doors are open at each stage (kana first → meet → recall
/// / listen), how each session behind them is composed, that a 「もう一回」
/// grind never re-introduces covered ids, and that the doors follow the
/// owners.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);

  Future<
    ({
      TravelSceneHubViewModel vm,
      KanaProgressRepository kana,
      WordProgressRepository words,
    })
  >
  makeVm({TravelSceneId scene = TravelSceneId.transport}) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final vm = TravelSceneHubViewModel(
      scene: scene,
      kana: kana,
      words: words,
      clock: () => now,
      rng: Random(0),
    );
    return (vm: vm, kana: kana, words: words);
  }

  Future<void> learnAllKana(KanaProgressRepository kana) async {
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
  }

  Future<void> meetEverything(
    TravelSceneHubViewModel vm,
    WordProgressRepository words,
  ) async {
    for (final item in vm.view.unreadReadable) {
      await words.introduce(item.progressId, at: now);
    }
  }

  test('a fresh learner is sent to the kana first', () async {
    final t = await makeVm();
    final view = t.vm.view;
    expect(view.scene, TravelSceneId.transport);
    expect(view.needsKanaFirst, isTrue);
    expect(view.canRecall, isFalse);
    expect(view.canListen, isFalse);
    expect(t.vm.composeReview(), isEmpty);
    t.vm.dispose();
  });

  test('with the kana learned the door is meet, not recall', () async {
    final t = await makeVm();
    await learnAllKana(t.kana);
    final view = t.vm.view;
    expect(view.needsKanaFirst, isFalse);
    expect(view.unreadable, isEmpty);
    expect(view.missingUnits, isEmpty);
    expect(view.canMeet, isTrue);
    expect(view.canRecall, isFalse);
    expect(view.canListen, isFalse);
    final words = t.vm.composeIntroWords();
    expect(words, isNotEmpty);
    expect(words.length, lessThanOrEqualTo(TravelScene.length));
    expect(t.vm.hasMoreIntro(), isTrue);
    expect(t.vm.composeReview(), isEmpty);
    t.vm.dispose();
  });

  test('once everything is met, recall and listening open', () async {
    final t = await makeVm();
    await learnAllKana(t.kana);
    await meetEverything(t.vm, t.words);
    final view = t.vm.view;
    expect(view.canMeet, isFalse);
    expect(view.canRecall, isTrue);
    expect(view.canListen, isTrue);
    expect(t.vm.composeIntroWords(), isEmpty);
    expect(t.vm.composeIntroPhrases(), isEmpty);
    expect(t.vm.hasMoreIntro(), isFalse);
    final review = t.vm.composeReview();
    expect(review, isNotEmpty);
    expect(review.length, lessThanOrEqualTo(TravelScene.length));
    t.vm.dispose();
  });

  test(
    'a もう一回 grind prefers uncovered ids and wraps only at the end',
    () async {
      final t = await makeVm();
      await learnAllKana(t.kana);
      final first = t.vm.composeIntroWords();
      final covered = first.map((w) => w.progressId).toSet();
      final unreadWords = t.vm.view.unreadReadable
          .map((i) => i.progressId)
          .where((id) => id.startsWith('word:'))
          .toSet();
      final second = t.vm.composeIntroWords(excludeProgressIds: covered);
      expect(second, isNotEmpty);
      if (unreadWords.difference(covered).isNotEmpty) {
        // Other unread words remain: the covered ones are left out.
        expect(
          second.map((w) => w.progressId).toSet().intersection(covered),
          isEmpty,
        );
      }
      // With every unread id covered the pool wraps around rather than
      // padding from another scene — the grind stays alive while anything
      // in this scene is unmet…
      final everything = t.vm.view.unreadReadable
          .map((i) => i.progressId)
          .toSet();
      expect(t.vm.hasMoreIntro(excludeProgressIds: everything), isTrue);
      // …and closes once it is all met.
      await meetEverything(t.vm, t.words);
      expect(t.vm.hasMoreIntro(excludeProgressIds: everything), isFalse);
      t.vm.dispose();
    },
  );

  test('the doors follow the kana and word owners', () async {
    final t = await makeVm();
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    await learnAllKana(t.kana);
    expect(notifications, greaterThan(0));
    final afterKana = notifications;
    await meetEverything(t.vm, t.words);
    expect(notifications, greaterThan(afterKana));
    t.vm.dispose();
  });
}
