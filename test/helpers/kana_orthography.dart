// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Dataset-integrity helpers: canonical romaji derivation and orthography
// validation for hand-typed kana content.
//
// The derivation guarantees a stored romaji matches the app's transcription
// RULES (shi/chi/tsu/fu/wo/n; sokuon doubles the next consonant, っち → tchi;
// chōonpu repeats the previous vowel; ん before a vowel or y is n'). It is an
// orthography check — it catches typos, not pronunciation or naturalness.

import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';

/// Common small-vowel loanword combinations and their canonical romaji. The
/// corpus may only use combinations from this table (a curated subset of the
/// 文化庁 外来語の表記 conventions).
const Map<String, String> kSmallVowelComboRomaji = {
  'ファ': 'fa',
  'フィ': 'fi',
  'フェ': 'fe',
  'フォ': 'fo',
  'ティ': 'ti',
  'ディ': 'di',
  'ウィ': 'wi',
  'ウェ': 'we',
  'ウォ': 'wo',
  'シェ': 'she',
  'ジェ': 'je',
  'チェ': 'che',
};

const _vowels = {'a', 'i', 'u', 'e', 'o'};

Map<String, String> _romajiMap(KanaScript script) => {
  for (final k in kAllKana)
    if (k.script == script) k.character: k.romaji,
};

/// The canonical romaji for [kana] under this app's transcription rules, or
/// null if a token has no defined transcription (which the orthography
/// validator reports separately).
String? deriveRomaji(String kana, KanaScript script) {
  final map = _romajiMap(script);
  final tokens = KanaTokenizer.tokenize(kana);
  String? tokenRomaji(String t) => map[t] ?? kSmallVowelComboRomaji[t];
  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == KanaTokenizer.sokuonHiragana ||
        t == KanaTokenizer.sokuonKatakana) {
      if (i + 1 >= tokens.length) return null;
      final next = tokenRomaji(tokens[i + 1]);
      if (next == null || next.isEmpty) return null;
      out.write(next.startsWith('ch') ? 't' : next[0]);
    } else if (t == KanaTokenizer.choonpu) {
      final soFar = out.toString();
      if (soFar.isEmpty || !_vowels.contains(soFar[soFar.length - 1])) {
        return null;
      }
      out.write(soFar[soFar.length - 1]);
    } else if (t == 'ん' || t == 'ン') {
      out.write('n');
      if (i + 1 < tokens.length) {
        final next = tokenRomaji(tokens[i + 1]);
        if (next != null &&
            next.isNotEmpty &&
            (_vowels.contains(next[0]) || next[0] == 'y')) {
          out.write("'");
        }
      }
    } else {
      final r = tokenRomaji(t);
      if (r == null) return null;
      out.write(r);
    }
  }
  return out.toString();
}

/// Orthography problems in [kana] for the given [script]; empty = clean.
/// Checks script-pure units, table-limited small-vowel combos, and the legal
/// environments of the special moras (no leading/trailing sokuon, no leading
/// chōonpu, chōonpu only after a lengthenable vowel, sokuon only before an
/// obstruent, chōonpu in katakana only).
List<String> validateKanaOrthography(String kana, KanaScript script) {
  final map = _romajiMap(script);
  final tokens = KanaTokenizer.tokenize(kana);
  final problems = <String>[];
  final sokuon = script == KanaScript.katakana
      ? KanaTokenizer.sokuonKatakana
      : KanaTokenizer.sokuonHiragana;
  final wrongSokuon = script == KanaScript.katakana
      ? KanaTokenizer.sokuonHiragana
      : KanaTokenizer.sokuonKatakana;
  if (tokens.isEmpty) return ['empty kana'];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == wrongSokuon) {
      problems.add('sokuon "$t" from the wrong script');
    } else if (t == sokuon) {
      if (i == 0) problems.add('leading sokuon');
      if (i + 1 >= tokens.length) {
        problems.add('trailing sokuon');
      } else {
        final next =
            map[tokens[i + 1]] ?? kSmallVowelComboRomaji[tokens[i + 1]];
        const geminable = {
          'k',
          's',
          't',
          'c',
          'p',
          'd',
          'g',
          'b',
          'z',
          'f',
          'h',
          'j',
        };
        if (next == null || next.isEmpty || !geminable.contains(next[0])) {
          problems.add(
            'sokuon before non-geminable "${tokens.length > i + 1 ? tokens[i + 1] : ''}"',
          );
        }
      }
    } else if (t == KanaTokenizer.choonpu) {
      if (script != KanaScript.katakana) {
        problems.add('chōonpu in a hiragana item');
      }
      if (i == 0) {
        problems.add('leading chōonpu');
      } else {
        final prev = tokens[i - 1];
        final prevRomaji = map[prev] ?? kSmallVowelComboRomaji[prev];
        if (prevRomaji == null ||
            prevRomaji.isEmpty ||
            !_vowels.contains(prevRomaji[prevRomaji.length - 1])) {
          problems.add('chōonpu after non-vowel "$prev"');
        }
      }
    } else if (t.runes.length > 1) {
      // A combined token: either a yōon unit of this script, or a small-vowel
      // combo from the curated table.
      final isUnit = map.containsKey(t);
      final isCombo = kSmallVowelComboRomaji.containsKey(t);
      if (!isUnit && !isCombo) {
        problems.add('unknown combination "$t"');
      }
      if (isCombo && script != KanaScript.katakana) {
        problems.add('small-vowel combo "$t" in a hiragana item');
      }
    } else if (!map.containsKey(t)) {
      problems.add('"$t" is not a $script kana unit');
    }
  }
  return problems;
}
