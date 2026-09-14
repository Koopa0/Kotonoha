// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// The furigana fade rule: how much reading support a kanji run still shows
/// at a given per-reading SRS level, and whether a sentence therefore hands
/// the learner a reading before he commits. A learning rule, not paint —
/// `RubyText` renders the opacity, the sentence ViewModel reads the support
/// to decide whether a 「讀得出來」 was independent.
///
/// Pure data: no `package:flutter/*` imports.
abstract final class FuriganaSupport {
  /// Full furigana while a reading is new, thinning as it matures, and GONE
  /// once it reaches [ReadingStat.kFuriganaFadeLevel] — a level every reading
  /// reaches by correct (untimed) recall alone. Bound to that named constant
  /// on purpose: the terminal fade was once gated one step ABOVE the
  /// reachable ceiling, so it never completed in real play (furigana froze
  /// half-faded). The SCHEDULE now climbs past the fade level (to
  /// [ReadingStat.kMaxLevel]) without moving it.
  ///
  /// An unpractised unit has no stat and so level 0: full support. The app
  /// never fades a reading it has not actually drilled.
  static double opacity(int srsLevel) {
    if (srsLevel >= ReadingStat.kFuriganaFadeLevel) {
      return 0; // known — the support comes off (was once unreachable)
    }
    if (srsLevel <= 0) return 1; // brand new — full support
    if (srsLevel == 1) return 0.7; // first recalls — thinning
    return 0.4; // one below the cap — faint
  }

  /// True when any kanji run still shows furigana — the sentence already
  /// offered a reading, so a later「讀得出來」is not an independent recall.
  static bool hasVisibleReadingSupport(
    KanjiPhrase phrase,
    int Function(String unitId) srsLevelOf,
  ) {
    return phrase.segments.any(
      (s) => s.isKanji && opacity(srsLevelOf(s.unitId!)) > 0,
    );
  }
}
