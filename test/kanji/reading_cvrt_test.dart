// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// The kanji track's CVRT gate (a faithful copy of KanaStat's): timed recall
/// graduates on consistent-fast, not fast-once. Self-graded (untimed) answers
/// still only climb to the cap.
void main() {
  final at = DateTime(2026, 6);

  test('cvLatency is infinity until timed, then stddev/mean', () {
    expect(const ReadingStat().cvLatency, double.infinity);
    final one = const ReadingStat().recordAnswer(
      correct: true,
      at: at,
      latencyMs: 300,
    );
    expect(one.avgLatencyMs, 300);
    expect(one.cvLatency, 0); // one point: no spread
  });

  test('below the cap, fast answers graduate even when timing is erratic', () {
    var s = const ReadingStat();
    s = s.recordAnswer(correct: true, at: at, latencyMs: 100);
    s = s.recordAnswer(correct: true, at: at, latencyMs: 700); // erratic, fast
    expect(s.srsLevel, 2); // climbed both — CV is ignored below the cap
  });

  test('past the cap, fast-but-erratic holds; steady-fast graduates', () {
    var erratic = const ReadingStat();
    for (final ms in [100, 700, 100, 700]) {
      erratic = erratic.recordAnswer(correct: true, at: at, latencyMs: ms);
    }
    expect(erratic.cvLatency, greaterThan(ReadingStat.kMaxGraduationCv));
    expect(erratic.srsLevel, ReadingStat.kUntimedCapLevel); // held at the cap

    var steady = const ReadingStat();
    for (var i = 0; i < 5; i++) {
      steady = steady.recordAnswer(correct: true, at: at, latencyMs: 250);
    }
    expect(steady.cvLatency, lessThanOrEqualTo(ReadingStat.kMaxGraduationCv));
    expect(steady.srsLevel, greaterThan(ReadingStat.kUntimedCapLevel)); // past
  });

  test('untimed self-grade still only climbs to the cap (CVRT untouched)', () {
    var s = const ReadingStat();
    for (var i = 0; i < 6; i++) {
      s = s.recordAnswer(correct: true, at: at); // no latency
    }
    expect(s.srsLevel, ReadingStat.kUntimedCapLevel);
    expect(s.avgLatencyMs, 0); // untimed never feeds the RT signal
    expect(s.cvLatency, double.infinity);
  });

  test('al/vl round-trip and are omitted at default', () {
    expect(const ReadingStat().toJson().containsKey('al'), isFalse);
    final timed = const ReadingStat()
        .recordAnswer(correct: true, at: at, latencyMs: 400)
        .recordAnswer(correct: true, at: at, latencyMs: 600);
    final json = timed.toJson();
    expect(json.containsKey('al'), isTrue);
    expect(json.containsKey('vl'), isTrue);
    final back = ReadingStat.fromJson(json);
    expect(back.avgLatencyMs, timed.avgLatencyMs);
    expect(back.varLatencyMs2, timed.varLatencyMs2);
  });
}
