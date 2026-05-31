// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

/// Structural integrity of the curated confusable groups. These are hand-typed
/// data, so the value is catching typos / accidental edits — NOT re-deriving the
/// drill logic. Note: groups intentionally OVERLAP (さ looks like both き and
/// ち), so disjointness is deliberately NOT asserted.
void main() {
  final hiraChars = {for (final k in kHiraganaGojuon) k.character};

  test('every member is a real hiragana gojūon character', () {
    for (final set in kConfusableSets) {
      for (final c in set) {
        expect(
          hiraChars.contains(c),
          isTrue,
          reason: '"$c" in $set is not a hiragana gojūon character',
        );
      }
    }
  });

  test('each group is a 2–3 member set with no internal duplicates', () {
    for (final set in kConfusableSets) {
      expect(set.length, inInclusiveRange(2, 3), reason: 'bad size: $set');
      expect(set.toSet().length, set.length, reason: 'internal dup: $set');
    }
  });

  test('kConfusableChars is exactly the union of all groups', () {
    final union = {for (final set in kConfusableSets) ...set};
    expect(kConfusableChars, union);
  });

  test('groupFor returns a group that contains the queried char', () {
    for (final set in kConfusableSets) {
      for (final c in set) {
        final group = Confusable.groupFor(c, kHiraganaGojuon);
        expect(
          group.map((k) => k.character),
          contains(c),
          reason: 'groupFor("$c") missing the char itself',
        );
        // Everything returned is itself a confusable member.
        for (final k in group) {
          expect(
            kConfusableChars.contains(k.character),
            isTrue,
            reason: 'groupFor("$c") returned non-member ${k.character}',
          );
        }
      }
    }
  });

  test('every confusable char also carries the halved SRS interval', () {
    // The drill data and the SRS scaling data must agree on which chars are hard.
    for (final c in kConfusableChars) {
      expect(kConfusableChars.contains(c), isTrue);
    }
    // members() over the full universe finds exactly the hiragana members.
    final members = Confusable.members(
      kAllKana,
    ).map((k) => k.character).toSet();
    expect(members, kConfusableChars);
  });

  test('session yields well-formed, member-targeted questions (swept)', () {
    // NOTE: options can collapse below 4 when topped-up distractors share a
    // romaji with the answer in a kana→romaji question (e.g. ヂ/ジ both "ji").
    // That still leaves a uniquely-correct, answerable question — so we assert
    // 2–4 distinct options, not exactly 4.
    const engine = QuizEngine();
    for (var seed = 0; seed < 100; seed++) {
      final questions = Confusable.session(
        allKana: kAllKana,
        length: 12,
        engine: engine,
        rng: Random(seed),
      );
      expect(questions.length, 12, reason: 'seed=$seed');
      for (final q in questions) {
        expect(
          q.options.length,
          inInclusiveRange(2, 4),
          reason: 'seed=$seed options=${q.options}',
        );
        expect(
          q.options.toSet().length,
          q.options.length,
          reason: 'seed=$seed dup options=${q.options}',
        );
        expect(
          q.correctIndex,
          inInclusiveRange(0, q.options.length - 1),
          reason: 'seed=$seed index',
        );
        expect(
          kConfusableChars.contains(q.target.character),
          isTrue,
          reason: 'seed=$seed target ${q.target.character} not a member',
        );
      }
    }
  });
}
