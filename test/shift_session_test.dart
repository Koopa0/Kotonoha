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
}
