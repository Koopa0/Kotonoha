// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/ui/ruby_text.dart';

/// RULER guard for the 名残の仮名 promise: "furigana fades to nothing as a reading
/// matures." This drives the ACTUAL untimed production path (kanji_quiz_screen
/// calls recordAnswer with no clock) end to end and asserts the on-screen furigana
/// the learner sees actually reaches opacity 0 — closing the silent coupling where
/// the terminal fade was gated one step above the untimed-reachable cap, so it froze
/// at 0.42 forever in real play while the suite stayed green (ruby_text.dart:23
/// docstring "gone once known" was a lie). It fails the day that coupling returns.
void main() {
  test('untimed mastery alone drives the furigana the learner sees to 0 (gone)', () {
    final at = DateTime(2026, 6);
    var s = const ReadingStat();
    // Correct recalls only, NEVER a clock — exactly how 漢字の声 records every beat.
    for (var i = 0; i < 20; i++) {
      s = s.recordAnswer(correct: true, at: at);
    }
    // The reading climbs to the untimed ceiling on correct recall alone...
    expect(s.srsLevel, ReadingStat.kUntimedCapLevel);
    // ...and at that level the furigana is fully transparent — the training wheels
    // come off without any timed beat. (Was 0.42 before the fade was tied to the cap.)
    expect(RubyText.furiganaOpacity(s.srsLevel), 0.0);
  });

  test('a fresh / cooled reading still shows full furigana (support returns)', () {
    // srsLevel 0 = brand new OR just-missed (recordAnswer resets to 0 on wrong) —
    // either way the support is back at full, so a relapsed reading is re-supported.
    expect(RubyText.furiganaOpacity(0), 1.0);
    final missed = const ReadingStat()
        .recordAnswer(correct: true, at: DateTime(2026, 6))
        .recordAnswer(correct: false, at: DateTime(2026, 6));
    expect(missed.srsLevel, 0);
    expect(RubyText.furiganaOpacity(missed.srsLevel), 1.0);
  });
}
