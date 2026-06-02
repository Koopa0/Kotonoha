// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/false_friend.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/reading_item.dart';

/// A short word the learner can read once they've unlocked its kana — the unit
/// of the contextual *reading* practice (glyph string → sound), one step past
/// single-kana recognition. Implements [ReadingItem] so it shares the reading
/// screen with [Phrase].
///
/// Pure data: no `package:flutter/*` imports.
class Word implements ReadingItem {
  const Word({
    required this.kana,
    required this.romaji,
    required this.meaning,
    this.script = KanaScript.hiragana,
    this.theme,
    this.falseFriend,
  });

  /// The word as written in kana, e.g. `いぬ`.
  final String kana;

  /// Canonical Hepburn reading, e.g. `inu` (shi/chi/tsu/fu/wo/n).
  @override
  final String romaji;

  /// Meaning, in Traditional Chinese (the learner's mother tongue).
  @override
  final String meaning;

  final KanaScript script;

  /// Optional interest flavour (ヨルシカ / anime / game / travel).
  final ContentTheme? theme;

  /// Optional 同形異義語 note — a gentle "the Japanese meaning is…" for a kanji
  /// the (Chinese-reading) learner already knows but that diverges in Japanese.
  final FalseFriend? falseFriend;

  @override
  String get displayText => kana;

  /// The distinct kana characters this word is built from. Single-codepoint per
  /// character (the dataset avoids yōon so each rune is one kana unit), which is
  /// what gating against the learner's unlocked kana relies on.
  @override
  Set<String> get characters => {
    for (final r in kana.runes) String.fromCharCode(r),
  };
}
