// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';

/// The outcome of one answered question.
class AnsweredQuestion {
  const AnsweredQuestion({required this.question, required this.selectedIndex});

  final QuizQuestion question;
  final int selectedIndex;

  bool get wasCorrect => question.isCorrect(selectedIndex);
}

/// The result of a completed quiz session.
///
/// Pure data: no `package:flutter/*` imports.
class QuizResult {
  const QuizResult({required this.answers});

  final List<AnsweredQuestion> answers;

  int get total => answers.length;

  int get correctCount => answers.where((a) => a.wasCorrect).length;

  /// Distinct kana the user got wrong, in the order first missed.
  List<Kana> get missedKana {
    final seen = <String>{};
    final result = <Kana>[];
    for (final a in answers) {
      if (!a.wasCorrect && seen.add(a.question.target.id)) {
        result.add(a.question.target);
      }
    }
    return result;
  }
}
