// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns the end-of-session decisions: whether a lesson test passed, the
/// one-time write that marks its row learned, and how the follow-up
/// sessions (retry the lesson, review the missed kana) are composed. The
/// screen renders the close and navigates.
///
/// Contract (the same one the widget state used to hold):
/// - A lesson's pass / not-yet gate is [Lessons.isPassed]; a plain review
///   has no gate.
/// - A passed lesson marks its row learned exactly once
///   ([applyLessonPass]); the app-scoped owner observes the write so a
///   failure survives even if the screen is popped before it settles.
///
/// Pure of timers, widgets and navigation.
class QuizResultViewModel extends ChangeNotifier {
  QuizResultViewModel({
    required this.result,
    required this.kana,
    required this.persistence,
    this.lesson,
    Random? rng,
  }) : _rng = rng ?? Random(),
       lessonPassed = lesson != null && Lessons.isPassed(lesson, result);

  final QuizResult result;

  /// Owner of the learned rows and the review pools.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future.
  final ProgressPersistenceController persistence;

  /// The lesson this session tested, `null` for a plain review.
  final Lesson? lesson;

  /// Whether the lesson test cleared its gate (always false without one).
  final bool lessonPassed;

  final Random _rng;
  bool _applied = false;

  bool get isLesson => lesson != null;
  List<Kana> get missed => result.missedKana;
  bool get isPerfect => missed.isEmpty;

  /// The learned-row write has been issued.
  bool get isApplied => _applied;

  /// Marks the passed lesson's row learned, once. A no-op on a plain
  /// review, a failed lesson, or a second call.
  void applyLessonPass() {
    if (!lessonPassed || _applied) return;
    _applied = true;
    persistence.trackKana(kana.markUnitLearned(lesson!.id));
    notifyListeners();
  }

  /// A fresh test over the failed lesson, drawn against the other learned
  /// rows of its script.
  List<QuizQuestion> composeRetry() {
    final target = lesson!;
    final learned = Lessons.fromKana(kana.allKana)
        .where(
          (l) =>
              l.id != target.id &&
              l.script == target.script &&
              kana.isUnitLearned(l.id),
        )
        .expand((l) => l.kana)
        .toList();
    return Lessons.composeTest(
      lesson: target,
      learnedOtherKana: learned,
      pool: StudySet.lessonTestPool(kana, target),
      random: _rng,
    );
  }

  /// One question per missed kana, distractors scoped to what is learned.
  List<QuizQuestion> composeMissedReview() {
    final targets = missed;
    return const QuizEngine().generateSession(
      targets: targets,
      // learned only; the engine scopes distractors per target script.
      allKana: StudySet.reviewPool(kana),
      length: targets.length,
      random: _rng,
    );
  }
}
