// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';

void main() {
  final catalog = Lessons.fromKana(kAllKana);
  final ao = catalog.firstWhere((l) => l.id == 'hira_row_0');
  final ka = catalog.firstWhere((l) => l.id == 'hira_row_1');
  final sa = catalog.firstWhere((l) => l.id == 'hira_row_2');

  group('PlacementCheck.start', () {
    test('refuses an empty selection — no one-tap all-fluent', () {
      expect(PlacementCheck.start(const []), isNull);
    });

    test('queues every kana in the selected rows, none from the rest', () {
      final draft = PlacementCheck.start([ao, ka])!;
      expect(draft.lessonIds, ['hira_row_0', 'hira_row_1']);
      expect(draft.pendingKanaIds, [
        ...ao.kana.map((k) => k.id),
        ...ka.kana.map((k) => k.id),
      ]);
      expect(draft.pendingKanaIds, isNot(contains(sa.kana.first.id)));
      expect(draft.records, isEmpty);
    });
  });

  group('PlacementCheck.questions', () {
    test('is kanaRecall only — no MCQ to guess a row fluent', () {
      final questions = PlacementCheck.questions(ao.kana);
      expect(questions.length, ao.kana.length);
      for (final q in questions) {
        expect(q.direction, QuizDirection.kanaRecall);
        expect(q.options, isEmpty);
      }
    });
  });

  group('PlacementCheck.record', () {
    test('keeps unanswered kana unanswered — never invents the rest', () {
      final started = PlacementCheck.start([ao])!;
      final after = PlacementCheck.record(
        started,
        ao.kana.first.id,
        PlacementOutcome.independent,
      );
      expect(after.records, hasLength(1));
      expect(after.records.single.kanaId, ao.kana.first.id);
      expect(after.pendingKanaIds, ao.kana.skip(1).map((k) => k.id));
    });

    test('ignores ids that are not pending', () {
      final started = PlacementCheck.start([ao])!;
      final after = PlacementCheck.record(
        started,
        ka.kana.first.id,
        PlacementOutcome.independent,
      );
      expect(after.records, isEmpty);
      expect(after.pendingKanaIds, started.pendingKanaIds);
    });
  });

  group('PlacementCheck.summarize', () {
    test('one independent answer does not confirm the rest of the row', () {
      var draft = PlacementCheck.start([ao])!;
      draft = PlacementCheck.record(
        draft,
        ao.kana.first.id,
        PlacementOutcome.independent,
      );
      final summary = PlacementCheck.summarize(draft: draft, catalog: catalog);
      expect(summary.confirmedLessons, isEmpty);
      expect(summary.independent, [ao.kana.first]);
      expect(summary.gapLessons, isEmpty);
    });

    test('a row is confirmed only when every kana was independent', () {
      var draft = PlacementCheck.start([ao])!;
      for (final kana in ao.kana) {
        draft = PlacementCheck.record(
          draft,
          kana.id,
          PlacementOutcome.independent,
        );
      }
      final summary = PlacementCheck.summarize(draft: draft, catalog: catalog);
      expect(summary.confirmedLessons.map((l) => l.id), ['hira_row_0']);
      expect(summary.hasGaps, isFalse);
    });

    test('prompted-correct is not independent and becomes a gap', () {
      var draft = PlacementCheck.start([ao])!;
      draft = PlacementCheck.record(draft, 'あ', PlacementOutcome.independent);
      draft = PlacementCheck.record(draft, 'い', PlacementOutcome.prompted);
      draft = PlacementCheck.record(draft, 'う', PlacementOutcome.unknown);
      final summary = PlacementCheck.summarize(draft: draft, catalog: catalog);
      expect(summary.confirmedLessons, isEmpty);
      expect(summary.independent.map((k) => k.character), ['あ']);
      expect(summary.prompted.map((k) => k.character), ['い']);
      expect(summary.unknown.map((k) => k.character), ['う']);
      expect(summary.gapLessons, hasLength(1));
      expect(summary.gapLessons.single.id, 'hira_row_0');
      expect(summary.gapLessons.single.kana.map((k) => k.character), [
        'い',
        'う',
      ]);
    });

    test('unselected rows never appear in the summary', () {
      var draft = PlacementCheck.start([ao])!;
      for (final kana in ao.kana) {
        draft = PlacementCheck.record(
          draft,
          kana.id,
          PlacementOutcome.independent,
        );
      }
      final summary = PlacementCheck.summarize(draft: draft, catalog: catalog);
      expect(summary.confirmedLessons.map((l) => l.id), ['hira_row_0']);
      expect(
        summary.independent.map((k) => k.character),
        isNot(contains(ka.kana.first.character)),
      );
    });

    test('pending kana are omitted — not graded as known or forgotten', () {
      var draft = PlacementCheck.start([ao])!;
      draft = PlacementCheck.record(draft, 'あ', PlacementOutcome.unknown);
      final summary = PlacementCheck.summarize(draft: draft, catalog: catalog);
      expect(summary.unknown.map((k) => k.character), ['あ']);
      expect(summary.independent, isEmpty);
      expect(summary.prompted, isEmpty);
      expect(summary.gapLessons.single.kana.map((k) => k.character), ['あ']);
    });
  });

  group('PlacementDraft.fromJson', () {
    test('pending wins over a recorded id — unanswered is not invented', () {
      final draft = PlacementDraft.fromJson({
        'lessons': ['hira_row_0'],
        'pending': ['あ'],
        'records': [
          {'id': 'あ', 'out': 'independent'},
        ],
      });
      expect(draft.pendingKanaIds, ['あ']);
      expect(draft.records, isEmpty);
    });

    test('drops a corrupt record instead of inventing an outcome', () {
      final draft = PlacementDraft.fromJson({
        'lessons': ['hira_row_0'],
        'pending': ['い'],
        'records': [
          {'id': 'あ'},
          {'id': 'う', 'out': 'fluent'},
          {'id': 'え', 'out': 'unknown'},
        ],
      });
      expect(draft.pendingKanaIds, ['い']);
      expect(draft.records, hasLength(1));
      expect(draft.records.single.kanaId, 'え');
      expect(draft.records.single.outcome, PlacementOutcome.unknown);
    });
  });

  test('outcomeFor splits independent, prompted, and unknown', () {
    expect(
      PlacementCheck.outcomeFor(correct: true, unprompted: true),
      PlacementOutcome.independent,
    );
    expect(
      PlacementCheck.outcomeFor(correct: true, unprompted: false),
      PlacementOutcome.prompted,
    );
    expect(
      PlacementCheck.outcomeFor(correct: false, unprompted: true),
      PlacementOutcome.unknown,
    );
    expect(
      PlacementCheck.outcomeFor(correct: false, unprompted: false),
      PlacementOutcome.unknown,
    );
  });
}
