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
  test('picker exposes adjective and bring-over focuses', () {
    final focuses = ShiftSession.focuses();
    expect(focuses.map((f) => f.id), ['adj-mod', kBringFocusId]);
    expect(focuses.first.drills.map((d) => d.id), [
      'i-adj-aoi-noun',
      'na-adj-shizuka-noun',
    ]);
    expect(focuses.last.title, kBringFocusTitle);
    expect(focuses.last.drills.map((d) => d.id), [
      'bring-actor-watashi-kare',
      'bring-item-hon-mizu',
      'bring-actor-kare-watashi',
      'bring-item-mizu-hon',
      'bring-past-actor-kanojo-kare',
    ]);
    expect(ShiftSession.drillById('i-adj-aoi-noun')?.base.kana, 'あおい そら');
    expect(
      ShiftSession.drillById('bring-actor-watashi-kare')?.shift.kana,
      'かれが かばんを もってきます',
    );
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
        expect(
          validateKanaOrthography(sentence.kana, KanaScript.hiragana),
          isEmpty,
          reason: sentence.kana,
        );
        final compact = sentence.romaji.replaceAll(' ', '').replaceAll("'", '');
        final possible = possibleReadingRomaji(
          sentence.kana.replaceAll(' ', ''),
        );
        expect(
          possible.any((p) => p.replaceAll("'", '') == compact),
          isTrue,
          reason: '${sentence.kana} romaji ${sentence.romaji}',
        );
        if (sentence.isAction) {
          expect(sentence.actor, isNotEmpty, reason: sentence.kana);
          expect(sentence.item, isNotEmpty, reason: sentence.kana);
          expect(sentence.verbForm, isNotEmpty, reason: sentence.kana);
          expect(sentence.dictionaryForm, isNotEmpty, reason: sentence.kana);
          expect(sentence.relation, contains(sentence.actor));
          expect(sentence.relation, contains(sentence.item));
          expect(sentence.kana, contains('${sentence.actor}が'));
          expect(sentence.kana, contains('${sentence.item}を'));
          expect(sentence.kana, contains(sentence.verbForm));
        } else {
          expect(sentence.relation, contains(sentence.modifier));
          expect(sentence.relation, contains(sentence.head));
        }
      }
    }
  });

  test('bring-over intro teaches every form a check can offer', () {
    final sentences = <String>{};
    for (final drill in kShiftDrills.where((d) => d.isAction)) {
      expect(drill.introduce, isNotEmpty, reason: drill.id);
      expect(drill.formHint, isNotEmpty, reason: drill.id);
      final taught = {
        for (final card in drill.introduce)
          for (final line in card.lines) line.kana,
      };
      for (final card in drill.introduce) {
        for (final line in card.lines) {
          expect(line.romaji, isNotEmpty, reason: line.kana);
          expect(line.meaning, isNotEmpty, reason: line.kana);
          expect(
            validateKanaOrthography(line.kana, KanaScript.hiragana),
            isEmpty,
            reason: line.kana,
          );
        }
      }
      for (final sentence in [drill.base, drill.shift]) {
        expect(sentences.add(sentence.kana), isTrue, reason: sentence.kana);
        expect(taught, contains(sentence.actor), reason: drill.id);
        expect(taught, contains(sentence.item), reason: drill.id);
        expect(taught, contains(sentence.verbForm), reason: drill.id);
        expect(taught, contains(sentence.dictionaryForm), reason: drill.id);
        for (final choice in [
          ...sentence.verbChoices,
          ...sentence.actorChoices,
          ...sentence.itemChoices,
        ]) {
          expect(taught, contains(choice), reason: '${drill.id} $choice');
        }
        expect(sentence.verbChoices, contains(sentence.dictionaryForm));
        expect(sentence.actorChoices, contains(sentence.actor));
        expect(sentence.itemChoices, contains(sentence.item));
      }
      final introText = [
        for (final card in drill.introduce)
          for (final line in card.lines) '${line.kana} ${line.note}',
      ].join(' ');
      expect(introText.contains(drill.base.kana), isFalse, reason: drill.id);
      expect(introText.contains(drill.shift.kana), isFalse, reason: drill.id);
    }
    expect(sentences, hasLength(10));
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
    expect(read.meta[AttemptMeta.scored], isTrue);
    expect(read.meta.containsKey(AttemptMeta.source), isFalse);
    expect(sense.itemId, 'shift:i-adj-aoi-noun:shift');
    expect(sense.meta[AttemptMeta.prompted], isTrue);
    expect(sense.meta[AttemptMeta.evidence], ShiftCheck.sense.name);
    expect(sense.meta[AttemptMeta.source], 'https://example.test/note');
    expect(sense.meta.containsKey(AttemptMeta.readSupport), isFalse);
    expect(ShiftSession.isTransferSense(read), isFalse);
    expect(ShiftSession.isTransferSense(sense), isTrue);
    expect(ShiftSession.checksFor(drill), [ShiftCheck.read, ShiftCheck.sense]);
  });

  test('action checks stay on the same itemId contract as adjective pairs', () {
    final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
    expect(ShiftSession.checksFor(drill), [
      ShiftCheck.read,
      ShiftCheck.verb,
      ShiftCheck.roles,
      ShiftCheck.sense,
    ]);
    final verb = ShiftSession.attempt(
      drill: drill,
      beat: ShiftBeat.shift,
      check: ShiftCheck.verb,
      prompted: false,
      correct: true,
      sessionId: 's',
      at: DateTime(2026, 9, 10),
    );
    final roles = ShiftSession.attempt(
      drill: drill,
      beat: ShiftBeat.shift,
      check: ShiftCheck.roles,
      prompted: true,
      correct: false,
      sessionId: 's',
      at: DateTime(2026, 9, 10),
    );
    expect(verb.itemId, 'shift:bring-actor-watashi-kare:shift');
    expect(roles.itemId, verb.itemId);
    expect(verb.meta[AttemptMeta.evidence], ShiftCheck.verb.name);
    expect(roles.meta[AttemptMeta.evidence], ShiftCheck.roles.name);
    expect(ShiftSession.isTransferVerb(verb), isTrue);
    expect(ShiftSession.isTransferRoles(roles), isTrue);
    expect(ShiftSession.isTransferSense(verb), isFalse);
  });

  test('dictionary form and roles have one structural answer', () {
    final present = ShiftSession.drillById('bring-actor-watashi-kare')!.base;
    final past = ShiftSession.drillById('bring-past-actor-kanojo-kare')!.base;
    expect(ShiftSession.gradesVerb('もってくる', present), isTrue);
    expect(ShiftSession.gradesVerb('もってきます', present), isFalse);
    expect(ShiftSession.gradesVerb('もってきました', present), isFalse);
    expect(ShiftSession.gradesVerb('くる', present), isFalse);
    expect(ShiftSession.gradesVerb('もってくる', past), isTrue);
    expect(ShiftSession.gradesVerb('もってきました', past), isFalse);
    expect(
      ShiftSession.gradesRoles(actor: 'わたし', item: 'かばん', sentence: present),
      isTrue,
    );
    expect(
      ShiftSession.gradesRoles(actor: 'かれ', item: 'かばん', sentence: present),
      isFalse,
    );
    expect(
      ShiftSession.gradesRoles(actor: 'わたし', item: 'ほん', sentence: present),
      isFalse,
    );
    final adj = ShiftSession.drillById('i-adj-aoi-noun')!.base;
    expect(ShiftSession.gradesVerb('あおい', adj), isFalse);
    expect(
      ShiftSession.gradesRoles(actor: 'そら', item: 'あおい', sentence: adj),
      isFalse,
    );
  });

  test('exact Chinese or a full session still does not master the focus', () {
    final drill = ShiftSession.drillById('na-adj-shizuka-noun')!;
    expect(
      ShiftSession.gradesExplanation('安靜的房間', drill.base.meaning),
      isFalse,
    );
    expect(ShiftSession.gradesExplanation('しずかな へや', drill.base.kana), isFalse);
    final action = ShiftSession.drillById('bring-item-hon-mizu')!;
    expect(
      ShiftSession.gradesExplanation('她把書帶過來。', action.base.meaning),
      isFalse,
    );
    final attempts = [
      for (final beat in ShiftBeat.values)
        for (final check in ShiftCheck.values)
          ShiftSession.attempt(
            drill: action,
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
    expect(attempts.where(ShiftSession.isTransferVerb), hasLength(1));
    expect(attempts.where(ShiftSession.isTransferRoles), hasLength(1));
  });
}
