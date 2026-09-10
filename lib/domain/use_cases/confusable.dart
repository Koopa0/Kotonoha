// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

/// Builds a look-alike discrimination drill: each question's distractors are
/// drawn from the SAME confusable group as the target (topped up to 4 options
/// if the group is small), so the learner must truly tell them apart.
///
/// [session] treats [allKana] as the *learned* scope. Home must pass
/// [scope] — never the full gojūon — so unlearned kana cannot become
/// targets or required distractors.
///
/// Pure logic, no `package:flutter/*` imports.
abstract final class Confusable {
  /// Learned gojūon only, plus the script-appropriate curated sets. Katakana
  /// groups enter when a katakana *unit* is learned, not when any katakana
  /// glyph has merely been seen.
  static ({List<Kana> pool, List<List<String>> sets}) scope(
    List<Kana> learned,
  ) {
    final pool = [
      for (final k in learned)
        if (k.isGojuon) k,
    ];
    return (pool: pool, sets: setsFor(pool));
  }

  /// Hiragana sets once any hiragana gojūon is learned; katakana sets once
  /// any katakana gojūon unit is learned.
  static List<List<String>> setsFor(List<Kana> learnedGojuon) {
    final hasHira = learnedGojuon.any((k) => k.script == KanaScript.hiragana);
    final hasKata = learnedGojuon.any((k) => k.script == KanaScript.katakana);
    return [
      if (hasHira) ...kConfusableSets,
      if (hasKata) ...kKatakanaConfusableSets,
    ];
  }

  /// A target is eligible only when at least one look-alike from the same
  /// group is also in [learned] — otherwise the drill is not discrimination.
  static List<Kana> eligibleTargets(
    List<Kana> learned, [
    List<List<String>> sets = kConfusableSets,
  ]) {
    return members(
      learned,
      sets,
    ).where((k) => groupFor(k.character, learned, sets).length >= 2).toList();
  }

  /// Enough learned same-script kana to build a full-option look-alike
  /// question for at least one eligible target. Below this, Home should
  /// hide the entry or guide the learner to 手解き — never pad with
  /// unlearned targets or a single valid option.
  static bool isReady(
    List<Kana> learned, [
    List<List<String>> sets = kConfusableSets,
    int optionCount = 4,
  ]) {
    if (learned.length < optionCount) return false;
    return eligibleTargets(learned, sets).any((t) {
      final sameScript = learned.where((k) => k.script == t.script).length;
      return sameScript >= optionCount;
    });
  }

  /// All kana that appear in any group of [sets] (the curated hiragana groups by
  /// default; the home passes the katakana groups too once katakana is met).
  static List<Kana> members(
    List<Kana> allKana, [
    List<List<String>> sets = kConfusableSets,
  ]) {
    final chars = {for (final set in sets) ...set};
    return allKana.where((k) => chars.contains(k.character)).toList();
  }

  /// The first group of [sets] containing [char] (or just [char] if none).
  static List<Kana> groupFor(
    String char,
    List<Kana> allKana, [
    List<List<String>> sets = kConfusableSets,
  ]) {
    final set = sets.firstWhere((s) => s.contains(char), orElse: () => [char]);
    return [for (final c in set) ...allKana.where((k) => k.character == c)];
  }

  static List<QuizQuestion> session({
    required List<Kana> allKana,
    required int length,
    required QuizEngine engine,
    required Random rng,
    List<List<String>> sets = kConfusableSets,
  }) {
    final mem = eligibleTargets(allKana, sets);
    if (mem.isEmpty || length <= 0) return const [];

    final result = <QuizQuestion>[];
    var guard = 0;
    var i = 0;
    var cycle = List<Kana>.of(mem)..shuffle(rng);
    while (result.length < length && guard < length * 8) {
      guard++;
      if (i >= cycle.length) {
        cycle = List<Kana>.of(mem)..shuffle(rng);
        i = 0;
      }
      final target = cycle[i++];
      final pool = <Kana>{...groupFor(target.character, allKana, sets)};
      // Top up — only within the learned pool and the target's own script.
      // Never pull unlearned kana to pad options.
      final topUp = allKana.where((k) => k.script == target.script).toList()
        ..shuffle(rng);
      for (final k in topUp) {
        if (pool.length >= engine.optionCount) break;
        pool.add(k);
      }
      final usable = pool
          .where((k) => k.id != target.id && k.romaji != target.romaji)
          .length;
      if (usable < engine.optionCount - 1) continue;
      final direction = rng.nextBool()
          ? QuizDirection.kanaToRomaji
          : QuizDirection.romajiToKana;
      final question = engine.buildQuestion(
        target,
        direction,
        pool.toList()..shuffle(rng),
        rng,
      );
      if (question.options.length != engine.optionCount) continue;
      result.add(question);
    }
    return result;
  }
}
