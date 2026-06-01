// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/use_cases/self_portrait.dart';

void main() {
  Attempt wrong(String item, String distractor) => Attempt(
    ts: 1,
    itemId: item,
    mode: 'daily',
    correct: false,
    sessionId: 's',
    meta: {AttemptMeta.distractor: distractor},
  );

  test('says nothing without enough evidence', () {
    expect(SelfPortrait.observe(const []), isEmpty);
    // Only twice — below the threshold of 3.
    expect(SelfPortrait.observe([wrong('ね', 'れ'), wrong('ね', 'れ')]), isEmpty);
  });

  test('surfaces the most-confused look-alike pair once it recurs', () {
    final obs = SelfPortrait.observe([
      wrong('ね', 'れ'),
      wrong('ね', 'れ'),
      wrong('ね', 'れ'),
      wrong('さ', 'ち'),
    ]);
    expect(obs, hasLength(1));
    final c = obs.single as ConfusionObservation;
    expect(c.target, 'ね');
    expect(c.mistakenFor, 'れ');
  });

  test('ignores romaji distractors and correct answers', () {
    final obs = SelfPortrait.observe([
      wrong('ね', 're'), // romaji distractor — not a glyph confusion
      wrong('ね', 're'),
      wrong('ね', 're'),
      const Attempt(
        ts: 1,
        itemId: 'ね',
        mode: 'daily',
        correct: true,
        sessionId: 's',
      ),
    ]);
    expect(obs, isEmpty);
  });
}
