// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

/// Builds a look-alike discrimination drill: each question's distractors are
/// drawn from the SAME confusable group as the target (topped up to 4 options
/// if the group is small), so the learner must truly tell them apart.
///
/// Pure logic, no `package:flutter/*` imports.
abstract final class Confusable {
  /// All kana that appear in any confusable group.
  static List<Kana> members(List<Kana> allKana) {
    final chars = {for (final set in kConfusableSets) ...set};
    return allKana.where((k) => chars.contains(k.character)).toList();
  }

  /// The first group containing [char] (or just [char] if none).
  static List<Kana> groupFor(String char, List<Kana> allKana) {
    final set = kConfusableSets.firstWhere(
      (s) => s.contains(char),
      orElse: () => [char],
    );
    return [for (final c in set) ...allKana.where((k) => k.character == c)];
  }

  static List<QuizQuestion> session({
    required List<Kana> allKana,
    required int length,
    required QuizEngine engine,
    required Random rng,
  }) {
    final mem = members(allKana);
    if (mem.isEmpty || length <= 0) return const [];

    final order = <Kana>[];
    while (order.length < length) {
      order.addAll(List<Kana>.of(mem)..shuffle(rng));
    }

    final result = <QuizQuestion>[];
    for (final target in order.take(length)) {
      final pool = <Kana>{...groupFor(target.character, allKana)};
      // Top up to at least 4 so there are always 4 options.
      for (final k in List<Kana>.of(allKana)..shuffle(rng)) {
        if (pool.length >= 4) break;
        pool.add(k);
      }
      final direction = rng.nextBool()
          ? QuizDirection.kanaToRomaji
          : QuizDirection.romajiToKana;
      result.add(
        engine.buildQuestion(
          target,
          direction,
          pool.toList()..shuffle(rng),
          rng,
        ),
      );
    }
    return result;
  }
}
