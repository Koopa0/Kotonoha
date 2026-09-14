// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';

/// Where a resumed draft leads.
enum PlacementResume {
  /// The draft still has pending kana — reopen the check.
  check,

  /// Every kana is graded — reopen the results.
  results,
}

/// Owns the placement scope step: the rows the learner names, the catalog
/// they are drawn from, the recoverable draft's start / resume / discard,
/// and whether writes are allowed at all. The screen renders the list and
/// navigates on the outcome of each command.
///
/// Draft contract (the same one the widget state used to hold):
/// - A new check is opened only once its draft is on disk: a failed save
///   keeps the learner here to resume after retry, never silently.
/// - Resume leads to the check while kana are pending and to the results
///   once every kana is graded; a draft with no progress resumes nowhere.
/// - Discard clears the draft and stays; a failed clear is the banner's
///   (in memory the draft is already empty and retry flushes it).
/// - Every write is refused while a restore needs recovery or a previous
///   write has failed ([isBlocked]).
///
/// Re-notifies on any change to the kana store, the draft, or the write /
/// recovery state, so the view can render from this type alone.
class PlacementScopeViewModel extends ChangeNotifier {
  PlacementScopeViewModel({
    required this.kana,
    required this.checks,
    required this.persistence,
    required this.recovery,
  }) {
    kana.addListener(notifyListeners);
    checks.addListener(notifyListeners);
    persistence.addListener(notifyListeners);
    recovery.addListener(notifyListeners);
  }

  /// Owner of the learned rows and the kana catalog.
  final KanaProgressRepository kana;

  /// Owner of the recoverable draft.
  final PlacementCheckRepository checks;

  /// App-scoped owner of every write's future and its failure state.
  final ProgressPersistenceController persistence;

  /// Blocks every write while a restore still needs recovery.
  final ProgressRestoreRecoveryController recovery;

  final Set<String> _selected = {};
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// Every row, in catalog order.
  List<Lesson> get catalog => Lessons.fromKana(kana.allKana);
  List<Lesson> get hiragana =>
      catalog.where((l) => l.script == KanaScript.hiragana).toList();
  List<Lesson> get katakana =>
      catalog.where((l) => l.script == KanaScript.katakana).toList();

  /// The draft as the repository holds it right now.
  PlacementDraft get draft => checks.draft;

  /// Writes are refused: a restore needs recovery or a save has failed.
  bool get isBlocked => persistence.hasWriteFailure || recovery.needsRecovery;

  /// A draft with progress can be resumed or discarded.
  bool get canResume => draft.hasProgress;

  /// The resumable draft is fully graded (results, not the check).
  bool get isResumeFinished => draft.isComplete;

  /// At least one row is named and writes are allowed.
  bool get canStart => _selected.isNotEmpty && !isBlocked;

  bool isSelected(String lessonId) => _selected.contains(lessonId);
  bool isUnitLearned(String lessonId) => kana.isUnitLearned(lessonId);

  /// Names or un-names one row.
  void setSelected(String lessonId, {required bool selected}) {
    final changed = selected
        ? _selected.add(lessonId)
        : _selected.remove(lessonId);
    if (changed) notifyListeners();
  }

  /// Starts a check over the named rows. Resolves to the saved draft once it
  /// is on disk, or `null` when blocked, nothing is named, or the save
  /// failed (the banner owns that failure; the learner resumes after retry).
  Future<PlacementDraft?> startNew() async {
    if (isBlocked) return null;
    final selected = [
      for (final lesson in catalog)
        if (_selected.contains(lesson.id)) lesson,
    ];
    final draft = PlacementCheck.start(selected);
    if (draft == null) return null;
    final save = checks.save(draft);
    persistence.trackPlacement(save);
    try {
      await save;
    } catch (_) {
      // Do not open a check whose draft is not on disk — resume from this
      // screen after retry, never silently.
      if (!_disposed) notifyListeners();
      return null;
    }
    if (_disposed) return null;
    return draft;
  }

  /// Where the resumable draft leads, or `null` when blocked or there is
  /// nothing to resume.
  PlacementResume? resume() {
    if (isBlocked) return null;
    final current = draft;
    if (!current.hasProgress) return null;
    if (current.isComplete) return PlacementResume.results;
    if (current.isInProgress) return PlacementResume.check;
    return null;
  }

  /// Clears the draft and stays. A failed clear leaves the in-memory draft
  /// empty for retry to flush.
  Future<void> discardAndStay() async {
    if (isBlocked) return;
    final clear = checks.clear();
    persistence.trackPlacement(clear);
    try {
      await clear;
    } catch (_) {
      // In-memory is empty; retry flushes that empty draft. Stay put.
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    kana.removeListener(notifyListeners);
    checks.removeListener(notifyListeners);
    persistence.removeListener(notifyListeners);
    recovery.removeListener(notifyListeners);
    super.dispose();
  }
}
