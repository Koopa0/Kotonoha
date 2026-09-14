// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/use_cases/furigana_support.dart';
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

  /// The fade rule is [FuriganaSupport.opacity] — a learning rule, kept in
  /// the domain so the sentence ViewModel can read it without this widget.
  static double furiganaOpacity(int srsLevel) =>
      FuriganaSupport.opacity(srsLevel);

  /// True when any kanji run still shows furigana — the sentence already
  /// offered a reading, so a later「讀得出來」is not an independent recall.
  static bool hasVisibleReadingSupport(
    KanjiPhrase phrase,
    int Function(String unitId) srsLevelOf,
  ) => FuriganaSupport.hasVisibleReadingSupport(phrase, srsLevelOf);

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
