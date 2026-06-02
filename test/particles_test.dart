// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/use_cases/particles.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

void main() {
  test('only the read-differently particles (は/を/へ) are detected', () {
    expect(Particles.particlesIn('みずを ください'), ['を']);
    expect(Particles.particlesIn('えきは どこ'), ['は']);
    // が・の・に read exactly as spelled — no reading trap, so no gloss.
    expect(Particles.particlesIn('そらが あおい'), isEmpty);
    expect(Particles.particlesIn('なつの かぜ'), isEmpty);
    expect(Particles.particlesIn('みずに うつる そら'), isEmpty);
  });

  test('a single-token word/phrase has no particle', () {
    expect(Particles.particlesIn('いぬ'), isEmpty); // a word (no spaces)
    expect(Particles.particlesIn('ただいま'), isEmpty); // single-token phrase
  });

  test('every particle the real corpus surfaces has a gloss (no orphans)', () {
    for (final p in kPhrases) {
      for (final particle in Particles.particlesIn(p.kana)) {
        expect(Particles.known.contains(particle), isTrue, reason: p.kana);
        expect(
          AppStrings.particleGloss(particle),
          isNotNull,
          reason: '${p.kana} → $particle',
        );
      }
    }
  });
}
