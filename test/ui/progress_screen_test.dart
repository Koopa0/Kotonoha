// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget test: the progress screen must reflect the repository's real stats —
/// overall accuracy, practiced/total, and the per-status breakdown counts.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, KanaProgressRepository store) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<KanaProgressRepository>.value(
        value: store,
        child: const MaterialApp(home: ProgressScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold start shows 0% and the full 208 as unseen', (tester) async {
    final store = await KanaProgressRepository.load();
    await pump(tester, store);

    expect(find.text('0%'), findsOneWidget);
    expect(find.text(AppStrings.practicedOfTotal(0, 208)), findsOneWidget);
    // Every kana is "未學" → its row count equals the total.
    expect(
      find.widgetWithText(Container, AppStrings.statusNew),
      findsOneWidget,
    );
  });

  testWidgets('recorded answers move accuracy and the status counts', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final at = DateTime(2026, 6);
    // 4 strong (5 correct each) + 1 clearly weak (3 wrong).
    for (final k in kHiraganaGojuon.take(4)) {
      for (var i = 0; i < 5; i++) {
        await store.recordAnswer(k, correct: true, at: at, latencyMs: 300);
      }
    }
    final weak = kHiraganaGojuon[4];
    for (var i = 0; i < 3; i++) {
      await store.recordAnswer(weak, correct: false, at: at);
    }
    await pump(tester, store);

    // 20 correct / 23 answers ≈ 87%.
    expect(find.text('87%'), findsOneWidget);
    expect(find.text(AppStrings.practicedOfTotal(5, 208)), findsOneWidget);
    // The 4 strong kana surface in the 熟練 row.
    expect(
      find.widgetWithText(Container, AppStrings.statusStrong),
      findsOneWidget,
    );
  });
}
