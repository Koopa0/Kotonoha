// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';

/// Harvests the practice units out of the sentence corpus: every distinct
/// (written run, reading) a sentence puts furigana on.
///
/// The corpus IS the curriculum. Nothing is drilled that the learner is not
/// also asked to read somewhere, and growing the corpus grows the kanji work
/// automatically — no second list to author, and no way for the two to drift.
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class KanjiUnits {
  /// Distinct units in corpus order, each carrying the first sentence it was
  /// found in as its teaching context.
  static List<KanjiUnit> fromPhrases(List<KanjiPhrase> phrases) {
    final byId = <String, KanjiUnit>{};
    for (final phrase in phrases) {
      for (final segment in phrase.segments) {
        if (!segment.isKanji) continue;
        final unit = KanjiUnit(
          written: segment.text,
          reading: segment.furigana!,
          example: phrase,
        );
        byId.putIfAbsent(unit.id, () => unit);
      }
    }
    return byId.values.toList();
  }

  /// Every sentence a unit appears in — the pool a review beat can draw a
  /// fresh context from instead of always showing the same sentence.
  static List<KanjiPhrase> examplesOf(
    KanjiUnit unit,
    List<KanjiPhrase> phrases,
  ) => [
    for (final phrase in phrases)
      if (phrase.segments.any(
        (s) =>
            s.isKanji && s.text == unit.written && s.furigana == unit.reading,
      ))
        phrase,
  ];
}

/// The corpus's units, harvested once. The corpus is const, so this can never
/// go stale — and the home would otherwise walk every segment of every
/// sentence on each rebuild.
final List<KanjiUnit> kKanjiUnits = KanjiUnits.fromPhrases(kKanjiPhrases);
