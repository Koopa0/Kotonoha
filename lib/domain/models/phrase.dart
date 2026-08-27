// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';

/// A short readable phrase — the sentence-level reading unit. Unlike [Word],
/// its [romaji] is a free reading (particles read は→wa, を→o; spaces mark word
/// boundaries) and is NOT a literal kana-by-kana transcription, so phrases are a
/// separate type rather than spaced [Word]s.
///
/// Pure data: no `package:flutter/*` imports.
class Phrase implements ReadingItem {
  const Phrase({
    required this.kana,
    required this.romaji,
    required this.meaning,
    this.season,
  });

  /// The phrase in kana, with layout spaces at word boundaries (うみが みえる).
  final String kana;

  @override
  final String romaji;

  @override
  final String meaning;

  /// The season this phrase evokes (null = season-neutral). Drives the silent
  /// seasonal-lift; never displayed.
  @override
  final Season? season;

  @override
  String get displayText => kana;

  @override
  String get progressId => 'phrase:$kana';
}
