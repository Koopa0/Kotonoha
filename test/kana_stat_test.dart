// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

void main() {
  final now = DateTime(2026, 5, 30, 12);

  test('recordAnswer advances srsLevel on correct, resets on wrong', () {
    var s = const KanaStat();
    s = s.recordAnswer(correct: true, at: now);
    expect(s.srsLevel, 1);
    expect(s.dueAt, isNotNull);
    s = s.recordAnswer(correct: true, at: now);
    expect(s.srsLevel, 2);
    s = s.recordAnswer(correct: false, at: now);
    expect(s.srsLevel, 0);
  });

  test('json round-trips including the new SRS fields', () {
    final s = const KanaStat(
      seenCount: 5,
      correctCount: 4,
      wrongCount: 1,
    ).recordAnswer(correct: true, at: now);
    final back = KanaStat.fromJson(s.toJson());
    expect(back.seenCount, s.seenCount);
    expect(back.correctCount, s.correctCount);
    expect(back.srsLevel, s.srsLevel);
    expect(back.dueAt, s.dueAt);
    expect(back.lastReviewedAt, s.lastReviewedAt);
  });

  test(
    'old JSON without SRS fields decodes to defaults (backward-compatible)',
    () {
      final old = {'s': 3, 'c': 2, 'w': 1, 'l': now.millisecondsSinceEpoch};
      final s = KanaStat.fromJson(old);
      expect(s.seenCount, 3);
      expect(s.srsLevel, 0);
      expect(s.dueAt, isNull);
    },
  );

  test('default SRS fields are omitted from json', () {
    final json = const KanaStat(seenCount: 1).toJson();
    expect(json.containsKey('sl'), isFalse);
    expect(json.containsKey('d'), isFalse);
  });

  group('RT-gated graduation', () {
    test('fast correct graduates without limit (up to max level)', () {
      var s = const KanaStat();
      for (var i = 0; i < 8; i++) {
        s = s.recordAnswer(correct: true, at: now, latencyMs: 200);
      }
      expect(s.srsLevel, 6); // clamped at max interval level
    });

    test('untimed correct climbs to the cap then holds', () {
      var s = const KanaStat();
      for (var i = 0; i < 6; i++) {
        s = s.recordAnswer(correct: true, at: now); // no latency = untimed
      }
      expect(s.srsLevel, KanaStat.kUntimedCapLevel); // 3
    });

    test('fast threshold: 799 graduates, 800+ does not (above cap)', () {
      const base = KanaStat(srsLevel: 4);
      expect(
        base.recordAnswer(correct: true, at: now, latencyMs: 799).srsLevel,
        5,
      );
      expect(
        base.recordAnswer(correct: true, at: now, latencyMs: 800).srsLevel,
        4,
      );
      expect(
        base.recordAnswer(correct: true, at: now, latencyMs: 0).srsLevel,
        4,
      ); // untimed holds above cap
    });

    test('intervalScale halves the next interval', () {
      final full = const KanaStat().recordAnswer(
        correct: true,
        at: now,
        latencyMs: 200,
      );
      final half = const KanaStat().recordAnswer(
        correct: true,
        at: now,
        latencyMs: 200,
        intervalScale: 0.5,
      );
      expect(full.dueAt!.difference(now).inMinutes, 1440); // level 1 = 1 day
      expect(half.dueAt!.difference(now).inMinutes, 720);
    });
  });

  group('CVRT automaticity gate', () {
    test('cvLatency is infinity until timed, then stddev/mean', () {
      expect(const KanaStat().cvLatency, double.infinity);
      // sqrt(900)/300 = 30/300 = 0.1
      expect(
        const KanaStat(avgLatencyMs: 300, varLatencyMs2: 900).cvLatency,
        closeTo(0.1, 0.001),
      );
    });

    test('below the cap, fast graduates regardless of consistency', () {
      // Even with wild variance, an item under the cap is still learning —
      // graduate on speed alone (cold start, unchanged behaviour).
      const early = KanaStat(
        srsLevel: 1,
        avgLatencyMs: 300,
        varLatencyMs2: 40000,
      );
      expect(
        early.recordAnswer(correct: true, at: now, latencyMs: 300).srsLevel,
        2,
      );
    });

    test(
      'past the cap, fast graduates only when reaction time is consistent',
      () {
        // Steady RT (low CV) → graduates 3→4.
        const steady = KanaStat(
          srsLevel: 3,
          avgLatencyMs: 300,
          varLatencyMs2: 900,
        );
        expect(
          steady.recordAnswer(correct: true, at: now, latencyMs: 300).srsLevel,
          4,
        );
        // Erratic fast-or-slow (high CV) → holds at 3, never demotes.
        const erratic = KanaStat(
          srsLevel: 3,
          avgLatencyMs: 300,
          varLatencyMs2: 40000,
        );
        expect(
          erratic.recordAnswer(correct: true, at: now, latencyMs: 300).srsLevel,
          3,
        );
      },
    );

    test('steady fast answers still climb to the max level', () {
      var s = const KanaStat();
      for (var i = 0; i < 8; i++) {
        s = s.recordAnswer(correct: true, at: now, latencyMs: 250);
      }
      expect(s.srsLevel, 6); // constant RT ⇒ CV 0 ⇒ never blocked
    });

    test('varLatencyMs2 round-trips and is omitted at default', () {
      const s = KanaStat(seenCount: 3, avgLatencyMs: 300, varLatencyMs2: 28000);
      expect(s.toJson()['vl'], 28000);
      expect(KanaStat.fromJson(s.toJson()).varLatencyMs2, 28000);
      expect(const KanaStat(seenCount: 1).toJson().containsKey('vl'), isFalse);
    });

    test(
      'an item that reached the cap untimed graduates on its first fast read',
      () {
        // No timed history (avgLatencyMs 0) ⇒ CV is vacuous ⇒ the single fast read
        // graduates 3→4; the consistency gate only bites once real variance accrues.
        const cappedUntimed = KanaStat(srsLevel: 3);
        expect(
          cappedUntimed
              .recordAnswer(correct: true, at: now, latencyMs: 200)
              .srsLevel,
          4,
        );
      },
    );
  });
}
