// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// One run of a kanji sentence: either plain kana (particles, okurigana) when
/// [furigana] is null, or a kanji that carries furigana + the reading id whose
/// SRS maturity decides whether the furigana still shows.
///
/// Pure data: no `package:flutter/*` imports.
class RubySegment {
  const RubySegment({required this.text, this.furigana, this.readingId});

  final String text; // 山 / を / 見 / る
  final String? furigana; // やま / null / み / null
  final String? readingId; // 'reading:山#やま' / null

  bool get isKanji => furigana != null;
}

/// A short sentence mixing kanji and kana — the reading bridge past pure-kana
/// phrases. Furigana over each kanji fades out as that reading is mastered, so
/// the same sentences become kana-free reading practice over time.
///
/// Pure data: no `package:flutter/*` imports.
class KanjiPhrase {
  const KanjiPhrase({
    required this.segments,
    required this.romaji,
    required this.meaning,
  });

  final List<RubySegment> segments;
  final String romaji; // 'yama o miru'
  final String meaning; // 看山

  /// The written form (kanji + kana), e.g. 山を見る.
  String get written => segments.map((s) => s.text).join();

  /// The full kana reading, e.g. やまをみる.
  String get reading => segments.map((s) => s.furigana ?? s.text).join();

  /// Non-kanji kana the learner must already know to read this (the kanji are
  /// furigana-supported, so they don't gate).
  Set<String> get plainKana => {
    for (final s in segments)
      if (!s.isKanji)
        for (final r in s.text.runes)
          if (r != 0x20) String.fromCharCode(r),
  };
}
