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
///
/// Timing starts when the question becomes current (construct / [advance]).
/// For listening items that is still *before* [QuizScreen]'s first-frame TTS
/// callback — "prompt available" vs engine delay is coordinated with
/// listening/#9. This type does not rework audio.
class QuizViewModel extends ChangeNotifier {
  QuizViewModel({
    required this.items,
    required this.repository,
    required this.persistence,
    this.analytics,
    this.sessionId = '',
    DateTime Function()? clock,
    this._monotonicMs,
  }) : _clock = clock ?? DateTime.now {
    _stopwatch = Stopwatch()..start();
    _armTiming();
  }

  final List<SessionItem> items;
  final KanaProgressRepository repository;
  final ProgressPersistenceController persistence;
  final AnalyticsLog? analytics;
  final String sessionId;
  final DateTime Function() _clock;
  final int Function()? _monotonicMs;

  late final Stopwatch _stopwatch;
  late int _shownMonoMs;
  late int _shownWallMs;
  bool _timingValid = true;

  final List<AnsweredQuestion> _answers = [];
  int _index = 0;
  int? _selected;
  bool _finished = false;

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

  int _nowMonoMs() => _monotonicMs?.call() ?? _stopwatch.elapsedMilliseconds;

  void _armTiming() {
    _timingValid = true;
    _shownMonoMs = _nowMonoMs();
    _shownWallMs = _clock().millisecondsSinceEpoch;
  }

  /// View reports the learner left an answerable state (pause / hide /
  /// inactive). Invalidates the current question's RT only; never records
  /// an answer and never auto-wrongs.
  void noteUnanswerable() {
    if (_finished || isAnswered) return;
    _timingValid = false;
  }

  /// Valid RT is monotonic foreground elapsed while the question stayed
  /// answerable. Interrupted, non-positive, or backward wall-clock deltas
  /// are untimed — correctness may still be stored, fluency may not.
  int? _latencyMs(DateTime now) {
    if (!_timingValid) return null;
    final mono = _nowMonoMs() - _shownMonoMs;
    final wall = now.millisecondsSinceEpoch - _shownWallMs;
    if (mono <= 0 || wall < 0) return null;
    return mono;
  }

  /// Records the user's choice for the current question and persists it.
  void selectAnswer(int optionIndex) {
    if (isAnswered || _finished) return;
    final item = currentItem;
    final question = item.question;
    final correct = question.isCorrect(optionIndex);
    final now = _clock();
    final latencyMs = _latencyMs(now);
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
        latencyMs: latencyMs,
      ),
    );
    analytics?.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: question.target.id,
        mode: item.mode.name,
        correct: correct,
        // 0 = untimed (see [Attempt.rtMs]), not a claimed 0ms reflex.
        rtMs: latencyMs ?? 0,
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
      _armTiming();
    }
    notifyListeners();
  }
}
