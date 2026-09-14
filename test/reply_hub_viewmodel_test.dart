// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/ui/reply/reply_hub_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the 短く返す door ViewModel's contract without pumping a widget:
/// which doors are open at each stage (kana first → meet → practice), how
/// each session behind them is composed, and that the doors follow the
/// owners.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);

  Future<
    ({
      ReplyHubViewModel vm,
      KanaProgressRepository kana,
      WordProgressRepository words,
    })
  >
  makeVm({ReplySceneId scene = ReplySceneId.station}) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final vm = ReplyHubViewModel(
      scene: scene,
      kana: kana,
      words: words,
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
    ReplyHubViewModel vm,
    WordProgressRepository words,
  ) async {
    for (final item in vm.view.unreadRequired) {
      await words.introduce(item.progressId, at: now);
    }
  }

  test('a fresh learner is sent to the kana first', () async {
    final t = await makeVm();
    expect(t.vm.view.needsKanaFirst, isTrue);
    expect(t.vm.view.canPractice, isFalse);
    expect(t.vm.composePractice(), isEmpty);
    t.vm.dispose();
  });

  test('with the kana learned the door is meet, not practice', () async {
    final t = await makeVm();
    await learnAllKana(t.kana);
    final view = t.vm.view;
    expect(view.needsKanaFirst, isFalse);
    expect(view.missingUnits, isEmpty);
    expect(view.canMeet, isTrue);
    expect(view.canPractice, isFalse);
    expect(t.vm.hasUnreadRequired, isTrue);
    expect(t.vm.composeIntroWords(), isNotEmpty);
    expect(t.vm.composePractice(), isEmpty);
    t.vm.dispose();
  });

  test('once everything required is met, practice opens', () async {
    final t = await makeVm();
    await learnAllKana(t.kana);
    await meetEverything(t.vm, t.words);
    final view = t.vm.view;
    expect(view.canMeet, isFalse);
    expect(view.canPractice, isTrue);
    expect(t.vm.hasUnreadRequired, isFalse);
    expect(t.vm.composeIntroWords(), isEmpty);
    expect(t.vm.composeIntroPhrases(), isEmpty);
    final drills = t.vm.composePractice();
    expect(drills, isNotEmpty);
    expect(drills.length, lessThanOrEqualTo(ReplySession.length));
    expect(drills.every((d) => d.scene == ReplySceneId.station), isTrue);
    t.vm.dispose();
  });

  test('another scene composes its own drills', () async {
    final t = await makeVm(scene: ReplySceneId.clothing);
    await learnAllKana(t.kana);
    await meetEverything(t.vm, t.words);
    final drills = t.vm.composePractice();
    expect(drills, isNotEmpty);
    expect(drills.every((d) => d.scene == ReplySceneId.clothing), isTrue);
    t.vm.dispose();
  });

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
