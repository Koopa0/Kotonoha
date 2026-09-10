// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';

/// Lightweight prior-range check: the learner names rows they have met,
/// tries each kana without seeing the reading, then fills only the gaps.
///
/// This is not a second ability model. Daily direction evidence and
/// question selection stay on #50 / [DailySession]. This type never
/// writes listening or batch-fills a row from one answer.
class PlacementCheck {
  const PlacementCheck._();

  /// One [QuizDirection.kanaRecall] item per pending kana, in order.
  /// Unselected lessons never appear. No MCQ — a guess must not stand in
  /// for independent recall, speed, or listening.
  static List<QuizQuestion> questions(List<Kana> pending) => [
    for (final kana in pending)
      QuizQuestion(
        target: kana,
        direction: QuizDirection.kanaRecall,
        options: const [],
        correctIndex: 0,
      ),
  ];

  /// Opens a check for [selected]. Empty selection is refused — there is
  /// no one-tap "all fluent" path.
  static PlacementDraft? start(List<Lesson> selected) {
    if (selected.isEmpty) return null;
    final lessonIds = <String>[];
    final pending = <String>[];
    final seenLesson = <String>{};
    final seenKana = <String>{};
    for (final lesson in selected) {
      if (!seenLesson.add(lesson.id)) continue;
      lessonIds.add(lesson.id);
      for (final kana in lesson.kana) {
        if (seenKana.add(kana.id)) pending.add(kana.id);
      }
    }
    if (pending.isEmpty) return null;
    return PlacementDraft(
      lessonIds: lessonIds,
      pendingKanaIds: pending,
      records: const [],
    );
  }

  /// Resolves [pendingKanaIds] against [allKana]. Unknown ids are skipped
  /// — they are not replaced with fabricated targets.
  static List<Kana> pendingTargets(PlacementDraft draft, List<Kana> allKana) {
    final byId = {for (final kana in allKana) kana.id: kana};
    return [
      for (final id in draft.pendingKanaIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  static PlacementOutcome outcomeFor({
    required bool correct,
    required bool unprompted,
  }) {
    if (!correct) return PlacementOutcome.unknown;
    return unprompted
        ? PlacementOutcome.independent
        : PlacementOutcome.prompted;
  }

  /// Records one real grade. Unknown ids, already-graded ids, and ids not
  /// still pending are ignored — never filled in for the learner.
  static PlacementDraft record(
    PlacementDraft draft,
    String kanaId,
    PlacementOutcome outcome,
  ) {
    if (!draft.pendingKanaIds.contains(kanaId)) return draft;
    if (draft.records.any((r) => r.kanaId == kanaId)) return draft;
    return PlacementDraft(
      lessonIds: draft.lessonIds,
      pendingKanaIds: [
        for (final id in draft.pendingKanaIds)
          if (id != kanaId) id,
      ],
      records: [
        ...draft.records,
        PlacementRecord(kanaId: kanaId, outcome: outcome),
      ],
    );
  }

  /// Groups completed grades. Pending kana stay unanswered — they are not
  /// listed as known, prompted, or forgotten.
  ///
  /// A row is confirmed only when every kana in that row was independently
  /// recalled. One correct answer never graduates the rest of the row.
  static PlacementSummary summarize({
    required PlacementDraft draft,
    required List<Lesson> catalog,
  }) {
    final byId = <String, PlacementOutcome>{
      for (final record in draft.records) record.kanaId: record.outcome,
    };
    final catalogById = {for (final lesson in catalog) lesson.id: lesson};

    final independent = <Kana>[];
    final prompted = <Kana>[];
    final unknown = <Kana>[];
    final confirmedLessons = <Lesson>[];
    final gapLessons = <Lesson>[];

    for (final lessonId in draft.lessonIds) {
      final lesson = catalogById[lessonId];
      if (lesson == null || lesson.kana.isEmpty) continue;

      final gaps = <Kana>[];
      var allIndependent = true;
      for (final kana in lesson.kana) {
        final outcome = byId[kana.id];
        if (outcome == null) {
          allIndependent = false;
          continue;
        }
        switch (outcome) {
          case PlacementOutcome.independent:
            independent.add(kana);
          case PlacementOutcome.prompted:
            prompted.add(kana);
            gaps.add(kana);
            allIndependent = false;
          case PlacementOutcome.unknown:
            unknown.add(kana);
            gaps.add(kana);
            allIndependent = false;
        }
      }
      if (allIndependent) confirmedLessons.add(lesson);
      if (gaps.isNotEmpty) {
        gapLessons.add(Lesson(id: lesson.id, title: lesson.title, kana: gaps));
      }
    }

    return PlacementSummary(
      independent: independent,
      prompted: prompted,
      unknown: unknown,
      confirmedLessons: confirmedLessons,
      gapLessons: gapLessons,
    );
  }
}

/// Calm next-step facts from a check. No rank, XP, or degree.
class PlacementSummary {
  const PlacementSummary({
    required this.independent,
    required this.prompted,
    required this.unknown,
    required this.confirmedLessons,
    required this.gapLessons,
  });

  final List<Kana> independent;
  final List<Kana> prompted;
  final List<Kana> unknown;
  final List<Lesson> confirmedLessons;
  final List<Lesson> gapLessons;

  List<Kana> get gaps => [...prompted, ...unknown];

  bool get hasGaps => gapLessons.isNotEmpty;
}
