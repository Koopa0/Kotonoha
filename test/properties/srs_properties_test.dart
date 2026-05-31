// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// Property tests for the SRS state machine in [KanaStat.recordAnswer]. We feed
/// long random sequences of answers and assert the invariants that must hold
/// after every single step — this is where cap/graduation interplay bugs hide.
void main() {
  final base = DateTime(2026);
  const maxLevel = 6; // _intervalsMinutes.length - 1
  const cap = KanaStat.kUntimedCapLevel; // 3
  const fastThreshold = KanaStat.kFastThresholdMs; // 800

  group('recordAnswer invariants over random sequences', () {
    test('counts, level bounds, and due-in-future hold at every step', () {
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        var stat = const KanaStat();
        var corrects = 0;
        final steps = 1 + rng.nextInt(40);

        for (var i = 0; i < steps; i++) {
          final correct = rng.nextBool();
          // latency: null, 0 (untimed), or a real ms reading.
          final roll = rng.nextInt(3);
          final int? latency = roll == 0
              ? null
              : (roll == 1 ? 0 : rng.nextInt(3000));
          final scale = rng.nextBool() ? 0.5 : 1.0;
          final prevLevel = stat.srsLevel;
          final at = base.add(Duration(minutes: i));

          stat = stat.recordAnswer(
            correct: correct,
            at: at,
            latencyMs: latency,
            intervalScale: scale,
          );
          if (correct) corrects++;
          final why =
              'seed=$seed step=$i correct=$correct '
              'latency=$latency scale=$scale prev=$prevLevel';

          // Counting invariants.
          expect(stat.seenCount, i + 1, reason: 'seen: $why');
          expect(stat.correctCount, corrects, reason: 'correct: $why');
          expect(
            stat.correctCount + stat.wrongCount,
            stat.seenCount,
            reason: 'sum: $why',
          );
          expect(stat.lastReviewedAt, at, reason: 'lastAt: $why');

          // Level bounds + transition rules.
          expect(
            stat.srsLevel,
            inInclusiveRange(0, maxLevel),
            reason: 'bounds: $why',
          );
          if (!correct) {
            expect(stat.srsLevel, 0, reason: 'wrong resets: $why');
          } else {
            final fast =
                latency != null && latency > 0 && latency < fastThreshold;
            if (fast) {
              expect(
                stat.srsLevel,
                min(prevLevel + 1, maxLevel),
                reason: 'fast climbs: $why',
              );
            } else {
              expect(
                stat.srsLevel,
                prevLevel < cap ? prevLevel + 1 : prevLevel,
                reason: 'untimed caps: $why',
              );
            }
          }

          // The next review is always strictly in the future.
          expect(stat.dueAt!.isAfter(at), isTrue, reason: 'due-future: $why');
        }
      }
    });
  });

  group('graduation scenarios', () {
    test('untimed correct answers never climb past the cap', () {
      var stat = const KanaStat();
      for (var i = 0; i < 20; i++) {
        stat = stat.recordAnswer(
          correct: true,
          at: base.add(Duration(days: i)),
        );
      }
      expect(stat.srsLevel, cap);
    });

    test('fast correct answers climb to the maximum level', () {
      var stat = const KanaStat();
      for (var i = 0; i < 20; i++) {
        stat = stat.recordAnswer(
          correct: true,
          at: base.add(Duration(days: i)),
          latencyMs: 300,
        );
      }
      expect(stat.srsLevel, maxLevel);
    });

    test('a single wrong answer resets level regardless of history', () {
      var stat = const KanaStat();
      for (var i = 0; i < 10; i++) {
        stat = stat.recordAnswer(
          correct: true,
          at: base.add(Duration(days: i)),
          latencyMs: 200,
        );
      }
      expect(stat.srsLevel, greaterThan(0));
      stat = stat.recordAnswer(
        correct: false,
        at: base.add(const Duration(days: 99)),
      );
      expect(stat.srsLevel, 0);
    });

    test('confusable scale halves the interval vs an unscaled answer', () {
      final plain = const KanaStat().recordAnswer(
        correct: true,
        at: base,
        latencyMs: 200,
      );
      final scaled = const KanaStat().recordAnswer(
        correct: true,
        at: base,
        latencyMs: 200,
        intervalScale: 0.5,
      );
      final plainMins = plain.dueAt!.difference(base).inMinutes;
      final scaledMins = scaled.dueAt!.difference(base).inMinutes;
      expect(scaledMins, (plainMins / 2).round());
    });
  });
}
