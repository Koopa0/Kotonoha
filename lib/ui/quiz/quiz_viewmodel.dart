// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';

/// Owns the state and logic of one session: the cursor, the selected answer,
/// scoring, persistence, and analytics. Mode is per-item (so an adaptive
/// session can mix MC / listening). Pure of timers and navigation.
class QuizViewModel extends ChangeNotifier {
  QuizViewModel({
    required this.items,
    required this.repository,
    required this.persistence,
    this.analytics,
    this.sessionId = '',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _shownAtMs = _clock().millisecondsSinceEpoch;
  }

  final List<SessionItem> items;
  final KanaProgressRepository repository;
  final ProgressPersistenceController persistence;
  final AnalyticsLog? analytics;
  final String sessionId;
  final DateTime Function() _clock;

  final List<AnsweredQuestion> _answers = [];
  int _index = 0;
  int? _selected;
  bool _finished = false;
  late int _shownAtMs; // when the current question was shown (latency)

  int get index => _index;
  int get total => items.length;
  SessionItem get currentItem => items[_index];
  QuizQuestion get current => currentItem.question;

  bool get isAnswered => _selected != null;
  bool get isFinished => _finished;
  bool get isLastQuestion => _index + 1 >= total;

  /// Whether the just-selected answer was correct (null before answering).
  bool? get lastWasCorrect => isAnswered ? current.isCorrect(_selected!) : null;

  double get progress =>
      total == 0 ? 0 : (_index + (isAnswered ? 1 : 0)) / total;

  QuizResult get result => QuizResult(answers: List.unmodifiable(_answers));

  OptionState optionState(int optionIndex) {
    if (!isAnswered) return OptionState.idle;
    if (optionIndex == current.correctIndex) {
      return optionIndex == _selected
          ? OptionState.correct
          : OptionState.revealed;
    }
    if (optionIndex == _selected) return OptionState.wrong;
    return OptionState.dimmed;
  }

  /// Records the user's choice for the current question and persists it.
  void selectAnswer(int optionIndex) {
    if (isAnswered || _finished) return;
    final item = currentItem;
    final question = item.question;
    final correct = question.isCorrect(optionIndex);
    final now = _clock();
    _selected = optionIndex;
    _answers.add(
      AnsweredQuestion(question: question, selectedIndex: optionIndex),
    );
    // Answering never waits on disk (the in-memory effect + notify below are
    // synchronous); the app-scoped owner observes the write so a failure is
    // surfaced instead of dropped.
    persistence.trackKana(
      repository.recordAnswer(
        question.target,
        correct: correct,
        at: now,
        latencyMs: now.millisecondsSinceEpoch - _shownAtMs,
      ),
    );
    analytics?.record(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: question.target.id,
        mode: item.mode.name,
        correct: correct,
        rtMs: now.millisecondsSinceEpoch - _shownAtMs,
        sessionId: sessionId,
        meta: {
          AttemptMeta.direction: question.direction.name,
          if (!correct) AttemptMeta.distractor: question.options[optionIndex],
        },
      ),
    );
    notifyListeners();
  }

  /// Moves to the next question, or marks the session finished.
  void advance() {
    if (!isAnswered || _finished) return;
    if (isLastQuestion) {
      _finished = true;
    } else {
      _index += 1;
      _selected = null;
      _shownAtMs = _clock().millisecondsSinceEpoch;
    }
    notifyListeners();
  }
}
