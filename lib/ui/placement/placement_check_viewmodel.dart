// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';

/// Owns one answer-first placement check: the recoverable draft and its
/// every save, the reveal and whether it was an unprompted commit, what an
/// outcome counts as, and the underlying graded recall ([QuizViewModel],
/// #41/#43 RT rules, prompted vs. independent). The screen renders,
/// forwards taps and lifecycle visibility, and navigates to the results.
///
/// Draft contract (the same one the widget state used to hold):
/// - A reveal — hint or 「讀得出來」 — is persisted as exposure at once, so
///   leave / reload cannot restart a first unprompted round. A same-visit
///   commit stays independent; after reload the reveal is prompted-only.
/// - An outcome grades the recall, records the draft row and saves it.
/// - Every write is refused while a restore needs recovery or a previous
///   write has failed ([isBlocked]); the banner owns that state.
/// - An already-hinted kana (from the persisted draft) opens revealed and
///   prompted, never with a fresh unprompted commit.
///
/// Pure of timers, widgets and navigation.
class PlacementCheckViewModel extends ChangeNotifier {
  PlacementCheckViewModel({
    required PlacementDraft draft,
    required this.checks,
    required this.kana,
    required this.persistence,
    required this.recovery,
    required AnalyticsLog analytics,
    String? sessionId,
    DateTime Function()? clock,
    int Function()? monotonicMs,
  }) : _draft = draft,
       quiz = QuizViewModel(
         items: [
           for (final question in PlacementCheck.questions(
             PlacementCheck.pendingTargets(draft, kana.allKana),
           ))
             SessionItem(question: question, mode: PracticeMode.placementCheck),
         ],
         repository: kana,
         persistence: persistence,
         analytics: analytics,
         sessionId:
             sessionId ??
             'placement-${(clock ?? DateTime.now)().millisecondsSinceEpoch}',
         clock: clock,
         monotonicMs: monotonicMs,
       ) {
    quiz.addListener(_onQuizChanged);
    _syncHintedPresentation();
  }

  /// Owner of the recoverable draft.
  final PlacementCheckRepository checks;

  /// Owner of the per-kana schedule the recall grades into.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future and its failure state.
  final ProgressPersistenceController persistence;

  /// Blocks every write while a restore still needs recovery.
  final ProgressRestoreRecoveryController recovery;

  /// The graded recall this check is built on. The view reports lifecycle
  /// visibility to it through [noteAnswerablePresentation] and
  /// [noteUnanswerable].
  final QuizViewModel quiz;

  PlacementDraft _draft;
  bool _recallRevealed = false;
  bool _recallUnpromptedCommit = false;

  /// The draft as last saved from this check.
  PlacementDraft get draft => _draft;

  /// No pending target — the check opens straight onto its results.
  bool get isEmpty => quiz.items.isEmpty;
  bool get isFinished => quiz.isFinished;
  bool get isAnswered => quiz.isAnswered;
  int get index => quiz.index;
  int get total => quiz.total;
  bool get isLastQuestion => quiz.isLastQuestion;
  QuizQuestion get current => quiz.current;

  /// The reading is on screen (hint, commit, or a persisted reveal).
  bool get isRevealed => _recallRevealed;

  /// The reveal came from 「讀得出來」 in this visit — the only reveal that
  /// can still be graded as independent.
  bool get isUnpromptedCommit => _recallUnpromptedCommit;

  /// Writes are refused: a restore needs recovery or a save has failed.
  bool get isBlocked => persistence.hasWriteFailure || recovery.needsRecovery;

  bool get _currentHinted => !isEmpty && _draft.isHinted(current.target.id);

  void _syncHintedPresentation() {
    if (isEmpty || quiz.isAnswered) return;
    if (!_currentHinted) return;
    _recallRevealed = true;
    _recallUnpromptedCommit = false;
  }

  void _onQuizChanged() {
    if (!quiz.isAnswered) {
      _recallRevealed = false;
      _recallUnpromptedCommit = false;
      _syncHintedPresentation();
    }
    notifyListeners();
  }

  /// The view reports the item is on screen and answerable (foreground).
  void noteAnswerablePresentation() {
    if (isEmpty || quiz.isAnswered || quiz.isFinished) return;
    quiz.noteAnswerablePresentation();
  }

  /// The view reports the item cannot be answered (background / hidden);
  /// [stillVisible] when it is still on screen but inactive.
  void noteUnanswerable({bool stillVisible = false}) {
    if (isEmpty || quiz.isFinished) return;
    quiz.noteUnanswerable(stillVisible: stillVisible);
  }

  /// Shows the reading as a hint. Persists exposure; refused when blocked
  /// or once the reading is already on screen.
  void revealAsHint() {
    if (isEmpty || _recallRevealed || quiz.isAnswered || isBlocked) return;
    _persistReveal();
    _recallUnpromptedCommit = false;
    _recallRevealed = true;
    notifyListeners();
  }

  /// 「讀得出來」: captures the unprompted recall, then shows the reading.
  /// Persists exposure so leave / reload cannot restart a first unprompted
  /// round; the same-visit confirm still uses the commit flag. Refused once
  /// the reading is already on screen — a persisted hint cannot be turned
  /// into a commit.
  void revealAfterUnpromptedCommit() {
    if (isEmpty || _recallRevealed || quiz.isAnswered || isBlocked) return;
    quiz.captureUnpromptedRecall();
    _recallUnpromptedCommit = true;
    _recallRevealed = true;
    _persistReveal();
    notifyListeners();
  }

  /// Self-grades the revealed reading and records the draft row. Ignored
  /// before reveal, once answered, or while blocked.
  void noteOutcome({required bool correct}) {
    if (isEmpty || !_recallRevealed || quiz.isAnswered || quiz.isFinished) {
      return;
    }
    if (isBlocked) return;
    final kanaId = current.target.id;
    // Same-visit 讀得出來 commit stays independent even though the reading
    // is now persisted as exposure. After leave / reload the commit flag
    // is gone; a persisted reveal is prompted-only and must not start a
    // new unprompted RT.
    final independent = _recallUnpromptedCommit;
    quiz.gradeRecall(correct: correct, unprompted: independent);
    _draft = PlacementCheck.record(
      _draft,
      kanaId,
      PlacementCheck.outcomeFor(
        correct: correct,
        unprompted: independent,
        hinted: !independent && _draft.isHinted(kanaId),
      ),
    );
    persistence.trackPlacement(checks.save(_draft));
    notifyListeners();
  }

  /// 「不知道」: the reading is shown as a hint and the row is a miss.
  void markUnknown() {
    if (isEmpty || quiz.isAnswered || isBlocked) return;
    revealAsHint();
    noteOutcome(correct: false);
  }

  /// Leaves an answered item; refused while blocked.
  void advance() {
    if (isEmpty || !quiz.isAnswered || isBlocked) return;
    quiz.advance();
  }

  void _persistReveal() {
    _draft = PlacementCheck.noteHinted(_draft, current.target.id);
    persistence.trackPlacement(checks.save(_draft));
  }

  @override
  void dispose() {
    quiz
      ..removeListener(_onQuizChanged)
      ..dispose();
    super.dispose();
  }
}
