// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_reading_quiz.dart';

/// The Japanese stem a recall beat shows *before* the learner answers.
///
/// A written run alone (日) is not a question when another taught reading
/// is legal in the same *word*. 帰国の日 selects ひ (にち is not a reading
/// of that word). 毎年の秋 does not: the inventory itself lists まいねん
/// for 年【ネン】, and まいとし is what the corpus harvested — both are
/// legal, so comparing first-example *sentences* (三年住みます vs 毎年の秋)
/// cannot prove uniqueness.
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class KanjiPrompt {
  /// Particles and case markers — trailing kana after a kanji run that is
  /// not okurigana. Exact segment match; 「ますか」 is not a particle.
  static const Set<String> _particles = {
    'を',
    'が',
    'の',
    'に',
    'で',
    'と',
    'へ',
    'は',
    'も',
    'から',
    'まで',
    'より',
    'など',
    'か',
    'ね',
    'よ',
    'な',
  };

  /// The full written sentence the unit was harvested from.
  static String stemOf(KanjiUnit unit) => unit.example.written;

  /// Index of the target run inside [unit.example.segments], or -1.
  /// 手話で話す has two 話; the mark is which one is being asked.
  static int markedIndex(KanjiUnit unit) {
    for (var i = 0; i < unit.example.segments.length; i++) {
      final s = unit.example.segments[i];
      if (s.text == unit.written && s.furigana == unit.reading) return i;
    }
    return -1;
  }

  /// The local word around the mark: consecutive kanji plus okurigana
  /// (手話 / 話す / 毎年 / 来る). Particles after the run are excluded.
  static String localWord(KanjiUnit unit) {
    final mark = markedIndex(unit);
    if (mark < 0) return unit.written;
    return localWordAt(unit.example, mark);
  }

  /// Local word at a kanji segment index of [phrase].
  static String localWordAt(KanjiPhrase phrase, int index) {
    final segs = phrase.segments;
    if (index < 0 || index >= segs.length) return '';
    final buffer = StringBuffer();
    var lastKanji = index;
    if (index > 0 && segs[index - 1].isKanji) {
      // Second character of a compound: 毎年 / 三年 / 手話.
      buffer.write(segs[index - 1].text);
      buffer.write(segs[index].text);
    } else {
      // First character: take one following kanji (日本 / 会社 / 来週)
      // and not a later verb (三年住みます stays 三年 because 年 is second).
      buffer.write(segs[index].text);
      if (index + 1 < segs.length && segs[index + 1].isKanji) {
        buffer.write(segs[index + 1].text);
        lastKanji = index + 1;
      }
    }
    for (var i = lastKanji + 1; i < segs.length; i++) {
      if (segs[i].isKanji) break;
      if (_particles.contains(segs[i].text)) break;
      buffer.write(segs[i].text);
    }
    return buffer.toString();
  }

  /// Taught readings that are legal for [target.written] in [target]'s
  /// local word — corpus attestation of that same word, plus inventory
  /// example-words that the local word can spell with that reading.
  ///
  /// Always includes [target.reading]. 毎年 → {とし, ねん}; 帰国の日 → {ひ}.
  static Set<String> validReadings(
    KanjiUnit target, {
    List<KanjiPhrase>? phrases,
    List<KanjiEntry>? inventory,
  }) {
    final pool = phrases ?? kKanjiPhrases;
    final entries = inventory ?? kKanji;
    final valid = <String>{target.reading};
    final word = localWord(target);
    if (word.isEmpty) return valid;

    for (final phrase in pool) {
      for (var i = 0; i < phrase.segments.length; i++) {
        final s = phrase.segments[i];
        if (!s.isKanji || s.text != target.written) continue;
        if (localWordAt(phrase, i) == word) {
          valid.add(s.furigana!);
        }
      }
    }

    for (final constructed in _inventoryAttested(target, word, entries)) {
      valid.add(constructed);
    }
    return valid;
  }

  /// True when [validReadings] is a singleton — the visible word selects
  /// one taught answer. Sentence-string inequality is not enough.
  static bool uniquelySelects(
    KanjiUnit target, {
    List<KanjiPhrase>? phrases,
    List<KanjiEntry>? inventory,
  }) =>
      validReadings(target, phrases: phrases, inventory: inventory).length == 1;

  /// Readings of [target.written] whose inventory example-word is a
  /// possible spelling of [localWord] when that reading is used there.
  static Iterable<String> _inventoryAttested(
    KanjiUnit target,
    String localWord,
    List<KanjiEntry> inventory,
  ) sync* {
    final entry = _entryFor(target.written, inventory);
    if (entry == null) return;
    for (final reading in entry.readings) {
      final kana = KanjiReadingQuiz.hiraganaOf(reading.text);
      final example = reading.exampleWord;
      if (example == null) continue;
      final want = KanjiReadingQuiz.hiraganaOf(example);
      for (final spelled in _spellings(
        localWord,
        target.written,
        kana,
        inventory,
      )) {
        if (spelled == want) {
          yield kana;
          break;
        }
      }
    }
  }

  static KanjiEntry? _entryFor(String written, List<KanjiEntry> inventory) {
    for (final e in inventory) {
      if (e.char == written) return e;
    }
    return null;
  }

  /// Ways to read [word]'s kanji, forcing [written] to [reading] and
  /// leaving trailing kana (okurigana) untouched.
  static List<String> _spellings(
    String word,
    String written,
    String reading,
    List<KanjiEntry> inventory,
  ) {
    var built = <String>[''];
    var i = 0;
    final units = word.runes.toList();
    while (i < units.length) {
      final ch = String.fromCharCode(units[i]);
      if (ch == written) {
        built = [for (final prefix in built) prefix + reading];
        i++;
        continue;
      }
      final entry = _entryFor(ch, inventory);
      if (entry != null && entry.readings.isNotEmpty) {
        built = [
          for (final prefix in built)
            for (final r in entry.readings)
              prefix + KanjiReadingQuiz.hiraganaOf(r.text),
        ];
        i++;
        continue;
      }
      // Plain kana (okurigana): append as written.
      built = [for (final prefix in built) prefix + ch];
      i++;
    }
    if (built.length > 32) {
      return built.sublist(0, 32);
    }
    return built;
  }
}
