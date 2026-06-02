// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/use_cases/particles.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

void main() {
  test('particlesIn finds the trailing particle of each non-final token', () {
    expect(Particles.particlesIn('そらが あおい'), ['が']);
    expect(Particles.particlesIn('なつの かぜ'), ['の']);
    expect(Particles.particlesIn('みずを ください'), ['を']);
    expect(Particles.particlesIn('えきは どこ'), ['は']);
    expect(Particles.particlesIn('みずに うつる そら'), ['に']);
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
