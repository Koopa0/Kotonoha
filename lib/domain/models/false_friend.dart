// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// A 同形異義語 — a word whose kanji a Chinese reader already knows, but which
/// means something different in Japanese. Carried optionally by a [Word] so the
/// reading screen can offer a gentle, on-demand "the Japanese meaning is…" note
/// that affirms the reader's existing literacy — never a scary warning.
///
/// Pure data: no `package:flutter/*` imports.
class FalseFriend {
  const FalseFriend({
    required this.kanji,
    required this.jaMeaning,
    required this.zhNote,
  });

  /// The shared kanji form, e.g. `手紙`.
  final String kanji;

  /// What it means in Japanese, glossed in Traditional Chinese (e.g. `信`).
  final String jaMeaning;

  /// One gentle 繁中 clause on the misleading Chinese association — soft, never
  /// alarmed (e.g. `中文直覺的「廁紙」,日文是別的詞。`).
  final String zhNote;
}
