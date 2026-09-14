// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';

/// Owns the placement results step: the graded summary, applying the
/// confirmed rows as learned, clearing the draft once they are on disk,
/// and waiting out a blocked or failed write to finish the pair. The
/// screen lists the summary and navigates.
///
/// Apply contract (the same one the widget state used to hold):
/// - Confirmed rows are persisted on disk first, then the draft is cleared.
///   Memory success is not enough — a failed `learned_units_v1` write must
///   keep the recoverable draft so cold start can resume the results
///   instead of leaving "draft empty / row unlearned".
/// - While a restore needs recovery, or after a failed row write, the
///   apply waits on the persistence and recovery owners and resumes once
///   both are clear and idle. It never runs twice: once the draft clear is
///   issued the pair is done.
///
/// Re-notifies on any change to the kana store so the daily-readiness
/// offer stays live. Pure of timers, widgets and navigation.
class PlacementResultViewModel extends ChangeNotifier {
  PlacementResultViewModel({
    required this.draft,
    required this.checks,
    required this.kana,
    required this.persistence,
    required this.recovery,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       summary = PlacementCheck.summarize(
         draft: draft,
         catalog: Lessons.fromKana(kana.allKana),
       ) {
    kana.addListener(notifyListeners);
  }

  /// The finished check.
  final PlacementDraft draft;

  /// Owner of the recoverable draft, cleared once the rows are on disk.
  final PlacementCheckRepository checks;

  /// Owner of the learned rows.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future and its failure state.
  final ProgressPersistenceController persistence;

  /// Blocks the apply while a restore still needs recovery.
  final ProgressRestoreRecoveryController recovery;

  /// How each kana was graded, and which rows that confirms or leaves open.
  final PlacementSummary summary;

  final DateTime Function() _clock;

  bool _disposed = false;
  bool _applying = false;
  bool _draftClearIssued = false;
  bool _awaitingRetry = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// The recoverable draft still belongs to this results visit — not a later
  /// check the learner opened after leaving.
  bool _stillOwnsDraft() {
    final current = checks.draft;
    if (!draft.isComplete || !current.isComplete) return false;
    if (current.lessonIds.length != draft.lessonIds.length) return false;
    for (var i = 0; i < draft.lessonIds.length; i++) {
      if (current.lessonIds[i] != draft.lessonIds[i]) return false;
    }
    if (current.records.length != draft.records.length) return false;
    for (var i = 0; i < draft.records.length; i++) {
      final expected = draft.records[i];
      final actual = current.records[i];
      if (expected.kanaId != actual.kanaId ||
          expected.outcome != actual.outcome) {
        return false;
      }
    }
    return true;
  }

  /// The confirmed rows are on disk and the draft clear has been issued.
  bool get isApplied => _draftClearIssued;

  /// The apply is parked on a blocked or failed write, waiting for retry.
  bool get isAwaitingRetry => _awaitingRetry;

  /// Whether a daily session can be composed from what is learned now.
  bool get isDailyReady => DailySession.isReady(
    StudySet.learned(kana),
    stats: kana.stats,
    now: _clock(),
  );

  /// The row a 「補上」 tap opens first.
  Lesson? get firstGap =>
      summary.gapLessons.isEmpty ? null : summary.gapLessons.first;

  /// Persists the confirmed rows, then clears the draft. Safe to call again:
  /// a running or finished apply is a no-op, and a blocked one parks itself
  /// until the owners clear.
  Future<void> applyConfirmed() async {
    if (_disposed || _applying || _draftClearIssued) return;
    if (recovery.needsRecovery) {
      _awaitRetry();
      return;
    }
    _applying = true;
    try {
      for (final lesson in summary.confirmedLessons) {
        final save = kana.markUnitLearned(lesson.id);
        persistence.trackKana(save);
        await save;
      }
      if (_disposed || !_stillOwnsDraft()) return;
      _draftClearIssued = true;
      persistence.trackPlacement(checks.clear());
      notifyListeners();
    } catch (_) {
      // Banner already tracks the kana failure. Keep the draft so retry
      // or a later results visit can finish the pair.
      if (!_disposed) _awaitRetry();
    } finally {
      _applying = false;
    }
  }

  void _awaitRetry() {
    if (_disposed || _awaitingRetry) return;
    _awaitingRetry = true;
    persistence.addListener(_onOwnersChanged);
    recovery.addListener(_onOwnersChanged);
    notifyListeners();
  }

  void _onOwnersChanged() {
    if (_disposed || !_awaitingRetry || _applying || _draftClearIssued) return;
    if (persistence.hasWriteFailure || persistence.isRetrying) return;
    if (recovery.needsRecovery || recovery.isRetrying) return;
    _stopAwaitingRetry();
    applyConfirmed();
  }

  void _stopAwaitingRetry() {
    if (!_awaitingRetry) return;
    _awaitingRetry = false;
    persistence.removeListener(_onOwnersChanged);
    recovery.removeListener(_onOwnersChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAwaitingRetry();
    kana.removeListener(notifyListeners);
    super.dispose();
  }
}
