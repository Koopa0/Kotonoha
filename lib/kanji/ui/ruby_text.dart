// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// Renders a [KanjiPhrase] with furigana above each kanji — and fades that
/// furigana out as the reading's SRS level climbs ([srsLevelOf]). The training
/// wheels come off one reading at a time.
class RubyText extends StatelessWidget {
  const RubyText({
    required this.phrase,
    required this.srsLevelOf,
    this.fontSize = 40,
    super.key,
  });

  final KanjiPhrase phrase;
  final int Function(String unitId) srsLevelOf;
  final double fontSize;

  /// Full furigana while a reading is new, thinning as it matures, and GONE once
  /// it reaches [ReadingStat.kFuriganaFadeLevel] — a level every reading reaches
  /// by correct (untimed) recall alone. Bound to that named constant on purpose:
  /// the terminal fade was once gated one step ABOVE the reachable ceiling, so it
  /// never completed in real play (furigana froze half-faded). The SCHEDULE now
  /// climbs past the fade level (to [ReadingStat.kMaxLevel]) without moving it.
  ///
  /// An unpractised unit has no stat and so level 0: full support. The app
  /// never fades a reading it has not actually drilled.
  static double furiganaOpacity(int srsLevel) {
    if (srsLevel >= ReadingStat.kFuriganaFadeLevel) {
      return 0; // known — the support comes off (was once unreachable)
    }
    if (srsLevel <= 0) return 1; // brand new — full support
    if (srsLevel == 1) return 0.7; // first recalls — thinning
    return 0.4; // one below the cap — faint
  }

  /// The maturity of the practice unit this run belongs to — the word, not the
  /// character, so 学校 fades as 学校 and knowing 先生 fades nothing in 学生.
  double _opacityFor(RubySegment s) => furiganaOpacity(srsLevelOf(s.unitId!));

  @override
  Widget build(BuildContext context) {
    final furiSize = fontSize * 0.36;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final s in phrase.segments)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: furiSize * 1.4,
                child: s.isKanji
                    ? Opacity(
                        opacity: _opacityFor(s),
                        child: Text(
                          s.furigana!,
                          style: TextStyle(
                            fontSize: furiSize,
                            height: 1,
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    : null,
              ),
              Text(
                s.text,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
