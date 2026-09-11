// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/shift_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';

import 'helpers/kana_orthography.dart';

void main() {
  test('one focus exposes い and な drills the learner can pick', () {
    final focuses = ShiftSession.focuses();
    expect(focuses, hasLength(1));
    expect(focuses.single.id, 'adj-mod');
    expect(focuses.single.drills.map((d) => d.id), [
      'i-adj-aoi-noun',
      'na-adj-shizuka-noun',
    ]);
    expect(ShiftSession.drillById('i-adj-aoi-noun')?.base.kana, 'あおい そら');
    expect(ShiftSession.drillById('missing'), isNull);
  });

  test('shift sentences stay out of the 黙読 / travel phrase pool', () {
    final phraseKana = {for (final p in kPhrases) p.kana};
    for (final drill in kShiftDrills) {
      expect(phraseKana, isNot(contains(drill.base.kana)), reason: drill.id);
      expect(phraseKana, isNot(contains(drill.shift.kana)), reason: drill.id);
    }
  });

  test('every shift sentence is clean hiragana with a reading and sense', () {
    final ids = <String>{};
    for (final drill in kShiftDrills) {
      expect(ids.add(drill.id), isTrue, reason: drill.id);
      for (final sentence in [drill.base, drill.shift]) {
        expect(sentence.romaji, isNotEmpty, reason: sentence.kana);
        expect(sentence.meaning, isNotEmpty, reason: sentence.kana);
        expect(sentence.relation, contains(sentence.modifier));
        expect(sentence.relation, contains(sentence.head));
        expect(
          validateKanaOrthography(sentence.kana, KanaScript.hiragana),
          isEmpty,
          reason: sentence.kana,
        );
      }
    }
  });

  test('attempt meta keeps read / sense and base / shift apart', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final at = DateTime(2026, 9, 10);
    final read = ShiftSession.attempt(
      drill: drill,
      beat: ShiftBeat.base,
      check: ShiftCheck.read,
      prompted: false,
      correct: true,
      sessionId: 's',
      at: at,
    );
    final sense = ShiftSession.attempt(
      drill: drill,
      beat: ShiftBeat.shift,
      check: ShiftCheck.sense,
      prompted: true,
      correct: true,
      sessionId: 's',
      at: at,
      sourceUrl: ' https://example.test/note ',
    );
    expect(read.mode, PracticeMode.shift.name);
    expect(read.itemType, ItemType.shift);
    expect(read.itemId, 'shift:i-adj-aoi-noun:base');
    expect(read.meta[AttemptMeta.prompted], isFalse);
    expect(read.meta[AttemptMeta.evidence], ShiftCheck.read.name);
    expect(read.meta.containsKey(AttemptMeta.source), isFalse);
    expect(sense.itemId, 'shift:i-adj-aoi-noun:shift');
    expect(sense.meta[AttemptMeta.prompted], isTrue);
    expect(sense.meta[AttemptMeta.evidence], ShiftCheck.sense.name);
    expect(sense.meta[AttemptMeta.source], 'https://example.test/note');
    expect(ShiftSession.isTransferSense(read), isFalse);
    expect(ShiftSession.isTransferSense(sense), isTrue);
  });

  test('exact Chinese or a full session still does not master the focus', () {
    final drill = ShiftSession.drillById('na-adj-shizuka-noun')!;
    expect(
      ShiftSession.gradesExplanation('安靜的房間', drill.base.meaning),
      isFalse,
    );
    expect(ShiftSession.gradesExplanation('しずかな へや', drill.base.kana), isFalse);
    final attempts = [
      for (final beat in ShiftBeat.values)
        for (final check in ShiftCheck.values)
          ShiftSession.attempt(
            drill: drill,
            beat: beat,
            check: check,
            prompted: false,
            correct: true,
            sessionId: 's',
            at: DateTime(2026, 9, 10),
          ),
    ];
    expect(ShiftSession.marksFocusMastered(attempts), isFalse);
    expect(attempts.where(ShiftSession.isTransferSense), hasLength(1));
  });

  test(
    'day 0 hold keeps the reserved shift hidden until the next local day',
    () {
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      final day0 = DateTime(2026, 9, 10, 10);
      final day0Evening = DateTime(2026, 9, 10, 22);
      final day1 = DateTime(2026, 9, 11, 9);
      final hold = ShiftSession.plan(
        drill: drill,
        now: day0,
        requested: ShiftLane.hold,
      );
      expect(hold.lane, ShiftLane.hold);
      expect(hold.beats, [ShiftBeat.base]);
      expect(hold.firstUnseen, isFalse);
      expect(ShiftSession.pickerPreview(hold), drill.base.kana);
      expect(hold.holdUntil, '2026-09-11');

      final reserved = ShiftSession.reservation(
        drill: drill,
        sessionId: 'hold',
        at: day0,
      );
      expect(reserved.meta[AttemptMeta.scored], isFalse);
      expect(reserved.meta.containsKey(AttemptMeta.sight), isFalse);
      expect(reserved.meta[AttemptMeta.holdUntil], '2026-09-11');
      expect(
        ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: [reserved]),
        ShiftSight.unseen,
      );

      final sameDay = ShiftSession.plan(
        drill: drill,
        now: day0Evening,
        attempts: [reserved],
        requested: ShiftLane.hold,
      );
      expect(sameDay.lane, ShiftLane.hold);
      expect(sameDay.confirmDue, isFalse);
      expect(sameDay.holdPending, isTrue);
      expect(sameDay.firstUnseen, isFalse);

      final confirm = ShiftSession.plan(
        drill: drill,
        now: day1,
        attempts: [reserved],
      );
      expect(confirm.lane, ShiftLane.confirm);
      expect(confirm.beats, [ShiftBeat.shift]);
      expect(confirm.firstUnseen, isTrue);
      expect(ShiftSession.pickerPreview(confirm), isNull);
    },
  );

  test('same-day start is still available and is not a next-day confirm', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final day0 = DateTime(2026, 9, 10);
    final same = ShiftSession.plan(drill: drill, now: day0);
    expect(same.lane, ShiftLane.sameDay);
    expect(same.beats, [ShiftBeat.base, ShiftBeat.shift]);
    expect(same.firstUnseen, isFalse);

    final held = ShiftSession.reservation(
      drill: drill,
      sessionId: 'h',
      at: day0,
    );
    final optOut = ShiftSession.plan(
      drill: drill,
      now: day0,
      attempts: [held],
      requested: ShiftLane.sameDay,
    );
    expect(optOut.lane, ShiftLane.sameDay);
    expect(optOut.beats, [ShiftBeat.base, ShiftBeat.shift]);
    expect(optOut.holdPending, isTrue);
  });

  test('read and sense self-grades stay separate, including mixed support', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final day0 = DateTime(2026, 9, 10, 10);
    final day1 = DateTime(2026, 9, 11, 10);
    final rows = [
      ShiftSession.attempt(
        drill: drill,
        beat: ShiftBeat.base,
        check: ShiftCheck.read,
        prompted: false,
        correct: true,
        sessionId: 'd0',
        at: day0,
        lane: ShiftLane.hold,
      ),
      ShiftSession.attempt(
        drill: drill,
        beat: ShiftBeat.base,
        check: ShiftCheck.sense,
        prompted: true,
        correct: true,
        sessionId: 'd0',
        at: day0,
        lane: ShiftLane.hold,
        readSupport: ShiftReadSupport.independent,
      ),
      ShiftSession.attempt(
        drill: drill,
        beat: ShiftBeat.shift,
        check: ShiftCheck.read,
        prompted: true,
        correct: true,
        sessionId: 'd1',
        at: day1,
        lane: ShiftLane.confirm,
      ),
      ShiftSession.attempt(
        drill: drill,
        beat: ShiftBeat.shift,
        check: ShiftCheck.sense,
        prompted: false,
        correct: true,
        sessionId: 'd1',
        at: day1,
        lane: ShiftLane.confirm,
        readSupport: ShiftReadSupport.prompted,
      ),
      ShiftSession.attempt(
        drill: drill,
        beat: ShiftBeat.shift,
        check: ShiftCheck.read,
        prompted: true,
        correct: false,
        sessionId: 'd1b',
        at: day1.add(const Duration(minutes: 30)),
        lane: ShiftLane.confirm,
      ),
      ShiftSession.attempt(
        drill: drill,
        beat: ShiftBeat.shift,
        check: ShiftCheck.sense,
        prompted: true,
        correct: false,
        sessionId: 'd1b',
        at: day1.add(const Duration(minutes: 31)),
        lane: ShiftLane.confirm,
        readSupport: ShiftReadSupport.prompted,
      ),
    ];
    final history = ShiftSession.selfGrades(rows, drillId: drill.id);
    expect(history, hasLength(6));
    expect(history[0].check, ShiftCheck.read);
    expect(history[0].prompted, isFalse);
    expect(history[1].check, ShiftCheck.sense);
    expect(history[1].readSupport, ShiftReadSupport.independent);
    expect(history[2].prompted, isTrue);
    expect(history[3].prompted, isFalse);
    expect(history[3].readSupport, ShiftReadSupport.prompted);
    expect(history[4].correct, isFalse);
    expect(history[5].correct, isFalse);
    expect(
      history.map((g) => '${g.check.name}:${g.prompted}:${g.correct}').toSet(),
      hasLength(6),
    );
    expect(ShiftSession.marksFocusMastered(rows), isFalse);
  });

  test('practice sighting without a grade is seen, not first-unseen', () {
    final drill = ShiftSession.drillById('na-adj-shizuka-noun')!;
    final day0 = DateTime(2026, 9, 10);
    final day1 = DateTime(2026, 9, 11);
    final reserved = ShiftSession.reservation(
      drill: drill,
      sessionId: 'h',
      at: day0,
    );
    final shown = ShiftSession.sighting(
      drill: drill,
      beat: ShiftBeat.shift,
      kind: ShiftSightKind.practice,
      sessionId: 'c',
      at: day1,
      lane: ShiftLane.confirm,
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: [reserved, shown]),
      ShiftSight.seen,
    );
    final plan = ShiftSession.plan(
      drill: drill,
      now: day1,
      attempts: [reserved, shown],
    );
    expect(plan.lane, ShiftLane.confirm);
    expect(plan.firstUnseen, isFalse);
  });

  test('menu preview counts as exposure for the shown beat only', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final preview = ShiftSession.sighting(
      drill: drill,
      beat: ShiftBeat.base,
      kind: ShiftSightKind.preview,
      sessionId: 'p',
      at: DateTime(2026, 9, 10),
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.base, attempts: [preview]),
      ShiftSight.seen,
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: [preview]),
      ShiftSight.unseen,
    );
  });

  test('legacy rows without sight metadata are unknown, not unseen', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final legacy = Attempt(
      ts: DateTime(2026, 9, 1).millisecondsSinceEpoch,
      itemId: ShiftSession.itemId(drill, ShiftBeat.base),
      itemType: ItemType.shift,
      mode: PracticeMode.shift.name,
      correct: true,
      sessionId: 'old',
      meta: const {
        AttemptMeta.prompted: false,
        AttemptMeta.evidence: 'read',
        AttemptMeta.beat: 'base',
        AttemptMeta.drill: 'i-adj-aoi-noun',
        AttemptMeta.focus: 'adj-mod',
      },
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: [legacy]),
      ShiftSight.unknown,
    );
    final plan = ShiftSession.plan(
      drill: drill,
      now: DateTime(2026, 9, 11),
      attempts: [legacy],
    );
    expect(plan.lane, ShiftLane.review);
    expect(plan.firstUnseen, isFalse);
    expect(plan.noUnseenVariant, isTrue);
  });

  test('legacy unknown stays unknown after menu preview on the other beat', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final legacy = Attempt(
      ts: DateTime(2026, 9, 1).millisecondsSinceEpoch,
      itemId: ShiftSession.itemId(drill, ShiftBeat.base),
      itemType: ItemType.shift,
      mode: PracticeMode.shift.name,
      correct: true,
      sessionId: 'old',
      meta: const {
        AttemptMeta.prompted: false,
        AttemptMeta.evidence: 'read',
        AttemptMeta.beat: 'base',
        AttemptMeta.drill: 'i-adj-aoi-noun',
        AttemptMeta.focus: 'adj-mod',
      },
    );
    final preview = ShiftSession.sighting(
      drill: drill,
      beat: ShiftBeat.base,
      kind: ShiftSightKind.preview,
      sessionId: 'p',
      at: DateTime(2026, 9, 11),
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: [legacy, preview]),
      ShiftSight.unknown,
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.base, attempts: [legacy, preview]),
      ShiftSight.seen,
    );
    final plan = ShiftSession.plan(
      drill: drill,
      now: DateTime(2026, 9, 11),
      attempts: [legacy, preview],
    );
    expect(plan.lane, ShiftLane.review);
    expect(plan.firstUnseen, isFalse);
    expect(plan.noUnseenVariant, isTrue);
    expect(plan.shiftSight, ShiftSight.unknown);
    expect(
      ShiftSession.plan(
        drill: drill,
        now: DateTime(2026, 9, 11),
        attempts: [legacy, preview],
        requested: ShiftLane.hold,
      ).lane,
      ShiftLane.review,
    );
  });

  test('protocol-only preview still leaves the reserved beat unseen', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final preview = ShiftSession.sighting(
      drill: drill,
      beat: ShiftBeat.base,
      kind: ShiftSightKind.preview,
      sessionId: 'p',
      at: DateTime(2026, 9, 10),
    );
    expect(
      ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: [preview]),
      ShiftSight.unseen,
    );
    final hold = ShiftSession.plan(
      drill: drill,
      now: DateTime(2026, 9, 10),
      attempts: [preview],
      requested: ShiftLane.hold,
    );
    expect(hold.lane, ShiftLane.hold);
    expect(hold.shiftSight, ShiftSight.unseen);
  });

  test('seen pair is an old-sentence review, not a new item', () {
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final at = DateTime(2026, 9, 10);
    final seen = [
      for (final beat in ShiftBeat.values)
        for (final check in ShiftCheck.values)
          ShiftSession.attempt(
            drill: drill,
            beat: beat,
            check: check,
            prompted: false,
            correct: true,
            sessionId: 'full',
            at: at,
          ),
    ];
    final plan = ShiftSession.plan(
      drill: drill,
      now: DateTime(2026, 9, 11),
      attempts: seen,
    );
    expect(plan.lane, ShiftLane.review);
    expect(plan.noUnseenVariant, isTrue);
    expect(plan.firstUnseen, isFalse);
    expect(
      ShiftSession.plan(
        drill: drill,
        now: DateTime(2026, 9, 11),
        attempts: seen,
        requested: ShiftLane.hold,
      ).lane,
      ShiftLane.review,
    );
  });

  test('plan keys on drill id so a later catalogue row can reuse hold', () {
    final sample = ShiftSession.drillById('i-adj-aoi-noun')!;
    final extra = ShiftDrill(
      id: 'future-catalogue-row',
      focusId: sample.focusId,
      focusTitle: sample.focusTitle,
      label: sample.label,
      change: sample.change,
      base: sample.base,
      shift: sample.shift,
    );
    final day0 = DateTime(2026, 9, 10, 10);
    final reserved = ShiftSession.reservation(
      drill: extra,
      sessionId: 'h',
      at: day0,
    );
    expect(reserved.itemId, 'shift:future-catalogue-row:shift');
    expect(
      ShiftSession.sightOf(extra, ShiftBeat.shift, attempts: [reserved]),
      ShiftSight.unseen,
    );
    final hold = ShiftSession.plan(
      drill: extra,
      now: day0,
      attempts: [reserved],
      requested: ShiftLane.hold,
    );
    expect(hold.lane, ShiftLane.hold);
    expect(hold.beats, [ShiftBeat.base]);
    expect(ShiftSession.pickerPreview(hold), extra.base.kana);
    final confirm = ShiftSession.plan(
      drill: extra,
      now: DateTime(2026, 9, 11, 9),
      attempts: [reserved],
    );
    expect(confirm.lane, ShiftLane.confirm);
    expect(confirm.firstUnseen, isTrue);
    expect(ShiftSession.pickerPreview(confirm), isNull);
  });
}
