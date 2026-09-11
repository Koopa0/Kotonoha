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

/// How this sitting uses the curated pair. Same-session practice stays
/// [sameDay]; [hold] / [confirm] are the optional next-day path.
enum ShiftLane { sameDay, hold, confirm, review }

/// Whether a beat's sentence has a known display — not a mastery mark.
enum ShiftSight { unseen, seen, unknown }

/// How a sentence became visible. Written to [AttemptMeta.sight].
abstract final class ShiftSightKind {
  static const String preview = 'preview';
  static const String practice = 'practice';
}

/// Reading support already on screen when the sense check was graded.
///
/// [independent] is a verified unprompted read after the reveal check,
/// not the pre-reveal「讀得出來」commit. A failed self-grade is [prompted].
abstract final class ShiftReadSupport {
  static const String independent = 'independent';
  static const String prompted = 'prompted';
}

/// One sitting decided from attempts + the learner's optional hold request.
class ShiftPlan {
  const ShiftPlan({
    required this.drill,
    required this.lane,
    required this.beats,
    required this.baseSight,
    required this.shiftSight,
    required this.firstUnseen,
    required this.holdPending,
    required this.confirmDue,
    required this.noUnseenVariant,
    this.holdUntil,
  });

  final ShiftDrill drill;
  final ShiftLane lane;
  final List<ShiftBeat> beats;
  final ShiftSight baseSight;
  final ShiftSight shiftSight;
  final bool firstUnseen;
  final bool holdPending;
  final bool confirmDue;
  final bool noUnseenVariant;
  final String? holdUntil;
}

/// One self-grade row for the look-back. Never a mastery or streak.
class ShiftSelfGrade {
  const ShiftSelfGrade({
    required this.at,
    required this.day,
    required this.drillId,
    required this.beat,
    required this.check,
    required this.prompted,
    required this.correct,
    this.readSupport,
    this.lane,
  });

  final DateTime at;
  final String day;
  final String drillId;
  final ShiftBeat beat;
  final ShiftCheck check;
  final bool prompted;
  final bool correct;
  final String? readSupport;
  final ShiftLane? lane;
}
