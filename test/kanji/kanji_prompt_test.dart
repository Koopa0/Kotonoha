// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

void main() {
  final units = kKanjiUnits;

  test('every harvested unit has a sentence stem that contains it', () {
    for (final u in units) {
      expect(KanjiPrompt.stemOf(u), contains(u.written));
    }
  });

  test('毎年の秋 admits both とし and ねん; 三年 admits only ねん', () {
    final toshi = units.singleWhere((u) => u.id == 'unit:年#とし');
    final nen = units.singleWhere((u) => u.id == 'unit:年#ねん');

    expect(KanjiPrompt.stemOf(toshi), '毎年の秋');
    expect(KanjiPrompt.localWord(toshi), '毎年');
    expect(KanjiPrompt.validReadings(toshi), {'とし', 'ねん'});
    expect(KanjiPrompt.uniquelySelects(toshi), isFalse);

    expect(KanjiPrompt.localWord(nen), '三年');
    expect(KanjiPrompt.validReadings(nen), {'ねん'});
    expect(KanjiPrompt.uniquelySelects(nen), isTrue);
  });

  test('帰国の日 selects only ひ; 毎日歩く selects only にち', () {
    final hi = units.singleWhere((u) => u.id == 'unit:日#ひ');
    final nichi = units.singleWhere((u) => u.id == 'unit:日#にち');

    expect(KanjiPrompt.localWord(hi), '日');
    expect(KanjiPrompt.validReadings(hi), {'ひ'});
    expect(KanjiPrompt.validReadings(hi), isNot(contains('にち')));
    expect(KanjiPrompt.validReadings(hi), isNot(contains('に')));
    expect(KanjiPrompt.uniquelySelects(hi), isTrue);

    expect(KanjiPrompt.localWord(nichi), '毎日');
    expect(KanjiPrompt.validReadings(nichi), {'にち'});
    expect(KanjiPrompt.uniquelySelects(nichi), isTrue);

    final ni = units.singleWhere((u) => u.id == 'unit:日#に');
    expect(KanjiPrompt.localWord(ni), '日本');
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

  test('話 in 手話で話す is two local words and two accessible stems', () {
    final wa = units.singleWhere((u) => u.id == 'unit:話#わ');
    final hana = units.singleWhere((u) => u.id == 'unit:話#はな');
    expect(KanjiPrompt.stemOf(wa), '手話で話す');
    expect(KanjiPrompt.stemOf(hana), '手話で話す');
    expect(KanjiPrompt.localWord(wa), '手話');
    expect(KanjiPrompt.localWord(hana), '話す');
    expect(KanjiPrompt.markedIndex(wa), isNot(KanjiPrompt.markedIndex(hana)));

    final waAccess = AppStrings.kanjiAccessibleStem(
      sentence: KanjiPrompt.stemOf(wa),
      localWord: KanjiPrompt.localWord(wa),
      written: wa.written,
    );
    final hanaAccess = AppStrings.kanjiAccessibleStem(
      sentence: KanjiPrompt.stemOf(hana),
      localWord: KanjiPrompt.localWord(hana),
      written: hana.written,
    );
    expect(waAccess, isNot(hanaAccess));
    expect(waAccess, contains('手話'));
    expect(hanaAccess, contains('話す'));
    expect(waAccess, isNot(contains('わ')));
    expect(hanaAccess, isNot(contains('はな')));
  });
}
