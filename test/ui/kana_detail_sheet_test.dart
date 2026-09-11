// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/widgets/kana_detail_sheet.dart';
import 'package:provider/provider.dart';

/// The 五十音図 detail sheet must show a calm present-tense STATUS (a state),
/// NEVER a chase-able per-kana score. Guards retention-ruler #1: accuracy /
/// counts stay private scheduler inputs and must not leak to this surface.
void main() {
  final kana = kHiraganaGojuon.first; // あ (romaji "a")

  Future<void> pump(WidgetTester tester, KanaStat stat) => tester.pumpWidget(
    Provider<SpeechService>.value(
      value: const SilentSpeechService(),
      child: MaterialApp(
        home: Scaffold(
          body: KanaDetailSheet(kana: kana, stat: stat),
        ),
      ),
    ),
  );

  testWidgets('a seen kana shows its status, never a score or accuracy', (
    tester,
  ) async {
    // 4 seen, all correct → strong. The old UI would have shown 答對/答錯/100%.
    await pump(tester, const KanaStat(seenCount: 4, correctCount: 4));
    await tester.pumpAndSettle();

    expect(find.text(kana.character), findsOneWidget);
    expect(find.text(kana.romaji), findsOneWidget);
    // A present-tense state, not a grade.
    expect(find.text(AppStrings.statusStrong), findsOneWidget);
    // No score in ANY form.
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('a weak kana shows 待加強 (a state), still no number', (
    tester,
  ) async {
    // 4 seen, 2 wrong → accuracy 0.5 → weak.
    await pump(
      tester,
      const KanaStat(seenCount: 4, correctCount: 2, wrongCount: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.statusWeak), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('an unseen kana shows the calm "not practiced" line', (
    tester,
  ) async {
    await pump(tester, const KanaStat());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.notPracticedYet), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
