// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

/// Property-based tests: instead of one hand-picked case, sweep hundreds of
/// seeded random inputs and assert the *invariants* that must hold for EVERY
/// generated question. Each iteration uses `Random(seed)` so a failure is
/// reproducible — the seed is printed in the `reason`.
void main() {
  const engine = QuizEngine(); // optionCount 4
  const iterations = 400;

  // char → script / romaji lookups over the full 208-kana universe.
  final scriptOf = {for (final k in kAllKana) k.character: k.script};
  final romajiOf = {for (final k in kAllKana) k.character: k.romaji};

  // Realistic single-script pools (what the app actually passes in).
  final pools = <List<Kana>>[
    kHiraganaGojuon,
    kKatakanaGojuon,
    kAllKana.where((k) => k.script == KanaScript.hiragana).toList(),
    kAllKana.where((k) => k.script == KanaScript.katakana).toList(),
  ];

  group('buildQuestion invariants (swept over seeds)', () {
    test('every question is well-formed', () {
      for (var seed = 0; seed < iterations; seed++) {
        final rng = Random(seed);
        final pool = pools[seed % pools.length];
        final target = pool[rng.nextInt(pool.length)];
        final direction = QuizDirection.values[rng.nextInt(3)];
        final q = engine.buildQuestion(target, direction, pool, rng);
        final why =
            'seed=$seed target=${target.id} dir=$direction '
            'options=${q.options}';

        // Options are distinct, capped at optionCount, and hold the answer once.
        expect(q.options.toSet().length, q.options.length, reason: 'dup: $why');
        expect(q.options.length, lessThanOrEqualTo(4), reason: 'cap: $why');
        expect(
          q.options.length,
          greaterThanOrEqualTo(1),
          reason: 'empty: $why',
        );
        final answer = direction == QuizDirection.kanaToRomaji
            ? target.romaji
            : target.character;
        expect(
          q.options.where((o) => o == answer).length,
          1,
          reason: 'answer-once: $why',
        );
        expect(
          q.correctIndex,
          inInclusiveRange(0, q.options.length - 1),
          reason: 'index: $why',
        );
        expect(q.options[q.correctIndex], answer, reason: 'correct: $why');
      }
    });

    test('romaji→kana: the answer is the ONLY option carrying the prompt romaji', () {
      // The real "answerable" invariant: a romaji prompt (e.g. "ji") must map to
      // exactly one correct glyph. Distractors may share a romaji with EACH
      // OTHER (ヂ/ジ as two wrong options for a "zu" prompt is fine) — what must
      // never happen is a distractor sharing the *target's* romaji.
      for (var seed = 0; seed < iterations; seed++) {
        final rng = Random(seed);
        final pool = pools[seed % pools.length];
        final target = pool[rng.nextInt(pool.length)];
        final q = engine.buildQuestion(
          target,
          QuizDirection.romajiToKana,
          pool,
          rng,
        );
        final optionsWithPromptRomaji = q.options
            .where((c) => romajiOf[c] == target.romaji)
            .toList();
        expect(
          optionsWithPromptRomaji,
          [target.character],
          reason:
              'seed=$seed target=${target.id} '
              'options=${q.options} prompt=${target.romaji}',
        );
      }
    });
  });

  group('generateSession invariants (swept over seeds)', () {
    test('length, determinism, and per-target script isolation hold', () {
      for (var seed = 0; seed < iterations; seed++) {
        final rng = Random(seed);
        // A single-script target set, but distractors drawn from ALL 208 kana —
        // this is where a cross-script leak (が→カ) would show up.
        final script = KanaScript.values[seed % 2];
        final targets = kAllKana.where((k) => k.script == script).toList()
          ..shuffle(rng);
        final picked = targets.take(1 + rng.nextInt(8)).toList();
        final length = 1 + rng.nextInt(20);

        final a = engine.generateSession(
          targets: picked,
          allKana: kAllKana,
          length: length,
          random: Random(seed),
        );
        final b = engine.generateSession(
          targets: picked,
          allKana: kAllKana,
          length: length,
          random: Random(seed),
        );

        expect(a.length, length, reason: 'seed=$seed length');
        // Determinism: same seed → identical option strings & targets.
        expect(
          [for (final q in a) q.target.id],
          [for (final q in b) q.target.id],
          reason: 'seed=$seed targets not deterministic',
        );
        expect(
          [for (final q in a) q.options],
          [for (final q in b) q.options],
          reason: 'seed=$seed options not deterministic',
        );

        for (final q in a) {
          // For glyph-option directions, every option must be the target's
          // script — romaji directions can't be checked (romaji is shared).
          if (q.direction != QuizDirection.kanaToRomaji) {
            for (final opt in q.options) {
              expect(
                scriptOf[opt],
                q.target.script,
                reason:
                    'seed=$seed cross-script option "$opt" '
                    'for target ${q.target.id}',
              );
            }
          }
        }
      }
    });

    test('empty targets or non-positive length yield no questions', () {
      final rng = Random(1);
      expect(
        engine.generateSession(
          targets: const [],
          allKana: kAllKana,
          length: 5,
          random: rng,
        ),
        isEmpty,
      );
      expect(
        engine.generateSession(
          targets: kHiraganaGojuon,
          allKana: kAllKana,
          length: 0,
          random: rng,
        ),
        isEmpty,
      );
    });
  });
}
