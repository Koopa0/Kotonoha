// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';

/// The classical pool is hand-transcribed PD data, so the value here is catching
/// transcription slips and guarding the invariants that keep it from drifting:
/// a PD attribution on EVERY line (the honesty + licensing gate), spoken-hiragana
/// readings (so a kanji-literate reader meets the sound), and a ONE-line gloss
/// (never a culture-blog paragraph).
/// Allowed in a reading: hiragana (U+3041–U+3096), a space (the 上句／下句 seam in
/// the long waka), or 、(U+3001, kept from the source's phrase breaks in the prose
/// lines). Crucially NO kanji and NO romaji — the reading is the spoken sound.
bool _isReadingChar(int rune) =>
    rune == 0x20 || rune == 0x3001 || (rune >= 0x3041 && rune <= 0x3096);

void main() {
  test('the pool is non-empty', () {
    expect(kKoten, isNotEmpty);
  });

  test('every line names its source (text, reading, gloss, attribution)', () {
    // Each line must carry an attribution — every line is sourced (the honesty
    // gate). Public-domain-ness is guaranteed by curation (all authors died
    // before 1928) + the verification record, NOT by a label shown to the user.
    for (final e in kKoten) {
      expect(e.text.trim(), isNotEmpty, reason: e.text);
      expect(e.reading.trim(), isNotEmpty, reason: e.text);
      expect(e.gloss.trim(), isNotEmpty, reason: e.text);
      expect(e.attribution.trim(), isNotEmpty, reason: 'unsourced: ${e.text}');
    }
  });

  test('readings are spoken hiragana only — no kanji, no romaji', () {
    for (final e in kKoten) {
      for (final r in e.reading.runes) {
        expect(
          _isReadingChar(r),
          isTrue,
          reason:
              '${e.text}: non-hiragana "${String.fromCharCode(r)}" in reading',
        );
      }
    }
  });

  test('glosses are ONE calm line — no newline, never a paragraph', () {
    for (final e in kKoten) {
      expect(e.gloss.contains('\n'), isFalse, reason: e.text);
      // 45 is the DESIGN maximum for one calm line on a narrow phone — the guard
      // against a gloss swelling into a paragraph (the culture-blog drift). If a
      // new gloss trips this, shorten the gloss; do NOT raise the ceiling.
      expect(
        e.gloss.length,
        lessThanOrEqualTo(45),
        reason: '${e.text}: gloss too long — shorten it, do not raise the cap',
      );
    }
  });
}
