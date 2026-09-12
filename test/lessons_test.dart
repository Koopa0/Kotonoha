// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const all = kHiraganaGojuon;
  final lessons = Lessons.fromKana(all);
  final ao = lessons.first; // あ行

  QuizQuestion q(Kana t) => QuizQuestion(
    target: t,
    direction: QuizDirection.kanaToRomaji,
    options: [t.romaji, 'x', 'y', 'z'],
    correctIndex: 0,
  );

  QuizResult resultFor(
    Kana target, {
    required int correct,
    required int total,
  }) {
    return QuizResult(
      answers: [
        for (var i = 0; i < total; i++)
          AnsweredQuestion(
            question: q(target),
            selectedIndex: i < correct ? 0 : 1,
          ),
      ],
    );
  }

  group('Lessons.fromKana', () {
    test('produces one lesson per gojūon row (11)', () {
      expect(lessons.length, 11);
    });

    test('rows carry the right kana and titles', () {
      expect(ao.title, 'あ行');
      expect(ao.kana.length, 5);
      expect(ao.id, 'hira_row_0');
      expect(lessons.firstWhere((l) => l.title == 'や行').kana.length, 3);
      expect(lessons.firstWhere((l) => l.title == 'わ行').kana.length, 2);
      expect(lessons.last.title, 'ん');
      expect(lessons.last.kana.length, 1);
    });

    test('every kana appears in exactly one lesson', () {
      expect(lessons.fold<int>(0, (s, l) => s + l.kana.length), 46);
    });

    test('over all kana: hiragana seion ids unchanged, new kinds disjoint', () {
      final allLessons = Lessons.fromKana(kAllKana);
      expect(allLessons.length, 54); // 27 hiragana + 27 katakana
      expect(allLessons.first.id, 'hira_row_0'); // backward-compatible
      final ids = allLessons.map((l) => l.id).toSet();
      expect(ids.length, allLessons.length); // no duplicate ids
      expect(ids.contains('hira_dakuten_1'), isTrue); // が行
      expect(ids.contains('hira_handakuten_5'), isTrue); // ぱ行
      expect(ids.any((id) => id.startsWith('hira_yoon_')), isTrue);
      expect(ids.contains('kata_dakuten_1'), isTrue); // ガ行

      // が is NOT merged into か's hira_row_1 (the corruption guard).
      final ka = allLessons.firstWhere((l) => l.id == 'hira_row_1');
      expect(ka.kana.every((k) => k.kind == KanaKind.seion), isTrue);

      // yoon family groups 3 together.
      final kya = allLessons.firstWhere((l) => l.id == 'hira_yoon_き');
      expect(kya.kana.length, 3);
    });
  });

  group('Lessons.testTargets', () {
    test('focus row appears twice when there is no review pool', () {
      final t = Lessons.testTargets(ao, const [], Random(1));
      expect(t.length, 10); // 5 kana × 2
      for (final k in ao.kana) {
        expect(t.where((x) => x.id == k.id).length, 2);
      }
    });

    test('interleaves review kana from already-learned rows', () {
      final ka = lessons[1]; // か行
      final t = Lessons.testTargets(ao, ka.kana, Random(2));
      expect(t.length, 15); // 10 focus + 5 review
      final kaIds = ka.kana.map((k) => k.id).toSet();
      expect(t.any((x) => kaIds.contains(x.id)), isTrue);
    });
  });

  group('Lessons.composeTest', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ん singleton uses kanaRecall, not forced-correct MCQ', () async {
      final store = await KanaProgressRepository.load();
      final nLesson = Lessons.fromKana(kAllKana)
          .firstWhere((l) => l.id == 'hira_row_10');
      final questions = Lessons.composeTest(
        lesson: nLesson,
        learnedOtherKana: const [],
        pool: StudySet.lessonTestPool(store, nLesson),
        random: Random(1),
      );
      expect(questions, isNotEmpty);
      expect(
        questions.every((q) => q.direction == QuizDirection.kanaRecall),
        isTrue,
      );
      expect(questions.every((q) => !q.isForcedCorrect), isTrue);
    });
  });

  group('Lessons.isPassed', () {
    test('passes at or above 80% on the focus row', () {
      expect(
        Lessons.isPassed(ao, resultFor(ao.kana.first, correct: 8, total: 10)),
        isTrue,
      );
    });

    test('fails below 80%', () {
      expect(
        Lessons.isPassed(ao, resultFor(ao.kana.first, correct: 7, total: 10)),
        isFalse,
      );
    });

    test('only the focus row counts — interleaved review is ignored', () {
      final ka = lessons[1].kana.first; // か行,out of あ行 scope
      final mixed = QuizResult(
        answers: [
          for (var i = 0; i < 5; i++)
            AnsweredQuestion(
              question: q(ao.kana.first),
              selectedIndex: 0,
            ), // あ ✓
          for (var i = 0; i < 5; i++)
            AnsweredQuestion(
              question: q(ka),
              selectedIndex: 1,
            ), // か ✗ (ignored)
        ],
      );
      expect(Lessons.isPassed(ao, mixed), isTrue);
    });

    test('a result with no in-scope answers never passes', () {
      final ka = lessons[1].kana.first;
      expect(
        Lessons.isPassed(ao, resultFor(ka, correct: 10, total: 10)),
        isFalse,
      );
    });
  });
}
