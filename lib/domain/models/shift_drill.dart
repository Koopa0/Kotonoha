// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// One original sentence inside a [ShiftDrill]: the kana the learner reads,
/// plus the reading / sense surfaces that stay hidden until the matching
/// hint. Not a [ReadingItem] — these sentences must not enter the 黙読 pool.
///
/// Adjective slices fill [modifier] / [head]. Action slices fill [actor],
/// [item], [verbForm], and [dictionaryForm]. Empty strings mean unused.
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
    this.actor = '',
    this.item = '',
    this.verbForm = '',
    this.dictionaryForm = '',
    this.verbChoices = const [],
    this.actorChoices = const [],
    this.itemChoices = const [],
  });

  final String kana;
  final String romaji;
  final String meaning;

  /// The prenominal modifier the learner is practising (あおい / しずかな).
  final String modifier;

  /// The noun being modified.
  final String head;

  /// Who-modifies-whom or who-brings-what, shown only after the matching hint.
  final String relation;

  /// The person doing the action (わたし / かれ / かのじょ).
  final String actor;

  /// The thing being brought over (かばん / ほん / みず / かさ).
  final String item;

  /// The conjugated verb as written in [kana] (もってきます / もってきました).
  final String verbForm;

  /// Dictionary form the conjugated verb reduces to (もってくる).
  final String dictionaryForm;

  /// Closed choices for the dictionary-form check. Must already appear in
  /// the drill's intro — never a cold form.
  final List<String> verbChoices;

  /// Closed choices for "who does this".
  final List<String> actorChoices;

  /// Closed choices for "what is brought over".
  final List<String> itemChoices;

  bool get isAction => actor.isNotEmpty && dictionaryForm.isNotEmpty;
}

/// One line on an intro card. Teaching only — never a grade.
class ShiftIntroLine {
  const ShiftIntroLine({
    required this.kana,
    required this.romaji,
    required this.meaning,
    this.note = '',
  });

  final String kana;
  final String romaji;
  final String meaning;
  final String note;
}

/// A grouped first meeting for nouns or forms used by an action drill.
class ShiftIntroCard {
  const ShiftIntroCard({required this.title, required this.lines});

  final String title;
  final List<ShiftIntroLine> lines;
}

/// What changed between the base sentence and its original variant.
///
/// Adjective drills use [noun] / [modifier]. Action drills use [actor] /
/// [item]. #73 should treat unknown values as a distinct swap kind, not
/// fall back to the adjective bridge copy.
enum ShiftChange { noun, modifier, actor, item }

/// Which sentence in the pair is on screen.
enum ShiftBeat { base, shift }

/// Which judgement is being recorded. Reading, verb restoration, roles,
/// and sense stay separate. #73 history should display [name] as-is;
/// adjective sessions still only emit [read] and [sense].
enum ShiftCheck { read, sense, verb, roles }

/// A human-checked original pair: read the base, then the swapped sentence.
/// One success never stands for the whole [focusId].
///
/// [introduce] is shown before any action check. The cards must not contain
/// a full [base] / [shift] sentence — that would expose a reserved variant.
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
    this.introduce = const [],
    this.formHint = '',
  });

  final String id;
  final String focusId;
  final String focusTitle;
  final String label;
  final ShiftChange change;
  final ShiftSentence base;
  final ShiftSentence shift;

  /// First meeting for nouns / forms. Empty on the adjective slice.
  final List<ShiftIntroCard> introduce;

  /// Dictionary-form pairing, shown only after the learner asks.
  final String formHint;

  bool get isAction =>
      change == ShiftChange.actor || change == ShiftChange.item;

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
