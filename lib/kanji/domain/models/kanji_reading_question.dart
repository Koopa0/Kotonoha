// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';

/// One "how is this read?" recall question — the honest test beat for the
/// kanji track. The prompt is the written word with NO gloss, so a
/// 漢字-literate reader cannot let the meaning he already owns stand in for the
/// sound he has to produce. [options] are kana readings; exactly one is right,
/// and the wrong ones are the readings a character-by-character guess would
/// produce (see `KanjiReadingQuiz`).
///
/// Pure data: no `package:flutter/*` imports.
class KanjiReadingQuestion {
  const KanjiReadingQuestion({
    required this.unit,
    required this.options,
    required this.correctIndex,
  });

  final KanjiUnit unit;

  /// Kana reading texts; [correctIndex] points at the answer.
  final List<String> options;
  final int correctIndex;

  String get answer => unit.reading;
  String get unitId => unit.id;
}
