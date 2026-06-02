// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/kanji_reading_question.dart';

/// Builds "choose the reading" recall questions — the honest format that makes
/// false competence hard: the learner must pick the actual READING, not nod at
/// a meaning he already owns. Distractors are real readings of OTHER kanji of
/// the SAME kind (on↔on / kun↔kun), so the on/kun chip and the meaning give no
/// edge, and the kind keeps the script (katakana on / hiragana kun) consistent
/// across options.
///
/// Pure logic: no `package:flutter/*` imports. Deterministic under [Random].
class KanjiReadingQuiz {
  const KanjiReadingQuiz({this.optionCount = 4});

  /// Number of options including the answer.
  final int optionCount;

  /// One question asking for [reading] of [target], drawing distractors from
  /// [pool]. The answer appears exactly once; distractors never duplicate it,
  /// never come from [target] itself (which could make a second option equally
  /// correct), and always share [reading]'s kind.
  KanjiReadingQuestion buildQuestion(
    KanjiEntry target,
    Reading reading,
    List<KanjiEntry> pool,
    Random rng,
  ) {
    final String answer = reading.text;

    final candidates = <String>{
      for (final e in pool)
        if (e.char != target.char)
          for (final r in e.readings)
            if (r.kind == reading.kind && r.text != answer) r.text,
    }.toList()..shuffle(rng);

    final int wanted = (optionCount - 1).clamp(0, candidates.length);
    final options = <String>[answer, ...candidates.take(wanted)]..shuffle(rng);

    return KanjiReadingQuestion(
      entry: target,
      reading: reading,
      options: options,
      correctIndex: options.indexOf(answer),
    );
  }
}
