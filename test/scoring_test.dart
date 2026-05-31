// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';

void main() {
  const all = kHiraganaGojuon;

  QuizQuestion q(String character) {
    final target = all.firstWhere((k) => k.character == character);
    return QuizQuestion(
      target: target,
      direction: QuizDirection.kanaToRomaji,
      options: [target.romaji, 'xx', 'yy', 'zz'],
      correctIndex: 0,
    );
  }

  group('QuizResult scoring', () {
    test('counts correct answers and total', () {
      final result = QuizResult(
        answers: [
          AnsweredQuestion(question: q('あ'), selectedIndex: 0), // correct
          AnsweredQuestion(question: q('い'), selectedIndex: 1), // wrong
          AnsweredQuestion(question: q('う'), selectedIndex: 0), // correct
        ],
      );
      expect(result.total, 3);
      expect(result.correctCount, 2);
      expect(result.scoreFraction, closeTo(2 / 3, 1e-9));
    });

    test('missedKana lists distinct wrong kana in order', () {
      final result = QuizResult(
        answers: [
          AnsweredQuestion(question: q('か'), selectedIndex: 2), // wrong
          AnsweredQuestion(question: q('き'), selectedIndex: 0), // correct
          AnsweredQuestion(question: q('か'), selectedIndex: 3), // wrong again
          AnsweredQuestion(question: q('く'), selectedIndex: 1), // wrong
        ],
      );
      expect(result.missedKana.map((k) => k.character).toList(), ['か', 'く']);
    });

    test('a perfect session has no missed kana', () {
      final result = QuizResult(
        answers: [
          AnsweredQuestion(question: q('さ'), selectedIndex: 0),
          AnsweredQuestion(question: q('し'), selectedIndex: 0),
        ],
      );
      expect(result.correctCount, 2);
      expect(result.missedKana, isEmpty);
    });

    test('empty result is safe', () {
      const result = QuizResult(answers: []);
      expect(result.total, 0);
      expect(result.scoreFraction, 0);
      expect(result.missedKana, isEmpty);
    });
  });
}
