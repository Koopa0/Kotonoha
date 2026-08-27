// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/false_friend.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';

/// A short word the learner can read once they've unlocked its kana — the unit
/// of the contextual *reading* practice (glyph string → sound), one step past
/// single-kana recognition. Implements [ReadingItem] so it shares the reading
/// screen with [Phrase].
///
/// Pure data: no `package:flutter/*` imports.
class Word implements ReadingItem {
  const Word({
    required this.kana,
    required this.romaji,
    required this.meaning,
    this.script = KanaScript.hiragana,
    this.theme,
    this.falseFriend,
  });

  /// The word as written in kana, e.g. `いぬ` or `がっこう`. May use yōon,
  /// sokuon, chōonpu and small-vowel combinations — readability is decided per
  /// learning unit by `KanaTokenizer`.
  final String kana;

  /// Canonical Hepburn reading, e.g. `inu` / `gakkou` / `koohii`
  /// (shi/chi/tsu/fu/wo/n; sokuon doubles the next consonant, chōonpu repeats
  /// the previous vowel, ん before a vowel or y is n').
  @override
  final String romaji;

  /// Meaning, in Traditional Chinese (the learner's mother tongue).
  @override
  final String meaning;

  final KanaScript script;

  /// Optional interest flavour (ヨルシカ / anime / game / travel).
  final ContentTheme? theme;

  /// Optional 同形異義語 note — a gentle "the Japanese meaning is…" for a kanji
  /// the (Chinese-reading) learner already knows but that diverges in Japanese.
  final FalseFriend? falseFriend;

  @override
  String get displayText => kana;

  @override
  String get progressId => 'word:$kana';

  @override
  List<String> get gatingText => [kana];

  // Words carry no season (the seasonal corpus lives in the phrases); a word is
  // always "in season", so the lift never sinks it.
  @override
  Season? get season => null;
}
