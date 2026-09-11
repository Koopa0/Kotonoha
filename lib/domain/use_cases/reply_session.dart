// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/reply_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

/// How one objective pick was earned. Clicking play or a self-grade is never
/// [independent]. Widget greens are not spoken production.
abstract final class ReplyEvidence {
  static const String unheard = 'unheard';
  static const String peeked = 'peeked';
  static const String hinted = 'hinted';
  static const String independent = 'independent';
  static const String miss = 'miss';

  static const String intent = 'intent';
  static const String reply = 'reply';

  static String classify({
    required bool heard,
    required bool sawText,
    required bool usedHint,
    required bool correct,
    bool priorIndependent = true,
  }) {
    if (!heard) return unheard;
    if (!correct) return miss;
    if (sawText) return peeked;
    if (usedHint || !priorIndependent) return hinted;
    return independent;
  }

  static bool isIndependent(String evidence) => evidence == independent;
}

/// Read-only gates for the station-reply room. Inspecting writes nothing.
class ReplySessionView {
  const ReplySessionView({
    required this.all,
    required this.readable,
    required this.ready,
    required this.unreadRequired,
    required this.missingUnits,
  });

  final List<ReplyDrill> all;
  final List<ReplyDrill> readable;
  final List<ReplyDrill> ready;
  final List<ReadingItem> unreadRequired;
  final List<String> missingUnits;

  bool get needsKanaFirst => readable.isEmpty;
  bool get canMeet => unreadRequired.isNotEmpty;
  bool get canPractice => ready.isNotEmpty;
}

/// Station "hear the ask → pick a short reply" composition.
///
/// Reuses shipped T01 / station corpus ids. Does not retune
/// [ListeningSession] or [TravelScene]. Pure logic: no Flutter imports.
abstract final class ReplySession {
  static const int length = 3;

  static List<ReplyDrill> catalog([List<ReplyDrill>? drills]) =>
      List<ReplyDrill>.unmodifiable(drills ?? kReplyDrills);

  static ReplySessionView inspect({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<ReplyDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    final all = catalog(drills);
    final readable = [
      for (final drill in all)
        if (_isReadable(drill, learnedChars)) drill,
    ];
    final ready = [
      for (final drill in readable)
        if (_isMet(drill, stats)) drill,
    ];
    return ReplySessionView(
      all: all,
      readable: readable,
      ready: ready,
      unreadRequired: unreadRequired(
        learnedChars: learnedChars,
        stats: stats,
        drills: all,
        words: words,
        phrases: phrases,
      ),
      missingUnits: missingUnits(all, learnedChars),
    );
  }

  static bool _isReadable(ReplyDrill drill, Set<String> learnedChars) =>
      drill.gatingText.every((t) => KanaTokenizer.isReadable(t, learnedChars));

  static bool _isMet(ReplyDrill drill, Map<String, WordStat> stats) =>
      drill.requiredSeenIds.every((id) => stats[id]?.isSeen ?? false);

  /// Corpus items a readable-but-unmet drill still needs to meet. Never
  /// pads with unrelated travel / 黙読 material.
  static List<ReadingItem> unreadRequired({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<ReplyDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    final byId = _corpus(words: words, phrases: phrases);
    final seen = <String>{};
    final items = <ReadingItem>[];
    for (final drill in catalog(drills)) {
      if (!_isReadable(drill, learnedChars)) continue;
      for (final id in drill.requiredSeenIds) {
        if (stats[id]?.isSeen ?? false) continue;
        if (!seen.add(id)) continue;
        final item = byId[id];
        if (item == null) continue;
        if (!ReadingSet.readable([item], learnedChars).contains(item)) {
          continue;
        }
        items.add(item);
      }
    }
    return items;
  }

  static List<Word> unreadRequiredWords({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<ReplyDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) => unreadRequired(
    learnedChars: learnedChars,
    stats: stats,
    drills: drills,
    words: words,
    phrases: phrases,
  ).whereType<Word>().toList();

  static List<ReadingItem> unreadRequiredPhrases({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<ReplyDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) => unreadRequired(
    learnedChars: learnedChars,
    stats: stats,
    drills: drills,
    words: words,
    phrases: phrases,
  ).where((item) => item.progressId.startsWith('phrase:')).toList();

  static List<String> missingUnits(
    Iterable<ReplyDrill> drills,
    Set<String> learnedChars,
  ) {
    final missing = <String>[];
    for (final drill in drills) {
      for (final stretch in drill.gatingText) {
        for (final token in KanaTokenizer.tokenize(stretch)) {
          if (token == KanaTokenizer.choonpu) continue;
          if (token == KanaTokenizer.sokuonHiragana) {
            if (!learnedChars.contains('つ') && !missing.contains('つ')) {
              missing.add('つ');
            }
            continue;
          }
          if (token == KanaTokenizer.sokuonKatakana) {
            if (!learnedChars.contains('ツ') && !missing.contains('ツ')) {
              missing.add('ツ');
            }
            continue;
          }
          if (KanaTokenizer.isReadable(token, learnedChars)) continue;
          if (!missing.contains(token)) missing.add(token);
        }
      }
    }
    return missing;
  }

  /// Ready drills only. Never boards unmet material as a cold listen.
  static List<ReplyDrill> compose({
    required Set<String> learnedChars,
    required Random rng,
    Map<String, WordStat> stats = const {},
    List<ReplyDrill>? drills,
    int sessionLength = length,
  }) {
    final ready = [
      for (final drill in catalog(drills))
        if (_isReadable(drill, learnedChars) && _isMet(drill, stats)) drill,
    ];
    if (ready.isEmpty) return const [];
    final copy = List<ReplyDrill>.of(ready)..shuffle(rng);
    if (copy.length <= sessionLength) return copy;
    // Prefer distinct heard prompts so a 3-turn session still covers
    // destination / location / confirmation when all are ready. Same-prompt
    // scene pairs stay together when that is all the learner has met.
    final picked = <ReplyDrill>[];
    final seenPrompt = <String>{};
    for (final drill in copy) {
      if (picked.length >= sessionLength) break;
      if (seenPrompt.add(drill.promptKana)) {
        picked.add(drill);
      }
    }
    for (final drill in copy) {
      if (picked.length >= sessionLength) break;
      if (!picked.contains(drill)) picked.add(drill);
    }
    return picked;
  }

  static Map<String, ReadingItem> _corpus({
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) => {
    for (final item in words ?? kWords) item.progressId: item,
    for (final item in phrases ?? kPhrases) item.progressId: item,
  };
}
