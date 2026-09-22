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
///  3. **Readings of other units the learner has met** — the [pool], normally
///     this session — to fill the options when the inventory is thin.
///
/// Two options is the floor: a card offering only the answer is not a question,
/// and the one tap available would be filed as recall that never happened. When
/// the pool cannot reach it (荷物 reviewed alone, with neither 荷 nor 物 in the
/// reading inventory), and only then, readings are borrowed from [corpus] — the
/// wider harvested set, met or not.
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
    Random rng, {
    List<KanjiUnit> corpus = const [],
  }) {
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
    // 3. Other real readings from the pool the learner has met, as filler.
    final others = _otherReadings(pool, target, answer);

    final ranked = <String>[
      ...constructed,
      ...(alternatives.toList()..shuffle(rng)),
      ...(others.toList()..shuffle(rng)),
    ];
    final distractors = <String>[];
    void take(Iterable<String> candidates) {
      for (final candidate in candidates) {
        if (distractors.length >= optionCount - 1) break;
        if (candidate.isEmpty || distractors.contains(candidate)) continue;
        distractors.add(candidate);
      }
    }

    take(ranked);
    // Only now, and only to clear the floor: borrowing is lazy, so a pool that
    // can answer for itself sees the same question it always did.
    if (distractors.isEmpty) {
      take(_otherReadings(corpus, target, answer).toList()..shuffle(rng));
    }

    final options = <String>[answer, ...distractors]..shuffle(rng);
    return KanjiReadingQuestion(
      unit: target,
      options: options,
      correctIndex: options.indexOf(answer),
    );
  }

  /// Real readings of every unit in [units] but [target] itself, minus the
  /// answer — the filler tier, and what a borrow from the corpus draws on.
  Set<String> _otherReadings(
    List<KanjiUnit> units,
    KanjiUnit target,
    String answer,
  ) => <String>{
    for (final u in units)
      if (u.id != target.id) u.reading,
  }..remove(answer);

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
