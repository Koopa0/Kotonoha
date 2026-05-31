// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';

/// A short word the learner can read once they've unlocked its kana — the unit
/// of the contextual *reading* practice (glyph string → sound), one step past
/// single-kana recognition.
///
/// Pure data: no `package:flutter/*` imports.
class Word {
  const Word({
    required this.kana,
    required this.romaji,
    required this.meaning,
    this.script = KanaScript.hiragana,
  });

  /// The word as written in kana, e.g. `いぬ`.
  final String kana;

  /// Canonical Hepburn reading, e.g. `inu` (shi/chi/tsu/fu/wo/n).
  final String romaji;

  /// Meaning, in Traditional Chinese (the learner's mother tongue).
  final String meaning;

  final KanaScript script;

  /// The distinct kana characters this word is built from. Single-codepoint per
  /// character (the dataset avoids yōon so each rune is one kana unit), which is
  /// what gating against the learner's unlocked kana relies on.
  Set<String> get characters => {
    for (final r in kana.runes) String.fromCharCode(r),
  };
}
