// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// One original sentence inside a [ShiftDrill]: the kana the learner reads,
/// plus the reading / sense surfaces that stay hidden until the matching
/// hint. Not a [ReadingItem] — these sentences must not enter the 黙読 pool.
///
/// Pure data: no `package:flutter/*` imports.
class ShiftSentence {
  const ShiftSentence({
    required this.kana,
    required this.romaji,
    required this.meaning,
    required this.modifier,
    required this.head,
    required this.relation,
  });

  final String kana;
  final String romaji;
  final String meaning;

  /// The prenominal modifier the learner is practising (あおい / しずかな).
  final String modifier;

  /// The noun being modified.
  final String head;

  /// Who-modifies-whom, shown only after the sense hint.
  final String relation;
}

/// What changed between the base sentence and its original variant.
enum ShiftChange { noun, modifier }

/// Which sentence in the pair is on screen.
enum ShiftBeat { base, shift }

/// Which judgement is being recorded. Reading and sense stay separate.
enum ShiftCheck { read, sense }

/// A human-checked original pair: read the base, then the swapped sentence.
/// One success never stands for the whole [focusId].
///
/// Pure data: no `package:flutter/*` imports.
class ShiftDrill {
  const ShiftDrill({
    required this.id,
    required this.focusId,
    required this.focusTitle,
    required this.label,
    required this.change,
    required this.base,
    required this.shift,
  });

  final String id;
  final String focusId;
  final String focusTitle;
  final String label;
  final ShiftChange change;
  final ShiftSentence base;
  final ShiftSentence shift;

  ShiftSentence sentenceAt(ShiftBeat beat) =>
      beat == ShiftBeat.base ? base : shift;
}

/// A focus the learner can pick without editing the Dart corpus.
class ShiftFocus {
  const ShiftFocus({
    required this.id,
    required this.title,
    required this.drills,
  });

  final String id;
  final String title;
  final List<ShiftDrill> drills;
}
