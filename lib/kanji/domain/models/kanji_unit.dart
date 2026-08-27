// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';

/// One thing the learner actually retrieves when reading: a written run and the
/// sound it makes THERE — 学校【がっこう】, 今日【きょう】, 見【み】(in 見る).
///
/// This, not the bare kanji, is the unit of both practice and the furigana
/// fade, because a reading is a property of the WORD, not of the character:
///
///  * 学校 is がっこう, which is not 学【がく】 + 校【こう】 — a per-character
///    model cannot even spell it, which is why sound-changing compounds
///    (学校・切符・出発・一緒) were structurally absent from the corpus.
///  * 今日 is きょう and 一人 is ひとり — nothing about 日【にち】 or 人【ひと】
///    gets you there.
///  * Knowing 先生【せんせい】 says nothing about 学生【がくせい】, though a
///    per-character model would fade the 生 in both.
///
/// Units are HARVESTED from the sentence corpus rather than listed separately
/// (see `KanjiUnits`), so the app can only ever drill a reading it actually
/// asks the learner to read, and the corpus stays the single source of truth.
///
/// Pure data: no `package:flutter/*` imports.
class KanjiUnit {
  const KanjiUnit({
    required this.written,
    required this.reading,
    required this.example,
  });

  /// The kanji run as written: 学校 / 見 / 今日.
  final String written;

  /// Its reading in this word, in hiragana: がっこう / み / きょう.
  final String reading;

  /// A sentence from the corpus containing it — the context the teach beat
  /// shows, so a reading is never met stripped of the word it lives in.
  final KanjiPhrase example;

  /// Stable scheduling/analytics id.
  String get id => idFor(written, reading);

  static String idFor(String written, String reading) =>
      RubySegment.unitIdFor(written, reading);

  /// The individual kanji making up [written] — what distractor generation
  /// consults the curriculum inventory about.
  List<String> get chars => [
    for (final r in written.runes) String.fromCharCode(r),
  ];
}
