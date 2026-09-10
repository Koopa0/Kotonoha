// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';

/// Property tests for the adaptive session composer. The composer is the most
/// "magic" piece (due + weak + new + fill, deduped, shuffled), so we sweep
/// random learner states and assert structural invariants.
void main() {
  final base = DateTime(2026, 3);
  final scriptOf = {for (final k in kAllKana) k.character: k.script};

  /// Builds a plausible random stats map over [pool].
  Map<String, KanaStat> randomStats(List<Kana> pool, Random rng) {
    final stats = <String, KanaStat>{};
    for (final k in pool) {
      if (rng.nextInt(3) == 0) continue; // some kana unseen
      var s = const KanaStat();
      final answers = 1 + rng.nextInt(6);
      for (var i = 0; i < answers; i++) {
        s = s.recordAnswer(
          correct: rng.nextBool(),
          at: base.subtract(Duration(hours: rng.nextInt(240))),
          latencyMs: rng.nextInt(2000),
        );
      }
      stats[k.id] = s;
    }
    return stats;
  }

  test('compose: determinism, bounds, dedup, mode, and script isolation', () {
    final hira = kAllKana
        .where((k) => k.script == KanaScript.hiragana)
        .toList();
    for (var seed = 0; seed < 300; seed++) {
      final rng = Random(seed);
      final pool = (List<Kana>.of(
        hira,
      )..shuffle(rng)).take(rng.nextInt(hira.length + 1)).toList();
      final stats = randomStats(pool, Random(seed));
      final newCandidates = (List<Kana>.of(
        hira,
      )..shuffle(Random(seed + 7))).take(rng.nextInt(6)).toList();
      final length = 1 + rng.nextInt(16);

      List<SessionItem> run() => DailySession.compose(
        pool: pool,
        stats: stats,
        newCandidates: newCandidates,
        now: base,
        rng: Random(seed),
        length: length,
      );
      final a = run();
      final b = run();
      final why =
          'seed=$seed poolN=${pool.length} '
          'newN=${newCandidates.length} length=$length';

      // Determinism.
      expect(
        [for (final i in a) i.question.target.id],
        [for (final i in b) i.question.target.id],
        reason: 'non-deterministic targets: $why',
      );

      // Bound: never more than asked, never more than the distinct supply.
      final supply = {
        ...pool.map((k) => k.id),
        ...newCandidates.map((k) => k.id),
      };
      expect(a.length, lessThanOrEqualTo(length), reason: 'over length: $why');
      expect(
        a.length,
        lessThanOrEqualTo(supply.length),
        reason: 'over supply: $why',
      );

      // No duplicate target within a session.
      final ids = [for (final i in a) i.question.target.id];
      expect(ids.toSet().length, ids.length, reason: 'dup target: $why');

      for (final item in a) {
        expect(item.mode, PracticeMode.daily, reason: 'mode: $why');
        final q = item.question;
        if (q.direction == QuizDirection.kanaRecall) {
          expect(q.options, isEmpty, reason: 'recall options: $why');
          continue;
        }
        expect(
          q.options.toSet().length,
          q.options.length,
          reason: 'dup option: $why',
        );
        expect(q.isForcedCorrect, isFalse, reason: 'forced-correct MCQ: $why');
        expect(
          q.correctIndex,
          inInclusiveRange(0, q.options.length - 1),
          reason: 'index: $why',
        );
        if (q.direction != QuizDirection.kanaToRomaji) {
          for (final opt in q.options) {
            expect(
              scriptOf[opt],
              q.target.script,
              reason: 'cross-script option "$opt": $why',
            );
          }
        }
      }
    }
  });

  test('quiet: no listening prompt ever; new items still kanaToRomaji', () {
    final hira = kAllKana
        .where((k) => k.script == KanaScript.hiragana)
        .toList();
    for (var seed = 0; seed < 300; seed++) {
      final rng = Random(seed);
      final pool = (List<Kana>.of(
        hira,
      )..shuffle(rng)).take(rng.nextInt(hira.length + 1)).toList();
      final stats = randomStats(pool, Random(seed));
      final newCandidates = (List<Kana>.of(
        hira,
      )..shuffle(Random(seed + 7))).take(rng.nextInt(6)).toList();
      // compose introduces at most kNew new items; any extra candidate that
      // surfaces does so as a review, so mirror take(kNew) here.
      final newIds = newCandidates
          .take(DailySession.kNew)
          .map((k) => k.id)
          .toSet();

      final items = DailySession.compose(
        pool: pool,
        stats: stats,
        newCandidates: newCandidates,
        now: base,
        rng: Random(seed),
        length: 1 + rng.nextInt(16),
        quiet: true,
      );
      for (final i in items) {
        final q = i.question;
        expect(
          q.direction,
          isNot(QuizDirection.soundToKana),
          reason: 'quiet leaked a listening prompt: seed=$seed',
        );
        if (newIds.contains(q.target.id)) {
          expect(
            q.direction,
            QuizDirection.kanaToRomaji,
            reason: 'quiet broke the new-item guard: seed=$seed',
          );
        }
      }
    }
  });

  test('empty pool and empty new candidates compose to nothing', () {
    final items = DailySession.compose(
      pool: const [],
      stats: const {},
      newCandidates: const [],
      now: base,
      rng: Random(0),
    );
    expect(items, isEmpty);
  });
}
