// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

/// Builds the ordered list of lessons from a kana set, assembles a lesson's
/// test (cumulative — the row plus review of earlier rows), and decides when a
/// lesson is "passed". Pure logic: no `package:flutter/*` imports.
class Lessons {
  const Lessons._();

  /// Minimum accuracy *on the focus row's questions* to count as learned.
  static const double passThreshold = 0.8;

  /// Hiragana row titles (0=あ行 … 10=ん).
  static const List<String> _hiraRowTitles = [
    'あ行',
    'か行',
    'さ行',
    'た行',
    'な行',
    'は行',
    'ま行',
    'や行',
    'ら行',
    'わ行',
    'ん',
  ];

  /// Katakana row titles (0=ア行 … 10=ン).
  static const List<String> _kataRowTitles = [
    'ア行',
    'カ行',
    'サ行',
    'タ行',
    'ナ行',
    'ハ行',
    'マ行',
    'ヤ行',
    'ラ行',
    'ワ行',
    'ン',
  ];

  static String _idPrefix(KanaScript s) =>
      s == KanaScript.hiragana ? 'hira' : 'kata';

  static String _yoonBase(Kana k) =>
      String.fromCharCode(k.character.runes.first);

  /// Lesson id for a kana. Seion keeps the legacy `hira_row_N` / `kata_row_N`
  /// ids (saved learned_units_v1 must survive); other kinds use disjoint
  /// namespaces so が never merges into か's hira_row_1.
  static String _unitId(Kana k) {
    final p = _idPrefix(k.script);
    switch (k.kind) {
      case KanaKind.seion:
        return '${p}_row_${k.row}';
      case KanaKind.dakuon:
        return '${p}_dakuten_${k.row}';
      case KanaKind.handakuon:
        return '${p}_handakuten_${k.row}';
      case KanaKind.yoon:
        return '${p}_yoon_${_yoonBase(k)}';
    }
  }

  static String _titleFor(List<Kana> kana) {
    final first = kana.first;
    switch (first.kind) {
      case KanaKind.seion:
        final titles = first.script == KanaScript.hiragana
            ? _hiraRowTitles
            : _kataRowTitles;
        return first.row < titles.length
            ? titles[first.row]
            : 'row ${first.row}';
      case KanaKind.dakuon:
      case KanaKind.handakuon:
        return '${first.character}行';
      case KanaKind.yoon:
        return kana.map((k) => k.character).join('・');
    }
  }

  /// Groups [allKana] into ordered lessons, one per (script, kind, row/family).
  /// Seion keeps `hira_row_N` / `kata_row_N` (backward-compatible); dakuten/
  /// handakuten/yoon use disjoint id namespaces.
  static List<Lesson> fromKana(List<Kana> allKana) {
    final byKey = <String, List<Kana>>{};
    final order = <String>[];
    for (final k in allKana) {
      final key = _unitId(k);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = [k];
        order.add(key);
      } else {
        existing.add(k);
      }
    }
    return [
      for (final key in order)
        Lesson(id: key, title: _titleFor(byKey[key]!), kana: byKey[key]!),
    ];
  }

  /// The shuffled question targets for a lesson test. The focus row appears
  /// twice each (desirable difficulty), interleaved with a sample of
  /// previously-learned kana so the test isn't a closed 5-of-5 guessing game.
  static List<Kana> testTargets(
    Lesson lesson,
    List<Kana> learnedOtherKana,
    Random rng,
  ) {
    final targets = <Kana>[...lesson.kana, ...lesson.kana];
    if (learnedOtherKana.isNotEmpty) {
      final pool = List<Kana>.of(learnedOtherKana)..shuffle(rng);
      final reviewN = lesson.kana.length.clamp(0, pool.length);
      targets.addAll(pool.take(reviewN));
    }
    targets.shuffle(rng);
    return targets;
  }

  /// Composes a lesson row test from [pool] (learned ∪ focus row). Tiny pools
  /// follow the Daily honesty contract: when a target cannot host a fair MCQ,
  /// it becomes [QuizDirection.kanaRecall] instead of a forced-correct tap.
  static List<QuizQuestion> composeTest({
    required Lesson lesson,
    required List<Kana> learnedOtherKana,
    required List<Kana> pool,
    Random? random,
    QuizEngine engine = const QuizEngine(),
  }) {
    final rng = random ?? Random();
    final targets = testTargets(lesson, learnedOtherKana, rng);
    final questions = <QuizQuestion>[];
    for (final target in targets) {
      questions.add(_questionFor(target, pool, rng, engine));
    }
    return questions;
  }

  static QuizQuestion _questionFor(
    Kana target,
    List<Kana> pool,
    Random rng,
    QuizEngine engine,
  ) {
    if (!DailySession.canDiscriminate(target, pool)) {
      return engine.buildQuestion(target, QuizDirection.kanaRecall, pool, rng);
    }
    final direction = rng.nextBool()
        ? QuizDirection.kanaToRomaji
        : QuizDirection.romajiToKana;
    final question = engine.buildQuestion(target, direction, pool, rng);
    if (question.isForcedCorrect) {
      return engine.buildQuestion(target, QuizDirection.kanaRecall, pool, rng);
    }
    return question;
  }

  /// Whether the lesson is passed — judged ONLY on the focus row's questions,
  /// so interleaved review items don't affect the verdict.
  static bool isPassed(Lesson lesson, QuizResult result) {
    final ids = lesson.kana.map((k) => k.id).toSet();
    final inScope = result.answers.where(
      (a) => ids.contains(a.question.target.id),
    );
    final total = inScope.length;
    if (total == 0) return false;
    final correct = inScope.where((a) => a.wasCorrect).length;
    return correct / total >= passThreshold;
  }
}
