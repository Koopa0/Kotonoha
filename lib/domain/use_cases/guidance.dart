// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';

/// Where the ambient "next step" line takes the learner when tapped.
enum GuidanceTarget { lessons, daily, rest }

/// One calm "do this next" decision, derived from learning state.
///
/// A pure value object: it carries only the navigation [target] and — for the
/// review state — the [dueCount] the View needs to fill in its sentence. The
/// 繁中 copy itself lives in `AppStrings` (the UI layer), so this stays
/// Flutter-free.
class GuidanceStep {
  const GuidanceStep(this.target, {this.dueCount = 0});

  final GuidanceTarget target;

  /// Kana due for review; only meaningful when [target] is
  /// [GuidanceTarget.daily] (0 otherwise).
  final int dueCount;

  @override
  bool operator ==(Object other) =>
      other is GuidanceStep &&
      other.target == target &&
      other.dueCount == dueCount;

  @override
  int get hashCode => Object.hash(target, dueCount);
}

/// Reads learning state and answers one question: what should the learner do
/// next? One quiet step at a time — never a map or a checklist. Pure logic,
/// deterministic under an injected [now].
abstract final class Guidance {
  /// First-match-wins over four states:
  ///
  /// - **A** nothing learned yet → start the lessons (手解き).
  /// - **B** reviews are due → today's session (今日の稽古), carrying the count.
  /// - **C** caught up but rows remain → keep learning (手解き).
  /// - **D** every row learned and nothing due → rest; pick freely.
  ///
  /// "Due" reuses [StudySet.reviewPool] + [Scheduler] so it never diverges from
  /// what 今日の稽古 itself draws on.
  static GuidanceStep nextStep(
    KanaProgressRepository store, {
    required DateTime now,
  }) {
    // A — a brand-new learner: send them to be taught, before anything is due.
    if (store.learnedUnitCount == 0) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // B — reviews take priority over new material.
    final due = Scheduler.dueCount(
      StudySet.reviewPool(store),
      store.stats,
      now: now,
    );
    if (due > 0) {
      return GuidanceStep(GuidanceTarget.daily, dueCount: due);
    }
    // C — caught up, but there is still a row left to learn.
    final hasUnlearned = Lessons.fromKana(
      store.allKana,
    ).any((l) => !store.isUnitLearned(l.id));
    if (hasUnlearned) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // D — everything learned, nothing pending: the day is theirs.
    return const GuidanceStep(GuidanceTarget.rest);
  }
}
