// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
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
  /// unlearned lesson; distractors stay within each target's script.
  static List<SessionItem> compose({
    required List<Kana> pool,
    required Map<String, KanaStat> stats,
    required List<Kana> newCandidates,
    required DateTime now,
    required Random rng,
    int length = 12,
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
            _directionFor(t, isNew: newIds.contains(t.id), rng: rng),
            pool.where((k) => k.script == t.script).toList(),
            rng,
          ),
          mode: PracticeMode.daily,
        ),
    ];
  }

  /// New items are shown form→sound (gentlest); reviews alternate recall and
  /// listening. Yōon (2-codepoint) never go to listening prompts here either.
  static QuizDirection _directionFor(
    Kana t, {
    required bool isNew,
    required Random rng,
  }) {
    if (isNew) return QuizDirection.kanaToRomaji;
    return rng.nextBool()
        ? QuizDirection.romajiToKana
        : QuizDirection.soundToKana;
  }
}
