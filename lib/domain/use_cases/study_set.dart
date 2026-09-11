// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';

/// Derives the *practice* kana sets from progress state — which kana the learner
/// has unlocked and what pool reviews should draw from.
///
/// This lives in the use-case layer (not the repository) so the data layer never
/// has to know about [Lessons]: derivation depends on the repo, never the other
/// way around.
class StudySet {
  const StudySet._();

  /// Kana from every learned lesson, across all scripts and kinds.
  static List<Kana> learned(KanaProgressRepository store) =>
      Lessons.fromKana(store.allKana)
          .where((l) => store.isUnitLearned(l.id))
          .expand((l) => l.kana)
          .toList();

  /// Targets/distractors for review-style practice: learned kana, falling back
  /// to あ行 only as a cold-start crash-safety (review entries are gated on
  /// learnedUnitCount in the UI, so this rarely matters).
  static List<Kana> reviewPool(KanaProgressRepository store) {
    final pool = learned(store);
    return pool.isNotEmpty
        ? pool
        : store.gojuonForScript(KanaScript.hiragana).take(5).toList();
  }

  /// Distractor pool for a lesson row test: learned kana in the same script,
  /// plus the focus row (not yet marked learned on the first attempt).
  static List<Kana> lessonTestPool(
    KanaProgressRepository store,
    Lesson lesson,
  ) {
    final byId = <String, Kana>{
      for (final k in learned(store))
        if (k.script == lesson.script) k.id: k,
      for (final k in lesson.kana) k.id: k,
    };
    return byId.values.toList();
  }
}
