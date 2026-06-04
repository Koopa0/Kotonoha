// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

/// 誤読の標本 phrasings (回望): several sibling templates picked deterministically
/// per pair. RULER guard: every phrasing stays a number-free PRESENT-TENSE STATE
/// (being seen, not scored) — never a count, %, or progress/praise.
void main() {
  const pairs = [
    ['ぬ', 'め'],
    ['シ', 'ツ'],
    ['は', 'ほ'],
    ['ね', 'れ'],
    ['わ', 'ね'],
    ['ソ', 'ン'],
    ['き', 'さ'],
    ['ク', 'ワ'],
    ['る', 'ろ'],
    ['ア', 'マ'],
  ];

  test('a line names both kana, is stable per pair, and carries no number', () {
    for (final p in pairs) {
      final line = AppStrings.confusionLine(p[0], p[1]);
      expect(line, AppStrings.confusionLine(p[0], p[1])); // deterministic
      expect(line, contains(p[0]));
      expect(line, contains(p[1]));
      // A state, never a score: no digits, no %, no progress words.
      expect(RegExp('[0-9%]').hasMatch(line), isFalse, reason: line);
      expect(line.contains('正確'), isFalse, reason: line);
    }
  });

  test('the sibling phrasings genuinely vary across pairs', () {
    // A marker unique to each of the three sibling templates.
    const markers = {'看成', '還沒完全分開', '靠在一起'};
    final reached = <String>{};
    for (final p in pairs) {
      final line = AppStrings.confusionLine(p[0], p[1]);
      for (final m in markers) {
        if (line.contains(m)) reached.add(m);
      }
    }
    // More than one template is actually reached — not one phrasing in disguise.
    expect(reached.length, greaterThan(1));
  });
}
