// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kotonoha/main.dart' as app;
import 'package:kotonoha/ui/core/app_strings.dart';

/// End-to-end tests that run the REAL bootstrap (real shared_preferences, real
/// TTS init, real on-disk analytics log) on a device or emulator. Their unique
/// value over the widget smoke test is catching launch/plugin-init/render
/// crashes — the exact class of bug that the R8-stripped-ML-Kit launch crash was.
///
/// Run with: `flutter test integration_test` (needs an attached device).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and the home screen renders without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(await app.bootstrap());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.appTitle), findsOneWidget);
    expect(find.text(AppStrings.continueLearning), findsOneWidget);
    expect(find.text(AppStrings.learnHiragana), findsOneWidget);
  });

  testWidgets('real navigation: home → lessons → study a row → reach its test', (
    tester,
  ) async {
    await tester.pumpWidget(await app.bootstrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.continueLearning));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.lessonsTitle), findsOneWidget);

    await tester.tap(find.text('あ行'));
    await tester.pumpAndSettle();
    expect(find.text('あ'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(AppStrings.nextCard));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(AppStrings.testThisRow));
    await tester.pumpAndSettle();
    // A real quiz question is on screen (its choose-a-thing instruction shows).
    expect(find.textContaining('選擇'), findsOneWidget);
  });

  testWidgets('real navigation: the 五十音図 grid renders the full row span', (
    tester,
  ) async {
    await tester.pumpWidget(await app.bootstrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.learnHiragana));
    await tester.pumpAndSettle();
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('ん'), findsOneWidget);
  });
}
