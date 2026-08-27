// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/ferry_session.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

/// Capacity guard for the 詞と句 schedule at "large corpus" scale — the failure
/// modes it exists to catch are the quiet ones a green unit suite never sees:
///
///  - **overdue divergence**: intervals too short (a 7-day ceiling) or an
///    ungated intake make a growing corpus produce more daily reviews than the
///    sessions can absorb, so the due backlog grows without bound and every
///    session is forever remedial. (Both bugs existed during development;
///    this simulation caught the ungated-intake one.)
///  - **new-item starvation**: a valve tuned too tight lets the due queue
///    permanently strangle introduction.
///
/// The simulation mirrors the real daily shape — 渡し舟 introduces (up to 3
/// never-seen words, first meeting = one correct encode, self-throttling on
/// the review backlog), 文字起こし reviews (8 items, due first, never
/// introduces, 10% error rate) — over 400 words, 180 days, deterministic.
///
/// Physics, not policy: one 8-item review session per day can mature at most
/// ~1 new word per day (each costs ~7 reviews to reach the long intervals), so
/// intake at that pace is capacity-limited by design. What must hold is that
/// the backlog stays bounded at ANY pace, and that throughput SCALES with
/// appetite — a learner who taps もう一回 gets proportionally more corpus.
void main() {
  test('one review session a day: bounded backlog, steady (capacity-limited) intake', () {
    final r = _simulate(reviewSessionsPerDay: 1);
    expect(
      r.maxBacklogAfterSettling,
      lessThanOrEqualTo(16),
      reason: 'due backlog diverged: ${r.maxBacklogAfterSettling}',
    );
    expect(
      r.introduced,
      greaterThanOrEqualTo(150),
      reason: 'introduction collapsed: only ${r.introduced} of 400 met',
    );
    expect(
      r.mature,
      greaterThanOrEqualTo(100),
      reason: 'items are not maturing: ${r.mature} at level >= 4',
    );
  });

  test('three review sessions a day (もう一回): the corpus opens ~3x faster, still bounded', () {
    final r = _simulate(reviewSessionsPerDay: 3);
    expect(
      r.maxBacklogAfterSettling,
      lessThanOrEqualTo(16),
      reason: 'due backlog diverged: ${r.maxBacklogAfterSettling}',
    );
    expect(
      r.introduced,
      greaterThanOrEqualTo(380),
      reason: 'appetite did not scale: only ${r.introduced} of 400 met',
    );
    expect(
      r.mature,
      greaterThanOrEqualTo(300),
      reason: 'items are not maturing: ${r.mature} at level >= 4',
    );
  });
}

typedef _SimResult = ({
  int maxBacklogAfterSettling,
  int introduced,
  int mature,
});

_SimResult _simulate({required int reviewSessionsPerDay}) {
  final chars = {
    for (final k in kAllKana)
      if (k.script == KanaScript.hiragana) k.character,
  };
  // 400 distinct two-unit words from the plain gojūon (all readable).
  final base = [
    for (final k in kHiraganaGojuon)
      if (k.character != 'を') k.character,
  ];
  final words = <Word>[
    for (var i = 0; i < 400; i++)
      Word(
        kana: base[i ~/ base.length] + base[i % base.length],
        romaji: 'w$i',
        meaning: 'm$i',
      ),
  ];
  assert(words.map((w) => w.kana).toSet().length == 400);

  final stats = <String, WordStat>{};
  final rng = Random(42);
  final start = DateTime(2026, 9, 1, 9);

  var maxBacklog = 0;
  for (var day = 0; day < 180; day++) {
    final now = start.add(Duration(days: day));

    // 渡し舟 — introduction only (self-throttling).
    final ferry = FerrySession.compose(
      words: words,
      learnedChars: chars,
      rng: rng,
      now: now,
      stats: stats,
    );
    for (final w in ferry) {
      final s = stats[w.progressId] ?? const WordStat();
      if (!s.isSeen) {
        stats[w.progressId] = s.recordAnswer(correct: true, at: now);
      }
    }

    // Measure the backlog the first review session walks into.
    final backlog = stats.values
        .where((s) => s.dueAt != null && !s.dueAt!.isAfter(now))
        .length;
    if (day >= 30) maxBacklog = max(maxBacklog, backlog);

    // 文字起こし — the objective schedule authority (10% error rate).
    for (var n = 0; n < reviewSessionsPerDay; n++) {
      final at = now.add(Duration(hours: n));
      final session = ReadingSet.session(
        items: words,
        learnedChars: chars,
        rng: rng,
        now: at,
        stats: stats,
        maxNew: 0,
      );
      for (final w in session) {
        final correct = rng.nextDouble() >= 0.10;
        stats[w.progressId] = (stats[w.progressId] ?? const WordStat())
            .recordAnswer(correct: correct, at: at);
      }
    }
  }

  return (
    maxBacklogAfterSettling: maxBacklog,
    introduced: stats.values.where((s) => s.isSeen).length,
    mature: stats.values.where((s) => s.srsLevel >= 4).length,
  );
}
