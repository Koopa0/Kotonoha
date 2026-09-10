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

  /// True when [stemOf] uniquely selects [target]'s reading among [corpus]
  /// units that share the same written run. A collision means two taught
  /// readings would present the same visible sentence — that item must not
  /// be graded as a cold recall.
  static bool uniquelySelects(KanjiUnit target, Iterable<KanjiUnit> corpus) {
    final stem = stemOf(target);
    for (final other in corpus) {
      if (other.id == target.id) continue;
      if (other.written != target.written) continue;
      if (stemOf(other) == stem) return false;
    }
    return true;
  }
}
