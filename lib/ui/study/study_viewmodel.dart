// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';

/// The two passes of 手解き.
enum StudyPhase {
  /// An honest ENCODE: every glyph shown with its romaji and audio — you
  /// cannot recall a kana you have never met.
  encode,

  /// An optional, self-paced RECAP: glyph only, romaji behind a tap, so the
  /// row test is no longer the first time the learner retrieves anything.
  /// Never graded or scored.
  recap,
}

/// Owns one lesson's 手解き: the pass, the card in view, whether a recap
/// card's romaji is revealed, and how the row test is composed against the
/// other learned rows. The screen pages, speaks, renders and navigates.
///
/// Nothing here writes progress: meeting a kana is not evidence, and the
/// row test that follows is the only graded step.
class StudyViewModel extends ChangeNotifier {
  StudyViewModel({required this.lesson, required this.kana, Random? rng})
    : _rng = rng ?? Random();

  final Lesson lesson;

  /// Owner of the learned rows the test interleaves with.
  final KanaProgressRepository kana;

  final Random _rng;

  StudyPhase _phase = StudyPhase.encode;
  int _index = 0;
  bool _revealed = false;

  List<Kana> get cards => lesson.kana;
  StudyPhase get phase => _phase;
  bool get isRecap => _phase == StudyPhase.recap;
  int get index => _index;
  Kana get current => cards[_index];
  bool get isLast => _index >= cards.length - 1;

  /// Recap only: the current card's romaji is on screen.
  bool get isRevealed => _revealed;

  /// The learner is on the last encode card: test now, or recap first.
  bool get offersRecap => _phase == StudyPhase.encode && isLast;

  /// The pager settled on card [i]; a fresh card hides its romaji again.
  void showCard(int i) {
    if (i == _index && !_revealed) return;
    _index = i;
    _revealed = false;
    notifyListeners();
  }

  /// Enters the recall lap from the top of the same row. Reachable only
  /// from the last encode card, so every recap glyph has been met.
  void enterRecap() {
    if (!offersRecap) return;
    _phase = StudyPhase.recap;
    _index = 0;
    _revealed = false;
    notifyListeners();
  }

  /// Confirms a recap card by showing its romaji. Ignored on an encode card.
  void reveal() {
    if (!isRecap || _revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// The row test: this lesson's kana interleaved with the other learned
  /// rows of its script, distractors drawn from the lesson-test pool.
  List<QuizQuestion> composeTest() => Lessons.composeTest(
    lesson: lesson,
    learnedOtherKana: _learnedOtherKana,
    pool: StudySet.lessonTestPool(kana, lesson),
    random: _rng,
  );

  /// Kana from previously-learned rows of the same script, excluding this
  /// one, for interleaving.
  List<Kana> get _learnedOtherKana => Lessons.fromKana(kana.allKana)
      .where(
        (l) =>
            l.id != lesson.id &&
            l.script == lesson.script &&
            kana.isUnitLearned(l.id),
      )
      .expand((l) => l.kana)
      .toList();
}
