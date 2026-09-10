// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';

void main() {
  final units = kKanjiUnits;
  final byWritten = <String, List<String>>{};
  for (final u in units) {
    byWritten.putIfAbsent(u.written, () => []).add(u.reading);
  }

  test('every harvested unit has a sentence stem that contains it', () {
    for (final u in units) {
      expect(KanjiPrompt.stemOf(u), contains(u.written));
    }
  });

  test('multi-reading runs are uniquely selected by their sentence stem', () {
    final ambiguous = byWritten.entries.where((e) => e.value.length > 1);
    expect(ambiguous, isNotEmpty, reason: 'corpus should teach 日 / 来 / 会');
    for (final entry in ambiguous) {
      final group = units.where((u) => u.written == entry.key).toList();
      for (final u in group) {
        expect(
          KanjiPrompt.uniquelySelects(u, units),
          isTrue,
          reason:
              '${u.id} stem=${KanjiPrompt.stemOf(u)} rivals='
              '${group.where((o) => o.id != u.id).map((o) => '${o.reading}:${KanjiPrompt.stemOf(o)}').join(', ')}',
        );
      }
    }
  });

  test('日 / 来 / 会 stems match the taught contexts', () {
    String stem(String id) =>
        KanjiPrompt.stemOf(units.singleWhere((u) => u.id == id));

    expect(stem('unit:日#ひ'), '帰国の日');
    expect(stem('unit:日#にち'), '毎日歩く');
    expect(stem('unit:来#く'), '雲が来る');
    expect(stem('unit:来#き'), 'いつ会社へ来ますか');
    expect(stem('unit:来#らい'), '来週まで');
    expect(stem('unit:会#あ'), isNot(stem('unit:会#かい')));
  });

  test('話 in 手話で話す is two marks on one sentence', () {
    final wa = units.singleWhere((u) => u.id == 'unit:話#わ');
    final hana = units.singleWhere((u) => u.id == 'unit:話#はな');
    expect(KanjiPrompt.stemOf(wa), '手話で話す');
    expect(KanjiPrompt.stemOf(hana), '手話で話す');
    expect(KanjiPrompt.markedIndex(wa), isNot(KanjiPrompt.markedIndex(hana)));
    expect(KanjiPrompt.uniquelySelects(wa, units), isTrue);
    expect(KanjiPrompt.uniquelySelects(hana, units), isTrue);
  });
}
