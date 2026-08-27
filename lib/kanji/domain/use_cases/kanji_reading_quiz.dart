// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/kanji_reading_question.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';

/// Builds "how is this read?" recall questions — the honest format for a
/// learner who already owns the meaning. The prompt is the written word with
/// no gloss, so nothing but the sound can answer it.
///
/// The distractors are the point. In order of preference they are:
///
///  1. **The naive concatenation** — 学校 read as がくこう by gluing 学【ガク】
///     to 校【コウ】. This is precisely the 漢字-literate reader's error, and a
///     learner who has actually met the word rejects it instantly while one who
///     is reasoning from characters does not.
///  2. **Other real readings of the same kanji** — 生 as せい/しょう/なま/う,
///     so knowing "生 is せい somewhere" is not enough.
///  3. **Readings of other units the learner has met**, to fill the options
///     when the inventory is thin.
///
/// Pure logic: no `package:flutter/*` imports. Deterministic under [Random].
class KanjiReadingQuiz {
  const KanjiReadingQuiz({this.optionCount = 4});

  /// Number of options including the answer.
  final int optionCount;

  KanjiReadingQuestion buildQuestion(
    KanjiUnit target,
    List<KanjiUnit> pool,
    List<KanjiEntry> inventory,
    Random rng,
  ) {
    final answer = target.reading;
    final readingsOf = <String, List<String>>{
      for (final e in inventory)
        e.char: [for (final r in e.readings) hiraganaOf(r.text)],
    };

    // 1. Character-by-character constructions of THIS word (the naive read).
    final constructed = _constructions(
      target,
      readingsOf,
    ).where((r) => r != answer).toList();
    // 2. Other readings of the constituent kanji, on their own.
    final alternatives = <String>{
      for (final char in target.chars) ...?readingsOf[char],
    }..remove(answer);
    // 3. Anything else the learner has seen, as filler.
    final others = <String>{
      for (final u in pool)
        if (u.id != target.id) u.reading,
    }..remove(answer);

    final ranked = <String>[
      ...constructed,
      ...(alternatives.toList()..shuffle(rng)),
      ...(others.toList()..shuffle(rng)),
    ];
    final distractors = <String>[];
    for (final candidate in ranked) {
      if (distractors.length >= optionCount - 1) break;
      if (candidate.isEmpty || distractors.contains(candidate)) continue;
      distractors.add(candidate);
    }

    final options = <String>[answer, ...distractors]..shuffle(rng);
    return KanjiReadingQuestion(
      unit: target,
      options: options,
      correctIndex: options.indexOf(answer),
    );
  }

  /// Readings built by reading each kanji of [unit] separately and gluing the
  /// pieces together — every combination, longest-plausible first. Empty when
  /// the curriculum does not know one of the characters.
  List<String> _constructions(
    KanjiUnit unit,
    Map<String, List<String>> readingsOf,
  ) {
    var built = <String>[''];
    for (final char in unit.chars) {
      final readings = readingsOf[char];
      if (readings == null || readings.isEmpty) return const [];
      built = [
        for (final prefix in built)
          for (final reading in readings) prefix + reading,
      ];
      if (built.length > 32) break; // no real word branches this far
    }
    return built;
  }

  /// Katakana → hiragana. On-readings are stored in katakana (the teaching cue)
  /// but furigana and options are hiragana, so they must be compared in one
  /// script or a correct answer could show up as its own distractor.
  static String hiraganaOf(String kana) => String.fromCharCodes([
    for (final r in kana.runes)
      if (r >= 0x30a1 && r <= 0x30f6) r - 0x60 else r,
  ]);
}
