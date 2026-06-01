// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/insights/insights_screen.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pump(WidgetTester tester, AnalyticsLog log) async {
    await tester.pumpWidget(
      Provider<AnalyticsLog>.value(
        value: log,
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty stream shows the gentle empty state', (tester) async {
    await pump(tester, InMemoryAnalyticsLog());
    expect(find.text(AppStrings.insightsEmpty), findsOneWidget);
  });

  testWidgets('renders totals, accuracy, and per-mode tallies', (tester) async {
    final log = InMemoryAnalyticsLog();
    await log.record(
      const Attempt(
        ts: 1,
        itemId: 'あ',
        mode: 'daily',
        correct: true,
        rtMs: 400,
        sessionId: 's',
      ),
    );
    await log.record(
      const Attempt(
        ts: 2,
        itemId: 'か',
        mode: 'reading',
        correct: false,
        sessionId: 's',
      ),
    );
    await pump(tester, log);

    expect(find.text('50%'), findsOneWidget); // 1 of 2 correct
    expect(find.text(AppStrings.modeLabel('daily')), findsOneWidget);
    expect(find.text(AppStrings.modeLabel('reading')), findsOneWidget);
    // The total row reads "2 次".
    expect(find.text(AppStrings.insightsCount(2)), findsOneWidget);
  });
}
