// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
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
  final int Function(String readingId) srsLevelOf;
  final double fontSize;

  /// Full furigana while a reading is new, faint while learning, gone once known.
  static double furiganaOpacity(int srsLevel) {
    if (srsLevel <= 1) return 1;
    if (srsLevel <= 3) return 0.42;
    return 0;
  }

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
                        opacity: furiganaOpacity(srsLevelOf(s.readingId!)),
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
