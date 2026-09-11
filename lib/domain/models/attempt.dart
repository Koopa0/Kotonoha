// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Where an answer happened — used to compare which modes work best.
enum PracticeMode {
  quickReview, // generic recognition test (lessons, daily "new" slot)
  lessonTest,
  missed,
  confusable, // look-alike kana discrimination drill
  daily, // adaptive "today's session"
  writing, // paper recall (self-graded, paired with the user's paper book)
  reading, // contextual word reading (glyph string → sound, self-graded)
  ferry, // hear → watch the kana ink in → read it back (sound↔glyph binding)
  dictation, // hear → assemble the kana (production / encoding)
  listening, // hear → recall → reveal → rehear (comprehension; not kana ID)
  shift, // original swap-sentence: reading vs sense, base vs transferred
  placementCheck, // explicit prior-range check: answer first, then reveal
  reply, // hear a station ask, pick intent, pick a short reply (not speech)
  info, // hear travel info, pick amount / time / headcount (not speech)
}

/// The kind of learnable item an [Attempt] is about. Content-agnostic so kanji
/// and vocab can share the same analytics stream later.
abstract final class ItemType {
  static const String kana = 'kana';
  static const String kanji = 'kanji';
  static const String word = 'word';
  static const String shift = 'shift';
}

/// Well-known keys inside [Attempt.meta] (mode-specific payload).
abstract final class AttemptMeta {
  static const String direction = 'direction'; // QuizDirection.name / write…
  static const String distractor = 'distractor'; // wrong MC option chosen
  /// Whether the learner saw the reading before grading (bool).
  static const String prompted = 'prompted';

  /// Whether the learner opened a meaning hint before grading (bool).
  static const String hinted = 'hinted';
  static const String playback = 'playback'; // SpeechPlaybackResult.name
  static const String heard = 'heard'; // true only after a completed play
  static const String scored = 'scored'; // false = exposure, not a grade
  /// Shift-practice check: [ShiftCheck.name]
  /// (`read`, `sense`, and action drills also `verb`, `roles`).
  static const String evidence = 'evidence';

  /// Shift-practice beat: [ShiftBeat.name] (`base` or `shift`).
  static const String beat = 'beat';
  static const String drill = 'drill';
  static const String focus = 'focus';

  /// Optional learner-supplied source URL (context only; never fetched).
  static const String source = 'source';

  /// Shift-practice lane: [ShiftLane.name] (`sameDay`, `hold`, `confirm`,
  /// `review`). Associates a delayed retest without a second ledger.
  static const String lane = 'lane';

  /// Local calendar date (`YYYY-MM-DD`) when a reserved shift beat is due.
  static const String holdUntil = 'holdUntil';

  /// How a shift sentence became visible: `preview` or `practice`.
  /// Absence on a legacy row means exposure is unknown — never "unseen".
  static const String sight = 'sight';

  /// Reading support already given when a shift sense check was graded
  /// (`independent` or `prompted`). Independent requires a correct
  /// unprompted read after reveal, not the pre-reveal commit alone.
  /// Sense never inherits a mastery flag. This is reading-only — a roles
  /// Chinese gloss is sense support, not this key.
  static const String readSupport = 'readSupport';
}

/// One answered item — the fine-grained event stream behind learning analytics.
///
/// Schema v2: a **content-agnostic stable core** plus an open [meta] map for
/// mode-specific fields. This keeps the stream usable when kanji (multi-reading,
/// not 4-choice) arrives. `meta` values must be JSON primitives (String/num/bool).
///
/// Pure data: no `package:flutter/*` imports.
class Attempt {
  const Attempt({
    required this.ts,
    required this.itemId,
    required this.mode,
    required this.correct,
    required this.sessionId,
    this.itemType = ItemType.kana,
    this.rtMs = 0,
    this.meta = const {},
  });

  factory Attempt.fromJson(Map<String, Object?> m) {
    return Attempt(
      ts: (m['ts']! as num).toInt(),
      itemId: m['item']! as String,
      itemType: m['type'] as String? ?? ItemType.kana,
      mode: m['mode']! as String,
      correct: (m['correct']! as num).toInt() == 1,
      rtMs: (m['rt'] as num?)?.toInt() ?? 0,
      sessionId: m['session']! as String,
      meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  final int ts; // ms since epoch
  final String itemId; // learnable item id (kana char now; kanji/word later)
  final String itemType; // ItemType.*
  final String mode; // PracticeMode.name
  final bool correct;

  /// Reaction time. 0 = untimed (writing/handwriting), NOT a real 0ms.
  final int rtMs;
  final String sessionId;
  final Map<String, Object?> meta;

  // Typed read-through getters over meta (back-compatible API for tests/UI).
  String? get direction => meta[AttemptMeta.direction] as String?;
  String? get distractor => meta[AttemptMeta.distractor] as String?;

  Map<String, Object?> toJson() => <String, Object?>{
    'ts': ts,
    'item': itemId,
    if (itemType != ItemType.kana) 'type': itemType,
    'mode': mode,
    'correct': correct ? 1 : 0,
    if (rtMs != 0) 'rt': rtMs,
    'session': sessionId,
    if (meta.isNotEmpty) 'meta': meta,
  };
}
