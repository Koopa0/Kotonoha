// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Curated groups of visually look-alike hiragana, used to build a
/// discrimination drill whose distractors come from the same group (so the
/// learner can't pass by elimination — desirable difficulty).
///
/// Pure data: no `package:flutter/*` imports.
/// Flat set of every kana that appears in a confusable group — used to halve
/// the SRS interval for hard-to-tell-apart kana.
final Set<String> kConfusableChars = {
  for (final set in kConfusableSets) ...set,
};

const List<List<String>> kConfusableSets = [
  ['あ', 'お'],
  ['い', 'り'],
  ['き', 'さ'],
  ['く', 'へ'],
  ['け', 'は', 'ほ'],
  ['さ', 'ち'],
  ['す', 'む'],
  ['ぬ', 'め'],
  ['ね', 'れ', 'わ'],
  ['は', 'ほ', 'ま'],
  ['る', 'ろ'],
  ['そ', 'ろ'],
  ['つ', 'し'],
  ['こ', 'に'],
];
