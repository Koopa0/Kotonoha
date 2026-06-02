// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget test: 歩み is a MAP, not a scoreboard — it shows coverage (kana met /
/// total) and the per-status breakdown, with NO accuracy %, NO reaction time.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, KanaProgressRepository store) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const MaterialApp(home: ProgressScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold start shows 0/208 coverage and no accuracy score', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    await pump(tester, store);

    expect(find.text('0/208'), findsOneWidget); // coverage, not a grade
    expect(find.textContaining('%'), findsNothing); // no accuracy anywhere
    expect(
      find.widgetWithText(Container, AppStrings.statusNew),
      findsOneWidget,
    );
  });

  testWidgets('recorded answers move coverage and the status counts', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final at = DateTime(2026, 6);
    // 4 strong (5 correct each) + 1 clearly weak (3 wrong) → 5 kana met.
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

    expect(find.text('5/208'), findsOneWidget); // 5 kana met
    expect(find.textContaining('%'), findsNothing); // still no score
    // The 4 strong kana surface in the 熟練 row.
    expect(
      find.widgetWithText(Container, AppStrings.statusStrong),
      findsOneWidget,
    );
  });
}
