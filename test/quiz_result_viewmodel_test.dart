// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/result/quiz_result_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the end-of-session ViewModel's contract without pumping a widget:
/// the lesson pass gate, the one-time learned-row write, and how the
/// follow-up sessions are composed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  QuizQuestion question(Kana target) => QuizQuestion(
    target: target,
    direction: QuizDirection.kanaToRomaji,
    options: [target.romaji, 'xx', 'yy', 'zz'],
    correctIndex: 0,
  );

  /// One answer per kana of [lesson]; [correct] of them right, the rest wrong.
  QuizResult resultFor(Lesson lesson, {required int correct}) => QuizResult(
    answers: [
      for (var i = 0; i < lesson.kana.length; i++)
        AnsweredQuestion(
          question: question(lesson.kana[i]),
          selectedIndex: i < correct ? 0 : 1,
        ),
    ],
  );

  Future<({QuizResultViewModel vm, KanaProgressRepository kana, Lesson lesson})>
  makeVm({
    required QuizResult Function(Lesson lesson) result,
    bool withLesson = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final lesson = Lessons.fromKana(kana.allKana).first;
    final vm = QuizResultViewModel(
      result: result(lesson),
      lesson: withLesson ? lesson : null,
      kana: kana,
      persistence: ProgressPersistenceController(
        kanaFlush: kana.flushPending,
        kanjiFlush: () async {},
        wordFlush: () async {},
      ),
      rng: Random(0),
    );
    return (vm: vm, kana: kana, lesson: lesson);
  }

  test('a perfect lesson test passes and marks the row learned once', () async {
    final t = await makeVm(result: (l) => resultFor(l, correct: l.kana.length));
    expect(t.vm.isLesson, isTrue);
    expect(t.vm.lessonPassed, isTrue);
    expect(t.vm.isPerfect, isTrue);
    expect(t.vm.isApplied, isFalse);
    expect(t.kana.isUnitLearned(t.lesson.id), isFalse);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    t.vm.applyLessonPass();
    expect(t.vm.isApplied, isTrue);
    expect(t.kana.isUnitLearned(t.lesson.id), isTrue);
    expect(notifications, 1);

    t.vm.applyLessonPass(); // a second visit of the frame must not re-write
    expect(notifications, 1);
    t.vm.dispose();
  });

  test('an all-wrong lesson test does not pass and writes nothing', () async {
    final t = await makeVm(result: (l) => resultFor(l, correct: 0));
    expect(t.vm.lessonPassed, isFalse);
    expect(t.vm.isPerfect, isFalse);
    expect(t.vm.missed, t.lesson.kana);
    t.vm.applyLessonPass();
    expect(t.vm.isApplied, isFalse);
    expect(t.kana.isUnitLearned(t.lesson.id), isFalse);
    t.vm.dispose();
  });

  test('a failed lesson composes a fresh test over its own kana', () async {
    final t = await makeVm(result: (l) => resultFor(l, correct: 0));
    final retry = t.vm.composeRetry();
    expect(retry, isNotEmpty);
    final lessonIds = t.lesson.kana.map((k) => k.id).toSet();
    expect(
      retry.map((q) => q.target.id).toSet().intersection(lessonIds),
      lessonIds,
    );
    t.vm.dispose();
  });

  test(
    'a plain review has no gate and reviews exactly the missed kana',
    () async {
      final t = await makeVm(
        result: (l) => resultFor(l, correct: 2),
        withLesson: false,
      );
      expect(t.vm.isLesson, isFalse);
      expect(t.vm.lessonPassed, isFalse);
      final missed = t.vm.missed;
      expect(missed, t.lesson.kana.skip(2).toList());
      t.vm.applyLessonPass();
      expect(t.vm.isApplied, isFalse);

      final review = t.vm.composeMissedReview();
      expect(review, hasLength(missed.length));
      expect(
        review.map((q) => q.target.id).toSet(),
        missed.map((k) => k.id).toSet(),
      );
      t.vm.dispose();
    },
  );

  test('missed kana are listed once each, in order', () async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final a = kHiraganaGojuon[0];
    final i = kHiraganaGojuon[1];
    final vm = QuizResultViewModel(
      result: QuizResult(
        answers: [
          AnsweredQuestion(question: question(i), selectedIndex: 1),
          AnsweredQuestion(question: question(a), selectedIndex: 0),
          AnsweredQuestion(question: question(i), selectedIndex: 2),
        ],
      ),
      kana: kana,
      persistence: ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: () async {},
      ),
    );
    expect(vm.missed, [i]);
    expect(vm.isPerfect, isFalse);
    vm.dispose();
  });
}
