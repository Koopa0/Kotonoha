// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

/// P0 re-weighting: "fast, not just correct". A stored reaction-time EMA lets
/// the weakness score surface correct-but-slow kana — the reading-fluency
/// bottleneck for a learner whose accuracy saturates quickly.
void main() {
  final at = DateTime(2026, 6);

  KanaStat timed(int n, int ms) {
    var s = const KanaStat();
    for (var i = 0; i < n; i++) {
      s = s.recordAnswer(correct: true, at: at, latencyMs: ms);
    }
    return s;
  }

  group('KanaStat.avgLatencyMs', () {
    test('first timed answer seeds it; untimed answers leave it', () {
      var s = const KanaStat().recordAnswer(
        correct: true,
        at: at,
        latencyMs: 1000,
      );
      expect(s.avgLatencyMs, 1000);
      s = s.recordAnswer(correct: true, at: at); // untimed
      s = s.recordAnswer(correct: true, at: at, latencyMs: 0); // untimed
      expect(s.avgLatencyMs, 1000);
    });

    test('subsequent timed answers EMA toward the new reading', () {
      final s = const KanaStat()
          .recordAnswer(correct: true, at: at, latencyMs: 1000)
          .recordAnswer(correct: true, at: at, latencyMs: 500);
      expect(s.avgLatencyMs, 850); // 0.7*1000 + 0.3*500
    });

    test('round-trips through JSON (omitted at 0)', () {
      expect(const KanaStat().toJson().containsKey('al'), isFalse);
      final s = timed(1, 1200);
      expect(KanaStat.fromJson(s.toJson()).avgLatencyMs, 1200);
    });
  });

  group('Weakness slowness term', () {
    test('correct-but-slow scores weaker than correct-and-fast', () {
      final fast = timed(3, 300);
      final slow = timed(3, 1600);
      expect(Weakness.score(fast, now: at), 0); // perfect + fast = not weak
      expect(
        Weakness.score(slow, now: at),
        greaterThan(Weakness.score(fast, now: at)),
      );
    });

    test('untimed-but-correct kana is not penalised for speed', () {
      var s = const KanaStat();
      for (var i = 0; i < 3; i++) {
        s = s.recordAnswer(correct: true, at: at);
      }
      expect(s.avgLatencyMs, 0);
      expect(Weakness.score(s, now: at), 0);
    });
  });
}
