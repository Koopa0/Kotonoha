// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

/// Composes the adaptive "today's session": one mixed-mode run drawn from the
/// learner's own data — due reviews + weak items + a little new — so they don't
/// have to choose a mode. Pure logic, deterministic under injected Random.
abstract final class DailySession {
  static const int kDue = 7;
  static const int kWeak = 4;
  static const int kNew = 3;

  /// [pool] = review pool (learned kana); [newCandidates] = kana of the next
  /// unlearned lesson; distractors lean on each target's look-alike group and
  /// stay within its script. A [quiet] run keeps reviews to visual recall — no
  /// listening prompt is ever generated — for practising without sound.
  static List<SessionItem> compose({
    required List<Kana> pool,
    required Map<String, KanaStat> stats,
    required List<Kana> newCandidates,
    required DateTime now,
    required Random rng,
    int length = 12,
    bool quiet = false,
    QuizEngine engine = const QuizEngine(),
  }) {
    if (pool.isEmpty && newCandidates.isEmpty) return const [];

    final due = Scheduler.due(pool, stats, now: now).take(kDue);
    final weak = Weakness.weakest(
      pool,
      stats,
      now: now,
      count: kWeak,
    ).where((k) => stats[k.id]?.isSeen ?? false);
    final neu = newCandidates.take(kNew);

    final seen = <String>{};
    final targets = <Kana>[];
    for (final k in [...due, ...weak, ...neu]) {
      if (seen.add(k.id)) targets.add(k);
    }
    // Fill the rest from the pool.
    for (final k in List<Kana>.of(pool)..shuffle(rng)) {
      if (targets.length >= length) break;
      if (seen.add(k.id)) targets.add(k);
    }
    targets.shuffle(rng);

    final newIds = neu.map((k) => k.id).toSet();
    return [
      for (final t in targets.take(length))
        SessionItem(
          question: engine.buildQuestion(
            t,
            _directionFor(
              t,
              isNew: newIds.contains(t.id),
              quiet: quiet,
              rng: rng,
            ),
            _distractors(t, pool, engine.optionCount, rng),
            rng,
          ),
          mode: PracticeMode.daily,
        ),
    ];
  }

  /// Distractors that lean on the target's look-alike group, so a review can't
  /// be passed by elimination — the same desirable-difficulty idea as 目利き
  /// ([Confusable]), now folded into the daily review. The group's members come
  /// first, topped up within the target's own script. [QuizEngine.buildQuestion]
  /// adds the answer, so we supply up to [want] - 1 distractors.
  static List<Kana> _distractors(
    Kana t,
    List<Kana> pool,
    int want,
    Random rng,
  ) {
    // [usable] mirrors buildQuestion's own candidate filter (line ~38) ON
    // PURPOSE — not redundantly. We hand the engine a tightly-capped pool, so a
    // same-romaji kana (ぢ/じ, づ/ず) slipping in would be dropped THERE and
    // leave only 2 distractors → a 3-option question. Pre-screening here keeps
    // every pick valid, so we reliably fill want - 1 and the engine yields 4.
    bool usable(Kana k) =>
        k.id != t.id && k.romaji != t.romaji && k.script == t.script;
    final picks = <Kana>{
      ...Confusable.groupFor(t.character, pool, _confusableSets).where(usable),
    };
    for (final k in List<Kana>.of(pool)..shuffle(rng)) {
      if (picks.length >= want - 1) break;
      if (usable(k)) picks.add(k);
    }
    return picks.toList()..shuffle(rng);
  }

  static const List<List<String>> _confusableSets = [
    ...kConfusableSets,
    ...kKatakanaConfusableSets,
  ];

  /// New items are shown form→sound (gentlest); reviews alternate recall and
  /// listening — except a [quiet] run, where reviews stay visual recall so no
  /// listening prompt (auto-played sound) is ever generated.
  static QuizDirection _directionFor(
    Kana t, {
    required bool isNew,
    required bool quiet,
    required Random rng,
  }) {
    if (isNew) return QuizDirection.kanaToRomaji;
    if (quiet) return QuizDirection.romajiToKana;
    return rng.nextBool()
        ? QuizDirection.romajiToKana
        : QuizDirection.soundToKana;
  }
}
