// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';

/// One run of a sentence: either plain kana (particles, okurigana, punctuation)
/// when [furigana] is null, or a kanji run that carries furigana.
///
/// A kanji run may be more than one character — 学校【がっこう】, 今日【きょう】,
/// 一人【ひとり】 — and that is deliberate: those readings belong to the WORD and
/// cannot be spelled character by character (がっ is no reading of 学). The run
/// plus its furigana IS the practice unit ([unitId], see `KanjiUnit`), so what
/// fades is exactly what was drilled.
///
/// Pure data: no `package:flutter/*` imports.
class RubySegment {
  const RubySegment({required this.text, this.furigana});

  final String text; // 山 / を / 学校 / る
  final String? furigana; // やま / null / がっこう / null

  bool get isKanji => furigana != null;

  /// The practice unit this run belongs to, or null for plain kana. Derived,
  /// never stored: a segment cannot disagree with the unit it teaches.
  String? get unitId => furigana == null ? null : unitIdFor(text, furigana!);

  /// The one place the unit-id format lives. `KanjiUnit` reads it from here so
  /// the written form and its practice id can never drift apart.
  static String unitIdFor(String written, String reading) =>
      'unit:$written#$reading';
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
