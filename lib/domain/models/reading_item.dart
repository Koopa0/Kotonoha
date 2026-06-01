// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Something the learner reads in the reading practice — a single [Word] or a
/// short [Phrase]. The reading screen needs only these surfaces, so words and
/// phrases share one screen without the screen knowing which it has.
///
/// Pure data: no `package:flutter/*` imports.
abstract interface class ReadingItem {
  /// The kana as displayed (phrases keep their layout spaces).
  String get displayText;

  /// Canonical reading (romaji for a word; a spaced reading for a phrase).
  String get romaji;

  /// Meaning, in Traditional Chinese.
  String get meaning;

  /// Distinct kana characters this item is built from (whitespace excluded) —
  /// what the "readable with your unlocked kana" gate checks.
  Set<String> get characters;
}

/// Interest flavour for content, so practice can lean into what the learner
/// loves (ヨルシカ, anime, games, travel) without changing the mechanics.
enum ContentTheme { yorushika, anime, game, travel, daily }
