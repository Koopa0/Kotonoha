// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';

/// The Japanese stem a recall beat shows *before* the learner answers.
///
/// A written run alone (日) is not a question when the corpus already taught
/// another reading of the same run (にち). The example sentence — 帰国の日 vs
/// 毎日歩く — plus a mark on the target run is what makes one answer the
/// answer. The reading itself stays off the stem; a gloss is not a substitute.
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class KanjiPrompt {
  /// The full written sentence the unit was harvested from.
  static String stemOf(KanjiUnit unit) => unit.example.written;

  /// Index of the target run inside [unit.example.segments], or -1.
  /// 手話で話す has two 話; the mark is which one is being asked.
  static int markedIndex(KanjiUnit unit) {
    for (var i = 0; i < unit.example.segments.length; i++) {
      final s = unit.example.segments[i];
      if (s.text == unit.written && s.furigana == unit.reading) return i;
    }
    return -1;
  }

  /// True when the visible stem plus the marked run uniquely selects
  /// [target]'s reading among [corpus] units that share the same written
  /// run. Same sentence + same mark for two readings cannot be graded.
  static bool uniquelySelects(KanjiUnit target, Iterable<KanjiUnit> corpus) {
    final stem = stemOf(target);
    final mark = markedIndex(target);
    for (final other in corpus) {
      if (other.id == target.id) continue;
      if (other.written != target.written) continue;
      if (stemOf(other) != stem) continue;
      if (markedIndex(other) == mark) return false;
    }
    return true;
  }
}
