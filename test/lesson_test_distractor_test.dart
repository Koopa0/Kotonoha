// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #100: lesson row test MCQ distractors must stay inside learned kana ∪ the
/// focus row — same honesty contract as Daily / 目利き. Replaces the audit
/// probe that counted unlearned romaji→kana option slots.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<KanaProgressRepository> storeWithAoLearned() async {
    final store = await KanaProgressRepository.load();
    await store.markUnitLearned('hira_row_0');
    return store;
  }

  List<Kana> learnedOther(KanaProgressRepository store, Lesson lesson) {
    return Lessons.fromKana(store.allKana)
        .where(
          (l) =>
              l.id != lesson.id &&
              l.script == lesson.script &&
              store.isUnitLearned(l.id),
        )
        .expand((l) => l.kana)
        .toList();
  }

  void expectNoUnlearnedDistractors(
    List<QuizQuestion> questions,
    Set<String> allowedIds,
    Map<KanaScript, Set<String>> romajiByScript,
  ) {
    var romajiSlots = 0;
    for (final q in questions) {
      if (q.direction == QuizDirection.kanaRecall) continue;
      if (q.direction == QuizDirection.romajiToKana ||
          q.direction == QuizDirection.soundToKana) {
        for (final o in q.options) {
          if (q.direction == QuizDirection.romajiToKana) romajiSlots++;
          expect(
            allowedIds.contains(o),
            isTrue,
            reason: 'unlearned option $o on ${q.target.character}',
          );
        }
      } else {
        final allowed = romajiByScript[q.target.script] ?? const <String>{};
        for (final o in q.options) {
          expect(
            allowed.contains(o),
            isTrue,
            reason: 'unlearned romaji $o on ${q.target.character}',
          );
        }
      }
    }
    expect(romajiSlots, greaterThan(0), reason: 'need romaji→kana coverage');
  }

  test(
    'あ行 learned → か行 test: zero unlearned romaji→kana distractors',
    () async {
      final store = await storeWithAoLearned();
      final kaLesson = Lessons.fromKana(store.allKana)
          .firstWhere((l) => l.id == 'hira_row_1');
      final learned = learnedOther(store, kaLesson);
      final pool = StudySet.lessonTestPool(store, kaLesson);
      final allowedIds = pool.map((k) => k.id).toSet();
      final romajiByScript = <KanaScript, Set<String>>{};
      for (final k in pool) {
        romajiByScript.putIfAbsent(k.script, () => <String>{}).add(k.romaji);
      }

      final targets = Lessons.testTargets(kaLesson, learned, Random(1));
      final questions = const QuizEngine().generateSession(
        targets: targets,
        allKana: pool,
        length: targets.length,
        random: Random(1),
      );

      expect(questions, isNotEmpty);
      expectNoUnlearnedDistractors(questions, allowedIds, romajiByScript);
    },
  );

  test(
    'あ行 learned → か行 test: MCQs stay answerable with four options',
    () async {
      final store = await storeWithAoLearned();
      final kaLesson = Lessons.fromKana(store.allKana)
          .firstWhere((l) => l.id == 'hira_row_1');
      final learned = learnedOther(store, kaLesson);
      final targets = Lessons.testTargets(kaLesson, learned, Random(1));
      final pool = StudySet.lessonTestPool(store, kaLesson);

      final questions = const QuizEngine().generateSession(
        targets: targets,
        allKana: pool,
        length: targets.length,
        random: Random(1),
      );

      final mcq = questions.where(
        (q) =>
            q.direction == QuizDirection.romajiToKana ||
            q.direction == QuizDirection.kanaToRomaji,
      );
      expect(mcq, isNotEmpty);
      for (final q in mcq) {
        expect(q.options.length, 4);
        expect(q.options.toSet().length, 4);
        expect(q.correctIndex, inInclusiveRange(0, 3));
      }
    },
  );

  test('first row only: distractors stay inside the focus row', () async {
    final store = await KanaProgressRepository.load();
    final aoLesson = Lessons.fromKana(store.allKana).first;
    final pool = StudySet.lessonTestPool(store, aoLesson);
    final allowedIds = pool.map((k) => k.id).toSet();
    expect(allowedIds, {'あ', 'い', 'う', 'え', 'お'});

    final questions = const QuizEngine().generateSession(
      targets: Lessons.testTargets(aoLesson, const [], Random(3)),
      allKana: pool,
      length: 10,
      random: Random(3),
    );

    final romajiByScript = <KanaScript, Set<String>>{
      KanaScript.hiragana: pool.map((k) => k.romaji).toSet(),
    };
    expectNoUnlearnedDistractors(questions, allowedIds, romajiByScript);
  });
}
