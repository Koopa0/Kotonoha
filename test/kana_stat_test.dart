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
}
