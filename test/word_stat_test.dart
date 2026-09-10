// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/word_stat.dart';

void main() {
  final at = DateTime(2026, 6, 1, 12);

  group('JSON round-trip', () {
    test('a fresh (level-0) stat omits sl/l/d and round-trips', () {
      const s = WordStat(seenCount: 2, correctCount: 1, wrongCount: 1);
      final json = s.toJson();
      expect(json.containsKey('sl'), isFalse); // level 0 omitted
      expect(json.containsKey('l'), isFalse); // null lastReviewedAt omitted
      expect(json.containsKey('d'), isFalse); // null dueAt omitted

      final back = WordStat.fromJson(json);
      expect(back.seenCount, 2);
      expect(back.correctCount, 1);
      expect(back.wrongCount, 1);
      expect(back.srsLevel, 0);
      expect(back.lastReviewedAt, isNull);
      expect(back.dueAt, isNull);
    });

    test('a stat with a nonzero level round-trips every field', () {
      final s = const WordStat().recordAnswer(correct: true, at: at);
      final json = s.toJson();
      expect(json.containsKey('sl'), isTrue);
      expect(json.containsKey('l'), isTrue);
      expect(json.containsKey('d'), isTrue);

      final back = WordStat.fromJson(json);
      expect(back.seenCount, 1);
      expect(back.correctCount, 1);
      expect(back.wrongCount, 0);
      expect(back.srsLevel, 1);
      expect(back.lastReviewedAt, at);
      expect(back.dueAt, s.dueAt);
    });
  });

  test('isSeen reflects whether the item has been recorded at all', () {
    expect(const WordStat().isSeen, isFalse);
    expect(
      const WordStat().recordAnswer(correct: false, at: at).isSeen,
      isTrue,
    );
  });

  group('recordAnswer', () {
    test('a correct answer from fresh advances level 0 to 1, due in 1 day', () {
      final s = const WordStat().recordAnswer(correct: true, at: at);
      expect(s.srsLevel, 1);
      expect(s.seenCount, 1);
      expect(s.correctCount, 1);
      expect(s.wrongCount, 0);
      expect(s.dueAt, at.add(const Duration(days: 1)));
    });

    test('a wrong answer resets the level to 0, due in 10 minutes', () {
      var s = const WordStat().recordAnswer(correct: true, at: at); // level 1
      s = s.recordAnswer(correct: true, at: at); // level 2
      s = s.recordAnswer(correct: false, at: at);
      expect(s.srsLevel, 0);
      expect(s.wrongCount, 1);
      expect(s.dueAt, at.add(const Duration(minutes: 10)));
    });

    test(
      'correct answers climb to kMaxLevel and hold there, due in 60 days',
      () {
        var s = const WordStat();
        for (var i = 0; i < 10; i++) {
          s = s.recordAnswer(correct: true, at: at);
        }
        expect(s.srsLevel, WordStat.kMaxLevel);
        expect(s.seenCount, 10);
        expect(s.dueAt, at.add(const Duration(days: 60)));

        // One more correct answer holds at the ceiling instead of climbing
        // past it.
        s = s.recordAnswer(correct: true, at: at);
        expect(s.srsLevel, WordStat.kMaxLevel);
        expect(s.dueAt, at.add(const Duration(days: 60)));
      },
    );
  });

  group('accuracy', () {
    test('is 0 when never seen', () {
      expect(const WordStat().accuracy, 0);
    });

    test('is correctCount / seenCount', () {
      var s = const WordStat();
      s = s.recordAnswer(correct: true, at: at);
      s = s.recordAnswer(correct: true, at: at);
      s = s.recordAnswer(correct: false, at: at);
      s = s.recordAnswer(correct: true, at: at);
      expect(s.seenCount, 4);
      expect(s.accuracy, closeTo(0.75, 1e-9));
    });
  });

  group('fromJson clamps corrupt input', () {
    test('an out-of-range srsLevel clamps to kMaxLevel', () {
      final s = WordStat.fromJson(const {'s': 4, 'c': 4, 'w': 0, 'sl': 999});
      expect(s.srsLevel, WordStat.kMaxLevel);
    });

    test('negative counts clamp to 0', () {
      final s = WordStat.fromJson(const {'s': -5, 'c': -1, 'w': -9});
      expect(s.seenCount, 0);
      expect(s.correctCount, 0);
      expect(s.wrongCount, 0);
    });

    test('markIntroduced is seen without a successful-recall climb', () {
      final s = const WordStat().markIntroduced(at: at);
      expect(s.isSeen, isTrue);
      expect(s.correctCount, 0);
      expect(s.srsLevel, 0);
      expect(s.dueAt, at.add(const Duration(minutes: 10)));
      expect(s.markIntroduced(at: at.add(const Duration(days: 1))), s);
    });

    test('a clamped stat still schedules without crashing', () {
      final s = WordStat.fromJson(const {'s': 4, 'c': 4, 'w': 0, 'sl': 999});
      final next = s.recordAnswer(correct: true, at: at);
      expect(next.dueAt, isNotNull);
      // Already at the (clamped) ceiling, so it holds rather than climbs.
      expect(next.srsLevel, WordStat.kMaxLevel);
    });
  });
}
