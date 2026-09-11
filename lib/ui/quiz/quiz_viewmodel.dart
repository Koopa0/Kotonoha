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
/// Visual timing starts on the first answerable presentation
/// ([noteAnswerablePresentation]), not merely construct / [advance]. A
/// question born while hidden stays unarmed until that frame. Once
/// presented, [noteUnanswerable] freezes the clock — resume must not
/// restart it. Flutter `inactive` can stay visible and paint; the view
/// reports [stillVisible] from an actual painted frame, not from the
/// previous lifecycle state.
///
/// Quiz `soundToKana` is kana-glyph ID, not listen-first sentence evidence —
/// that path lives on [ListeningScreen]. This type does not interpret
/// playback; the screen passes [persistProgress] so a failed, cancelled,
/// or stale play cannot become SRS. Presentation alone is not a hear;
/// fluency still waits on [noteListeningHeard].
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
  bool _presented = false;
  bool _recallCommitCaptured = false;
  int? _committedRecallLatencyMs;
  bool _listeningHeard = false;
  bool _listeningHeardArmed = false;

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
    _presented = false;
    _shownMonoMs = _nowMonoMs();
    _shownWallMs = _clock().millisecondsSinceEpoch;
  }

  /// First visible, answerable frame of a question that has never been
  /// presented. Starts monotonic RT from this instant. A later resume of
  /// an already-shown question is a no-op — thinking time cannot be
  /// washed (#19). `resumed` itself is not this call; the view must
  /// report a painted answerable frame.
  void noteAnswerablePresentation() {
    if (_finished || isAnswered) return;
    if (_presented) return;
    _presented = true;
    _timingValid = true;
    _shownMonoMs = _nowMonoMs();
    _shownWallMs = _clock().millisecondsSinceEpoch;
  }

  /// View reports the learner left an answerable state (pause / hide /
  /// inactive). Invalidates the current question's RT only; never records
  /// an answer and never auto-wrongs.
  ///
  /// [stillVisible] means a frame of this question was painted while
  /// Flutter was `inactive` (still on screen). Previous lifecycle
  /// states do not prove that. A hidden / paused birth stays
  /// unpresented so a later first answerable frame can start the clock.
  void noteUnanswerable({bool stillVisible = false}) {
    if (_finished || isAnswered) return;
    if (stillVisible) {
      _presented = true;
    }
    _timingValid = false;
  }

  /// Valid RT is monotonic foreground elapsed while the question stayed
  /// answerable. Interrupted, non-positive, or backward wall-clock deltas
  /// are untimed — correctness may still be stored, fluency may not.
  int? _latencyMs(DateTime now) {
    if (!_timingValid) return null;
    // soundToKana waits on the engine; show-time is not a recognition start.
    // Only a confirmed foreground hear arms fluency. No hear → no speed.
    if (current.direction == QuizDirection.soundToKana &&
        !_listeningHeardArmed) {
      return null;
    }
    final mono = _nowMonoMs() - _shownMonoMs;
    final wall = now.millisecondsSinceEpoch - _shownWallMs;
    if (mono <= 0 || wall < 0) return null;
    return mono;
  }

  /// First completed foreground play on a [QuizDirection.soundToKana] item.
  ///
  /// A valid hear is recorded even when the RT clock is already invalid
  /// (background interrupt, then a successful replay). Fluency re-arms
  /// only while timing is still valid. An already-invalid clock stays
  /// null — never a fabricated RT. Later replays do not move the start.
  void noteListeningHeard() {
    if (isAnswered || _finished) return;
    if (current.direction != QuizDirection.soundToKana) return;
    _listeningHeard = true;
    if (_listeningHeardArmed) return;
    if (!_timingValid) return;
    _listeningHeardArmed = true;
    _shownMonoMs = _nowMonoMs();
    _shownWallMs = _clock().millisecondsSinceEpoch;
  }

  /// Freeze foreground RT when the learner commits to an unprompted reading
  /// *before* the answer is revealed. Confirmation time after this must not
  /// enter fluency evidence. An already-invalid clock stays null — never a
  /// fabricated RT.
  void captureUnpromptedRecall() {
    if (isAnswered || _finished) return;
    if (current.direction != QuizDirection.kanaRecall) return;
    if (_recallCommitCaptured) return;
    _committedRecallLatencyMs = _latencyMs(_clock());
    _recallCommitCaptured = true;
  }

  /// Self-grades a [QuizDirection.kanaRecall] item after the reading has been
  /// revealed for confirmation. [unprompted] is true only when the learner
  /// committed to a reading *before* seeing it. A hinted correct is persisted
  /// as practice evidence and must not increment successful recalls or renew
  /// the schedule.
  void gradeRecall({required bool correct, required bool unprompted}) {
    if (isAnswered || _finished) return;
    if (current.direction != QuizDirection.kanaRecall) return;
    _record(
      selectedIndex: correct ? 0 : 1,
      correct: correct,
      forceUntimed: !unprompted || !correct,
      creditRecall: unprompted,
      extraMeta: {AttemptMeta.prompted: !unprompted},
    );
  }

  /// Records the user's choice for the current question and persists it.
  ///
  /// [persistProgress] is the screen's audio-evidence gate for
  /// [QuizDirection.soundToKana]. False skips repository writes so a
  /// failed / cancelled / stale play cannot become SRS. Forced-correct
  /// MCQ still writes nothing. [gradeRecall] is unchanged.
  void selectAnswer(
    int optionIndex, {
    bool persistProgress = true,
    Map<String, Object?> extraMeta = const {},
  }) {
    if (isAnswered || _finished) return;
    if (current.direction == QuizDirection.kanaRecall) return;
    _record(
      selectedIndex: optionIndex,
      correct: current.isCorrect(optionIndex),
      persistProgress: persistProgress,
      extraMeta: extraMeta,
    );
  }

  void _record({
    required int selectedIndex,
    required bool correct,
    bool forceUntimed = false,
    bool creditRecall = true,
    bool persistProgress = true,
    Map<String, Object?> extraMeta = const {},
  }) {
    final item = currentItem;
    final question = item.question;
    final now = _clock();
    final latencyMs = forceUntimed
        ? null
        : _recallCommitCaptured
        ? _committedRecallLatencyMs
        : _latencyMs(now);
    _selected = selectedIndex;
    _answers.add(
      AnsweredQuestion(question: question, selectedIndex: selectedIndex),
    );
    // Forced-correct MCQ can close the item in the session UI, but it is
    // not recall evidence. kanaRecall (empty options) is a different path
    // and still writes through gradeRecall / prompted practice below.
    if (!question.isForcedCorrect) {
      // Answering never waits on disk (the in-memory effect + notify below
      // are synchronous); the app-scoped owner observes the write so a
      // failure is surfaced instead of dropped.
      if (persistProgress) {
        // A sound item without a completed hear must not mint listening
        // evidence. persistProgress already blocks failed/cancelled play
        // from writing anything; this extra gate covers a scored glyph
        // pick that never actually heard the prompt.
        final listening =
            question.direction == QuizDirection.soundToKana && _listeningHeard;
        final persist = !correct
            ? repository.recordAnswer(
                question.target,
                correct: false,
                at: now,
                latencyMs: latencyMs,
                listening: listening,
              )
            : creditRecall
            ? repository.recordAnswer(
                question.target,
                correct: true,
                at: now,
                latencyMs: latencyMs,
                listening: listening,
              )
            : repository.recordPromptedPractice(question.target, at: now);
        persistence.trackKana(persist);
      }
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
            if (!correct &&
                selectedIndex >= 0 &&
                selectedIndex < question.options.length)
              AttemptMeta.distractor: question.options[selectedIndex],
            ...extraMeta,
          },
        ),
      );
    }
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
      _recallCommitCaptured = false;
      _committedRecallLatencyMs = null;
      _listeningHeard = false;
      _listeningHeardArmed = false;
      _armTiming();
    }
    notifyListeners();
  }
}
