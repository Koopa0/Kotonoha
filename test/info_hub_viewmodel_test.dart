// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/use_cases/info_session.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/ui/info/info_hub_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the 聞き取る数 door ViewModel's contract without pumping a widget:
/// which doors are open at each stage (kana first → meet → practice), how
/// each session behind them is composed, and that the doors follow the
/// owners.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);

  Future<
    ({
      InfoHubViewModel vm,
      KanaProgressRepository kana,
      WordProgressRepository words,
    })
  >
  makeVm() async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final vm = InfoHubViewModel(kana: kana, words: words, rng: Random(0));
    return (vm: vm, kana: kana, words: words);
  }

  Future<void> learnAllKana(KanaProgressRepository kana) async {
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
  }

  Future<void> meetEverything(
    InfoHubViewModel vm,
    WordProgressRepository words,
  ) async {
    for (final item in vm.view.unreadRequired) {
      await words.introduce(item.progressId, at: now);
    }
  }

  test(
    'defaults to the shipped drills and sends a fresh learner to kana',
    () async {
      final t = await makeVm();
      expect(t.vm.drills, kInfoDrills);
      expect(t.vm.view.needsKanaFirst, isTrue);
      expect(t.vm.view.canPractice, isFalse);
      expect(t.vm.composePractice(), isEmpty);
      t.vm.dispose();
    },
  );

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
    expect(drills.length, lessThanOrEqualTo(InfoSession.length));
    t.vm.dispose();
  });

  test('a narrowed drill set composes only from itself', () async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final subset = kInfoDrills.take(2).toList();
    final vm = InfoHubViewModel(
      kana: kana,
      words: words,
      drills: subset,
      rng: Random(0),
    );
    await learnAllKana(kana);
    for (final item in vm.view.unreadRequired) {
      await words.introduce(item.progressId, at: now);
    }
    final drills = vm.composePractice();
    expect(drills, isNotEmpty);
    expect(drills.every(subset.contains), isTrue);
    vm.dispose();
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
