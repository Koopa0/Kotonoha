// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// The writing system a [Kana] belongs to.
///
/// Both scripts are fully populated and live: each is a complete syllabary in
/// the dataset, taught by 手解き and shown throughout the UI.
enum KanaScript { hiragana, katakana }

/// The orthography variant of a kana. [seion] = base gojūon (default, so every
/// existing `Kana(...)` literal and all saved data are unaffected). dakuon = ゛
/// (が…), handakuon = ゜ (ぱ…), yoon = contracted 2-codepoint (きゃ…).
enum KanaKind { seion, dakuon, handakuon, yoon }

/// A single kana with its canonical Hepburn romaji and gojūon grid position.
///
/// Pure data: this file must not import `package:flutter/*`.
class Kana {
  const Kana({
    required this.character,
    required this.romaji,
    required this.row,
    required this.column,
    this.script = KanaScript.hiragana,
    this.kind = KanaKind.seion,
  });

  /// The kana glyph, e.g. `し`.
  final String character;

  /// Single canonical Hepburn romaji, e.g. `shi`.
  final String romaji;

  /// Gojūon row index for seion/dakuon/handakuon; -1 for yoon (no grid cell).
  final int row;

  /// Gojūon column index (vowel): 0=a,1=i,2=u,3=e,4=o; -1 for yoon.
  final int column;

  final KanaScript script;
  final KanaKind kind;

  /// Stable identity key used for persistence and stats lookup.
  String get id => character;

  /// True for base gojūon kana (the only ones the 11×5 grid can render).
  bool get isGojuon => kind == KanaKind.seion;

  @override
  bool operator ==(Object other) =>
      other is Kana && other.character == character && other.script == script;

  @override
  int get hashCode => Object.hash(character, script);

  @override
  String toString() => 'Kana($character/$romaji)';
}
