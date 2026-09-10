// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dictation_screen_test.dart' as fixture;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('independent large text full flow and next question viewport', (
    tester,
  ) async {
    const postal = Word(kana: 'ゆうびんきょく', romaji: 'yuubinkyoku', meaning: '郵局');
    const other = Word(kana: 'あたたかい', romaji: 'atatakai', meaning: '溫暖');
    await fixture.pumpDictation(
      tester,
      words: const [postal, other],
      size: const Size(360, 560),
      textScale: 2,
    );
    for (final token in KanaTokenizer.tokenize(postal.kana)) {
      final tile = find.text(token).last;
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text(AppStrings.dictationNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.dictationNext));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final sc = tester.state<ScrollableState>(find.byType(Scrollable).first);
    // ignore: avoid_print
    print(
      'next scroll=${sc.position.pixels}/${sc.position.maxScrollExtent} '
      'speakerRect=${tester.getRect(find.byType(SpeakButton))} '
      'speakerHit=${find.byType(SpeakButton).hitTestable().evaluate().length}',
    );
    expect(
      find.byType(SpeakButton).hitTestable(),
      findsOneWidget,
      reason: 'a new listening question must expose its replay prompt',
    );
    for (final token in KanaTokenizer.tokenize(other.kana)) {
      final tile = find.text(token).last;
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text(other.meaning), findsOneWidget);
  });

  testWidgets('next question prompt is visible at 320×480 with 2× text', (
    tester,
  ) async {
    const postal = Word(kana: 'ゆうびんきょく', romaji: 'yuubinkyoku', meaning: '郵局');
    const other = Word(kana: 'あたたかい', romaji: 'atatakai', meaning: '溫暖');
    await fixture.pumpDictation(
      tester,
      words: const [postal, other],
      size: const Size(320, 480),
      textScale: 2,
    );
    for (final token in KanaTokenizer.tokenize(postal.kana)) {
      final tile = find.text(token).last;
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text(AppStrings.dictationNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.dictationNext));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(SpeakButton).hitTestable(),
      findsOneWidget,
      reason: 'a new listening question must expose its replay prompt',
    );
    expect(find.text(other.kana), findsNothing);
  });
}
