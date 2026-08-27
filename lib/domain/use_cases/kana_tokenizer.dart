// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Splits kana text into LEARNING UNITS and decides readability against the
/// learner's unlocked kana — the one place that knows which characters are
/// units of their own and which only modify a neighbour.
///
/// Tokens and their readability rules:
///
///  - a small-character combination (yōon きゃ/シュ, or a small-vowel loanword
///    combination ファ/ティ/ウィ …) is ONE token — the small character never
///    stands alone, it reshapes the kana before it:
///     * a yōon digraph is readable iff that two-character unit itself is a
///       learned unit (きゃ-style digraphs are units of the kana dataset);
///     * a small-VOWEL combination is readable iff its base kana AND the
///       full-size vowel are both learned (ファ ← フ + ア): the sound is the
///       predictable base-consonant + vowel, so nothing new is taught by it;
///  - っ/ッ (sokuon) is its own token, readable once つ/ツ is learned — a
///    length convention on a shape the learner already knows, never a unit
///    taught by itself;
///  - ー (chōonpu) is its own token, readable when whatever precedes it is —
///    it has no sound of its own, it stretches the previous vowel;
///  - every other rune is a token readable iff it is itself a learned unit
///    (a `Kana.character` id).
///
/// Layout spaces are dropped. Pure logic: no `package:flutter/*` imports.
abstract final class KanaTokenizer {
  static const String sokuonHiragana = 'っ';
  static const String sokuonKatakana = 'ッ';
  static const String choonpu = 'ー';

  /// Small characters that attach to the kana before them (never stand alone).
  static const Set<String> _small = {
    // Yōon.
    'ゃ', 'ゅ', 'ょ', 'ャ', 'ュ', 'ョ',
    // Small vowels (loanword combinations: ファ, ティ, ウィ …).
    'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ', 'ァ', 'ィ', 'ゥ', 'ェ', 'ォ',
    // Small wa (rare, kept for completeness).
    'ゎ', 'ヮ',
  };

  /// Small vowel → its full-size counterpart (the shape whose sound it lends).
  static const Map<String, String> _fullSizeVowel = {
    'ぁ': 'あ',
    'ぃ': 'い',
    'ぅ': 'う',
    'ぇ': 'え',
    'ぉ': 'お',
    'ァ': 'ア',
    'ィ': 'イ',
    'ゥ': 'ウ',
    'ェ': 'エ',
    'ォ': 'オ',
    'ゎ': 'わ',
    'ヮ': 'ワ',
  };

  /// Japanese punctuation: read as pauses and quote marks, never sounded, so
  /// it is not a learning unit and never gates a sentence. It must ride along
  /// inside a plain-kana segment (`んで、`), never sit in a segment of its own.
  static const Set<String> _punctuation = {'、', '。', '「', '」', '・', '？', '！'};

  /// [kana] split into learning-unit tokens; layout spaces and punctuation
  /// removed.
  static List<String> tokenize(String kana) {
    final tokens = <String>[];
    for (final rune in kana.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == ' ' || ch == '　' || _punctuation.contains(ch)) continue;
      if (_small.contains(ch) && tokens.isNotEmpty) {
        tokens[tokens.length - 1] = tokens.last + ch;
        continue;
      }
      tokens.add(ch);
    }
    return tokens;
  }

  /// Whether every token of [kana] is readable given [learnedChars] (the set
  /// of learned `Kana.character` ids). Empty text reads as nothing → false.
  static bool isReadable(String kana, Set<String> learnedChars) {
    final tokens = tokenize(kana);
    if (tokens.isEmpty) return false;
    for (var i = 0; i < tokens.length; i++) {
      if (!_tokenReadable(tokens[i], atStart: i == 0, learnedChars)) {
        return false;
      }
    }
    return true;
  }

  static bool _tokenReadable(
    String token,
    Set<String> learnedChars, {
    required bool atStart,
  }) {
    if (token == sokuonHiragana) return learnedChars.contains('つ');
    if (token == sokuonKatakana) return learnedChars.contains('ツ');
    // A chōonpu stretches what came before it; by the time we reach it every
    // earlier token has already proven readable, so it only needs a "before".
    if (token == choonpu) return !atStart;
    final runes = token.runes.toList();
    if (runes.length == 1) return learnedChars.contains(token);
    if (runes.length > 2) return false;
    final smallVowelFull = _fullSizeVowel[String.fromCharCode(runes[1])];
    if (smallVowelFull != null) {
      final base = String.fromCharCode(runes[0]);
      return learnedChars.contains(base) &&
          learnedChars.contains(smallVowelFull);
    }
    // Yōon digraph: the two-character unit is itself the learnable thing.
    return learnedChars.contains(token);
  }
}
