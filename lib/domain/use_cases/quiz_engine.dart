// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';

/// Generates quiz sessions and questions. All randomness flows through an
/// injectable [Random] so sessions are deterministic under test.
///
/// Pure logic: no `package:flutter/*` imports.
class QuizEngine {
  const QuizEngine({this.optionCount = 4});

  /// Number of multiple-choice options per question (including the answer).
  final int optionCount;

  /// Builds one question for [target] in [direction], drawing distractors from
  /// [pool]. Options are shuffled; the correct answer is always present exactly
  /// once and never duplicated by a distractor.
  QuizQuestion buildQuestion(
    Kana target,
    QuizDirection direction,
    List<Kana> pool,
    Random rng,
  ) {
    final bool toRomaji = direction == QuizDirection.kanaToRomaji;
    String optionOf(Kana k) => toRomaji ? k.romaji : k.character;

    final String answer = optionOf(target);

    // Collect distinct distractor option strings != answer. Exclude any kana
    // sharing the target's romaji (ぢ/じ, づ/ず) — else a romaji→kana question
    // would have two correct glyphs and be unanswerable.
    final candidates =
        pool
            .where((k) => k.id != target.id && k.romaji != target.romaji)
            .map(optionOf)
            .where((o) => o != answer)
            .toSet()
            .toList()
          ..shuffle(rng);

    final int wanted = (optionCount - 1).clamp(0, candidates.length);
    final options = <String>[answer, ...candidates.take(wanted)]..shuffle(rng);

    return QuizQuestion(
      target: target,
      direction: direction,
      options: options,
      correctIndex: options.indexOf(answer),
    );
  }

  /// Builds a session of [length] questions. Targets are sampled from
  /// [targets] without replacement until exhausted, then reshuffled (avoiding
  /// an immediate repeat). Distractors are always drawn from [allKana].
  /// Direction is random per question unless [direction] is fixed.
  List<QuizQuestion> generateSession({
    required List<Kana> targets,
    required List<Kana> allKana,
    required int length,
    QuizDirection? direction,
    Random? random,
  }) {
    final rng = random ?? Random();
    if (targets.isEmpty || length <= 0) return const <QuizQuestion>[];

    final order = _drawTargets(targets, length, rng);
    return <QuizQuestion>[
      for (final target in order)
        buildQuestion(
          target,
          direction ?? _randomDirection(rng),
          // Distractors stay within the target's own script (no が→カ leak).
          allKana.where((k) => k.script == target.script).toList(),
          rng,
        ),
    ];
  }

  QuizDirection _randomDirection(Random rng) =>
      rng.nextBool() ? QuizDirection.kanaToRomaji : QuizDirection.romajiToKana;

  /// Produces [length] targets by repeatedly shuffling [targets] and avoiding
  /// the same kana appearing twice in a row across shuffle boundaries.
  List<Kana> _drawTargets(List<Kana> targets, int length, Random rng) {
    final result = <Kana>[];
    while (result.length < length) {
      final batch = List<Kana>.of(targets)..shuffle(rng);
      if (result.isNotEmpty &&
          batch.length > 1 &&
          batch.first.id == result.last.id) {
        // Avoid back-to-back repeat at the seam.
        final tmp = batch[0];
        batch[0] = batch[1];
        batch[1] = tmp;
      }
      result.addAll(batch);
    }
    return result.take(length).toList();
  }
}
