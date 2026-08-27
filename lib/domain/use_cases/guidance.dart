// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';

/// Where the ambient "next step" line takes the learner when tapped.
enum GuidanceTarget {
  lessons,
  daily,

  /// Meet new words ear-first (渡し舟).
  ferry,

  /// Review due words cold (文字起こし).
  dictation,

  /// Read sentences — due ones first (黙読).
  sentences,

  /// Kanji readings — due reviews or new teach beats (漢字の声).
  kanji,
  rest,
}

/// A track's standing in the schedule, as plain data — the caller (the View,
/// which holds the repositories) summarises each track into one of these so
/// this use_case never has to import the kanji module or walk stat maps.
class TrackDue {
  const TrackDue({this.dueCount = 0, this.oldestDue, this.unmet = 0});

  static const TrackDue none = TrackDue();

  /// Items due for review now.
  final int dueCount;

  /// The earliest due instant among them (null when [dueCount] is 0).
  final DateTime? oldestDue;

  /// Readable items never met yet.
  final int unmet;
}

/// One calm "do this next" decision, derived from learning state.
///
/// A pure value object: it carries only the navigation [target] and — for the
/// review states — the [dueCount] the View needs to fill in its sentence. The
/// 繁中 copy itself lives in `AppStrings` (the UI layer), so this stays
/// Flutter-free.
class GuidanceStep {
  const GuidanceStep(this.target, {this.dueCount = 0});

  final GuidanceTarget target;

  /// Items due for review; only meaningful for the review targets ([daily] /
  /// [dictation] / [sentences] / [kanji]-review — 0 otherwise).
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
  /// First-match-wins over three eras:
  ///
  /// **The kana era** (unchanged — the foundation always speaks first):
  /// - **A** nothing learned yet → start the lessons (手解き).
  /// - **B** kana reviews are due → today's session (今日の稽古), with count.
  /// - **C** caught up but rows remain → keep learning (手解き).
  ///
  /// **The reading era** (the kana are quiet — route into the corpus):
  /// - **D** something is due in a reading track → the track whose oldest due
  ///   item has waited longest (cross-track fairness: no track can be starved
  ///   by another's endless novelty; ties break words → sentences → kanji).
  ///   Words review in 文字起こし, sentences in 黙読, readings in 漢字の声.
  /// - **E** nothing due anywhere but unmet material remains → meet it, in
  ///   curriculum order: new words (渡し舟), then new sentences (黙読), then
  ///   new kanji readings (漢字の声).
  ///
  /// - **F** everything met and nothing due → rest; the day is theirs.
  ///
  /// "Due" for kana reuses [StudySet.reviewPool] + [Scheduler] so it never
  /// diverges from what 今日の稽古 itself draws on; each reading track's
  /// standing arrives as a [TrackDue] summary computed by the caller from the
  /// same repositories its sessions draw on.
  static GuidanceStep nextStep(
    KanaProgressRepository store, {
    required DateTime now,
    TrackDue words = TrackDue.none,
    TrackDue sentences = TrackDue.none,
    TrackDue kanji = TrackDue.none,
  }) {
    // A — a brand-new learner: send them to be taught, before anything is due.
    if (store.learnedUnitCount == 0) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // B — kana reviews take priority over everything else.
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
    // D — the reading tracks: oldest-waiting due item wins.
    final candidates = [
      (GuidanceTarget.dictation, words),
      (GuidanceTarget.sentences, sentences),
      (GuidanceTarget.kanji, kanji),
    ].where((c) => c.$2.dueCount > 0 && c.$2.oldestDue != null).toList();
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => a.$2.oldestDue!.compareTo(b.$2.oldestDue!));
      final (target, track) = candidates.first;
      return GuidanceStep(target, dueCount: track.dueCount);
    }
    // E — nothing due: meet what is still unmet, in curriculum order.
    if (words.unmet > 0) return const GuidanceStep(GuidanceTarget.ferry);
    if (sentences.unmet > 0) {
      return const GuidanceStep(GuidanceTarget.sentences);
    }
    if (kanji.unmet > 0) return const GuidanceStep(GuidanceTarget.kanji);
    // F — everything met, nothing pending: the day is theirs.
    return const GuidanceStep(GuidanceTarget.rest);
  }
}
