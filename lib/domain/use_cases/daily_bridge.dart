// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

/// After a daily kana run, picks at most one already-met word and one readable
/// sentence that reuse a session kana — the transfer check: can the glyph still
/// be read inside a word, then inside a new sentence?
///
/// Gates (deliberately narrower than 渡し舟 / 黙読 intake):
///  - every token must pass [KanaTokenizer] against learned kana;
///  - a word is only tested if ferry (or another cold mode) has already met it
///    — introduction is not a transfer test, and unseen words are never
///    cold-produced here;
///  - a brand-new sentence may board as the "new short sentence" once its
///    kana are readable and a seen word is already in the chain;
///  - [excludeProgressIds] keeps 「もう一回」 from mechanically replaying the
///    same word/sentence batch.
///
/// Pure logic, deterministic under an injected [Random].
abstract final class DailyBridge {
  static const int kMaxWords = 1;
  static const int kMaxPhrases = 1;

  static const Set<String> _particles = {
    'は',
    'が',
    'を',
    'に',
    'で',
    'と',
    'も',
    'へ',
    'や',
    'の',
    'な',
  };

  static List<ReadingItem> compose({
    required List<Kana> sessionKana,
    required List<Word> words,
    required List<Phrase> phrases,
    required Set<String> learnedChars,
    required Map<String, WordStat> wordStats,
    required DateTime now,
    required Random rng,
    Map<String, KanaStat> kanaStats = const {},
    Set<String> excludeProgressIds = const {},
  }) {
    if (sessionKana.isEmpty) return const [];

    final readableWords = ReadingSet.readable(
      words,
      learnedChars,
    ).where((w) => !excludeProgressIds.contains(w.progressId)).toList();
    final readablePhrases = ReadingSet.readable(
      phrases,
      learnedChars,
    ).where((p) => !excludeProgressIds.contains(p.progressId)).toList();

    WordStat statOf(ReadingItem item) =>
        wordStats[item.progressId] ?? const WordStat();

    final seenWords = readableWords.where((w) => statOf(w).isSeen).toList();
    if (seenWords.isEmpty) return const [];

    final orderedKana = _orderBridgeKana(sessionKana, kanaStats, now, rng);
    Word? word;
    for (final k in orderedKana) {
      final matches = seenWords.where((w) => containsUnit(w.kana, k.character));
      if (matches.isEmpty) continue;
      word = _pickPreferred(matches.toList(), rng);
      break;
    }
    word ??= _pickPreferred(seenWords, rng);

    final out = <ReadingItem>[word];

    final phrase = _pickPhrase(
      phrases: readablePhrases,
      word: word,
      sessionKana: orderedKana,
      rng: rng,
    );
    if (phrase != null) out.add(phrase);
    return out;
  }

  /// True when [unit] is a learning token of [text] (or sits inside a yōon).
  static bool containsUnit(String text, String unit) {
    return KanaTokenizer.tokenize(text)
        .any((t) => t == unit || t.contains(unit));
  }

  static List<Kana> _orderBridgeKana(
    List<Kana> sessionKana,
    Map<String, KanaStat> kanaStats,
    DateTime now,
    Random rng,
  ) {
    final keyed = [
      for (final k in sessionKana) (kana: k, key: rng.nextDouble()),
    ];
    int band(Kana k) {
      if (_isConfusable(k.character)) return 0;
      final stat = kanaStats[k.id] ?? const KanaStat();
      if (Weakness.isActionable(stat, now: now)) return 1;
      if (stat.dueAt != null && !stat.dueAt!.isAfter(now)) return 2;
      return 3;
    }

    keyed.sort((a, b) {
      final byBand = band(a.kana).compareTo(band(b.kana));
      if (byBand != 0) return byBand;
      return a.key.compareTo(b.key);
    });
    return [for (final e in keyed) e.kana];
  }

  static Word _pickPreferred(List<Word> candidates, Random rng) {
    final travel = [
      for (final w in candidates)
        if (w.theme == ContentTheme.travel) w,
    ];
    final pool = travel.isNotEmpty ? travel : candidates;
    return pool[rng.nextInt(pool.length)];
  }

  static Phrase? _pickPhrase({
    required List<Phrase> phrases,
    required Word word,
    required List<Kana> sessionKana,
    required Random rng,
  }) {
    if (phrases.isEmpty) return null;
    final wordTokens = _contentTokens(word.kana);
    final sessionUnits = {for (final k in sessionKana) k.character};

    final usingWord = [
      for (final p in phrases)
        if (wordTokens.isNotEmpty &&
            _contentTokens(p.kana).intersection(wordTokens).isNotEmpty)
          p,
    ];
    if (usingWord.isNotEmpty) {
      return usingWord[rng.nextInt(usingWord.length)];
    }

    final usingKana = [
      for (final p in phrases)
        if (sessionUnits.any((u) => containsUnit(p.kana, u))) p,
    ];
    if (usingKana.isNotEmpty) {
      return usingKana[rng.nextInt(usingKana.length)];
    }
    return phrases[rng.nextInt(phrases.length)];
  }

  static Set<String> _contentTokens(String kana) => {
    for (final t in KanaTokenizer.tokenize(kana))
      if (!_particles.contains(t)) t,
  };

  static bool _isConfusable(String character) {
    for (final set in kConfusableSets) {
      if (set.contains(character)) return true;
    }
    for (final set in kKatakanaConfusableSets) {
      if (set.contains(character)) return true;
    }
    return false;
  }
}
