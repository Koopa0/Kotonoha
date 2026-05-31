// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';

/// Which way a question is asked.
enum QuizDirection {
  /// Show the kana glyph, choose its romaji.
  kanaToRomaji,

  /// Show the romaji, choose the kana glyph.
  romajiToKana,

  /// Play the sound, choose the kana glyph (listening practice — no text cue).
  soundToKana,
}

/// A single multiple-choice question: a prompt and four options, exactly one
/// of which is correct.
///
/// Pure data: no `package:flutter/*` imports.
class QuizQuestion {
  const QuizQuestion({
    required this.target,
    required this.direction,
    required this.options,
    required this.correctIndex,
  });

  /// The kana being tested.
  final Kana target;
  final QuizDirection direction;

  /// Four option strings (romaji or kana depending on [direction]).
  final List<String> options;
  final int correctIndex;

  /// The text that represents the question (the glyph for kana/sound prompts,
  /// the romaji for romaji prompts). For [QuizDirection.soundToKana] the UI
  /// plays this rather than showing it.
  String get prompt => switch (direction) {
    QuizDirection.romajiToKana => target.romaji,
    QuizDirection.kanaToRomaji || QuizDirection.soundToKana => target.character,
  };

  /// The correct option text.
  String get correctAnswer => options[correctIndex];

  bool isCorrect(int selectedIndex) => selectedIndex == correctIndex;
}
