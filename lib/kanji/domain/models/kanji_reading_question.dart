// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';

/// One "choose the reading" recall question — the honest test beat for the
/// kanji track. The prompt is the kanji + its on/kun kind (NO meaning gloss,
/// so a 漢字-literate reader can't let the meaning he already owns stand in for
/// the reading he must recall). [options] are kana readings; exactly one is the
/// answer. Distractors are real readings of OTHER kanji of the same kind.
///
/// Pure data: no `package:flutter/*` imports.
class KanjiReadingQuestion {
  const KanjiReadingQuestion({
    required this.entry,
    required this.reading,
    required this.options,
    required this.correctIndex,
  });

  final KanjiEntry entry;
  final Reading reading;

  /// Kana reading texts; [correctIndex] points at the answer.
  final List<String> options;
  final int correctIndex;

  String get answer => reading.text;
  String get readingId => KanjiEntry.readingId(entry.char, reading.text);
}
