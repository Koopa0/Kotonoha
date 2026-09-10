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
    expect(back.lastMistakeAt, s.lastMistakeAt);
  });

  test('recordAnswer keeps lastMistakeAt on correct, sets it on wrong', () {
    final missed = const KanaStat().recordAnswer(correct: false, at: now);
    expect(missed.lastMistakeAt, now);
    final later = now.add(const Duration(days: 1));
    final recovered = missed.recordAnswer(
      correct: true,
      at: later,
      latencyMs: 500,
    );
    expect(recovered.lastReviewedAt, later);
    expect(recovered.lastMistakeAt, now);
  });

  test('old JSON without lastMistakeAt does not invent one', () {
    final old = {'s': 100, 'c': 99, 'w': 1, 'l': now.millisecondsSinceEpoch};
    final s = KanaStat.fromJson(old);
    expect(s.wrongCount, 1);
    expect(s.lastMistakeAt, isNull);
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

  test('old visual-only JSON stays listening-unknown', () {
    final old = {
      's': 138,
      'c': 138,
      'w': 0,
      'sl': 6,
      'al': 500,
      'l': now.millisecondsSinceEpoch,
    };
    final s = KanaStat.fromJson(old);
    expect(s.listeningUnknown, isTrue);
    expect(s.listenSeenCount, 0);
    expect(s.hasReliableListening(now: now), isFalse);
    expect(s.toJson().containsKey('ls'), isFalse);
    expect(s.toJson().containsKey('lc'), isFalse);
  });

  test('visual recordAnswer does not invent listening evidence', () {
    var s = const KanaStat();
    s = s.recordAnswer(correct: true, at: now, latencyMs: 400);
    expect(s.listeningUnknown, isTrue);
    expect(s.listenSeenCount, 0);
    expect(s.seenCount, 1);
  });

  test('scored listening writes listen fields; a miss is not unknown', () {
    var s = const KanaStat().recordAnswer(
      correct: true,
      at: now,
      latencyMs: 400,
      listening: true,
    );
    expect(s.listeningUnknown, isFalse);
    expect(s.listenSeenCount, 1);
    expect(s.listenCorrectCount, 1);
    expect(s.hasReliableListening(now: now), isFalse);
    s = s.recordAnswer(
      correct: true,
      at: now.add(const Duration(minutes: 1)),
      latencyMs: 400,
      listening: true,
    );
    expect(
      s.hasReliableListening(now: now.add(const Duration(minutes: 1))),
      isTrue,
    );
    final missed = s.recordAnswer(
      correct: false,
      at: now.add(const Duration(hours: 1)),
      listening: true,
    );
    expect(
      missed.hasRecentListeningMiss(now: now.add(const Duration(hours: 1))),
      isTrue,
    );
    expect(
      missed.hasReliableListening(now: now.add(const Duration(hours: 1))),
      isFalse,
    );
    expect(missed.srsLevel, 0);
  });

  test('recordPromptedPractice keeps listen evidence untouched', () {
    final heard = KanaStat(
      listenSeenCount: 2,
      listenCorrectCount: 2,
      lastListenAt: now,
    );
    final next = heard.recordPromptedPractice(
      at: now.add(const Duration(minutes: 1)),
    );
    expect(next.listenSeenCount, 2);
    expect(next.listenCorrectCount, 2);
    expect(next.lastListenAt, now);
  });

  test('listen fields round-trip and stay omitted at default', () {
    final s = const KanaStat().recordAnswer(
      correct: false,
      at: now,
      listening: true,
    );
    final back = KanaStat.fromJson(s.toJson());
    expect(back.listenSeenCount, 1);
    expect(back.listenWrongCount, 1);
    expect(back.lastListenMistakeAt, now);
    expect(const KanaStat(seenCount: 1).toJson().containsKey('ls'), isFalse);
    expect(const KanaStat(seenCount: 1).toJson().containsKey('llm'), isFalse);
  });

  test('recordPromptedPractice keeps correctCount, due, and lastMistake', () {
    final due = now.subtract(const Duration(days: 10));
    final missed = now.subtract(const Duration(days: 20));
    final s = KanaStat(
      seenCount: 10,
      correctCount: 10,
      srsLevel: 6,
      dueAt: due,
      lastReviewedAt: due,
      lastMistakeAt: missed,
      avgLatencyMs: 400,
    );
    final next = s.recordPromptedPractice(at: now);
    expect(next.correctCount, 10);
    expect(next.srsLevel, 6);
    expect(next.dueAt, due);
    expect(next.lastMistakeAt, missed);
    expect(next.lastReviewedAt, due);
    expect(next.seenCount, 11);
    expect(next.avgLatencyMs, 400);
  });
}
