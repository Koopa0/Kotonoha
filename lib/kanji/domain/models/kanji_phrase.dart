// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';

/// One run of a sentence: either plain kana (particles, okurigana) when
/// [furigana] is null, or a kanji that carries furigana.
///
/// [readingId] is set only when that kanji-with-that-reading is part of the
/// kanji curriculum (`kKanji`). A kanji the curriculum has not reached yet
/// carries furigana with NO reading id — and keeps it at full strength
/// forever, until the reading is actually taught. That is what lets the
/// sentence corpus be written in natural Japanese without waiting for the
/// kanji dataset to catch up: unknown kanji are simply always supported.
///
/// Pure data: no `package:flutter/*` imports.
class RubySegment {
  const RubySegment({required this.text, this.furigana, this.readingId});

  final String text; // 山 / を / 見 / る
  final String? furigana; // やま / null / み / null
  final String? readingId; // 'reading:山#やま' / null when not yet taught

  bool get isKanji => furigana != null;

  /// Whether this kanji's furigana can ever fade (its reading is in the
  /// curriculum). A segment without one is permanently supported.
  bool get fades => furigana != null && readingId != null;
}

/// A sentence mixing kanji and kana — real written Japanese, and the home of
/// the grammar-pattern spine. Furigana over a kanji fades out as that reading
/// matures in 漢字の声, so the same sentences shed their training wheels one
/// reading at a time.
///
/// Implements [ReadingItem] so it shares one schedule, one session composer
/// and one readability gate with words and kana phrases — only its
/// [gatingText] differs (okurigana and particles gate; the kanji do not).
///
/// Pure data: no `package:flutter/*` imports.
class KanjiPhrase implements ReadingItem {
  const KanjiPhrase({
    required this.segments,
    required this.romaji,
    required this.meaning,
  });

  final List<RubySegment> segments;

  @override
  final String romaji; // 'yama o miru'

  @override
  final String meaning; // 看山

  /// The written form (kanji + kana), e.g. 山を見る.
  String get written => segments.map((s) => s.text).join();

  /// The full kana reading, e.g. やまをみる.
  String get reading => segments.map((s) => s.furigana ?? s.text).join();

  @override
  String get displayText => written;

  @override
  String get progressId => 'sentence:$written';

  /// Sentences carry no season (the seasonal corpus lives in the kana phrases).
  @override
  Season? get season => null;

  /// The non-kanji stretches, one string per plain segment. Each must be
  /// independently readable — a chōonpu never leans across a kanji boundary.
  @override
  List<String> get gatingText => [
    for (final s in segments)
      if (!s.isKanji) s.text,
  ];
}
