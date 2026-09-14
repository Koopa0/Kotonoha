// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/ui/study/study_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the 手解き ViewModel's contract without pumping a widget: the
/// encode pass, the optional recap lap and its reveal, and how the row test
/// is composed against the other learned rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
    ({StudyViewModel vm, KanaProgressRepository kana, List<Lesson> catalog})
  >
  makeVm({int lessonIndex = 0}) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final catalog = Lessons.fromKana(kana.allKana);
    final vm = StudyViewModel(
      lesson: catalog[lessonIndex],
      kana: kana,
      rng: Random(0),
    );
    return (vm: vm, kana: kana, catalog: catalog);
  }

  test('opens on the first encode card', () async {
    final t = await makeVm();
    expect(t.vm.phase, StudyPhase.encode);
    expect(t.vm.isRecap, isFalse);
    expect(t.vm.index, 0);
    expect(t.vm.cards, t.vm.lesson.kana);
    expect(t.vm.current, t.vm.lesson.kana.first);
    expect(t.vm.isLast, isFalse);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.offersRecap, isFalse);
    t.vm.dispose();
  });

  test(
    'paging follows the card; the last encode card offers the lap',
    () async {
      final t = await makeVm();
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      t.vm.showCard(1);
      expect(t.vm.index, 1);
      expect(t.vm.current, t.vm.cards[1]);
      t.vm.showCard(1); // settled on the same card — silent
      expect(notifications, 1);
      t.vm.showCard(t.vm.cards.length - 1);
      expect(t.vm.isLast, isTrue);
      expect(t.vm.offersRecap, isTrue);
      // Encode cards never hide their romaji: reveal is not a step here.
      t.vm.reveal();
      expect(t.vm.isRevealed, isFalse);
      expect(notifications, 2);
      t.vm.dispose();
    },
  );

  test(
    'the recap walks the same row from the top, romaji behind a tap',
    () async {
      final t = await makeVm();
      t.vm.enterRecap(); // not offered before the last encode card
      expect(t.vm.isRecap, isFalse);

      t.vm.showCard(t.vm.cards.length - 1);
      t.vm.enterRecap();
      expect(t.vm.phase, StudyPhase.recap);
      expect(t.vm.index, 0);
      expect(t.vm.isRevealed, isFalse);
      expect(t.vm.offersRecap, isFalse);

      t.vm.reveal();
      expect(t.vm.isRevealed, isTrue);
      t.vm.reveal(); // already shown — silent
      t.vm.showCard(1);
      expect(t.vm.isRevealed, isFalse); // hidden again on the next card
      t.vm.showCard(t.vm.cards.length - 1);
      expect(t.vm.isLast, isTrue);
      expect(t.vm.offersRecap, isFalse); // the lap is over: test only
      t.vm.enterRecap(); // no second lap from here
      expect(t.vm.index, t.vm.cards.length - 1);
      t.vm.dispose();
    },
  );

  test(
    'the row test covers this lesson and interleaves learned rows',
    () async {
      final t = await makeVm(lessonIndex: 1);
      final lesson = t.vm.lesson;
      final other = t.catalog.first;
      expect(other.script, lesson.script);
      await t.kana.markUnitLearned(other.id);

      final questions = t.vm.composeTest();
      expect(questions, isNotEmpty);
      final targets = questions.map((q) => q.target.id).toSet();
      final lessonIds = lesson.kana.map((k) => k.id).toSet();
      final allowed = {...lessonIds, ...other.kana.map((k) => k.id)};
      expect(targets.containsAll(lessonIds), isTrue);
      expect(targets.difference(allowed), isEmpty);
      t.vm.dispose();
    },
  );

  test('without other learned rows the test stays within the lesson', () async {
    final t = await makeVm();
    final targets = t.vm.composeTest().map((q) => q.target.id).toSet();
    expect(targets, t.vm.lesson.kana.map((k) => k.id).toSet());
    t.vm.dispose();
  });
}
