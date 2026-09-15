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
/// These deliberately do NOT seed or clear stored progress. They run against
/// whatever the device already holds, so they must stay reachable from any
/// state and must not touch learning evidence — running them on a real phone
/// should never cost the owner a day's practice, and fabricated progress would
/// make a walk prove something the learner never did.
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

  // #149 B6. Of the rooms split into View / ViewModel, 換句 is the one a home
  // with no progress still offers, so it is the only one this suite can reach
  // without fabricating practice. The host suite already covers its state and
  // commands; what only a device adds is that the real composition root hands
  // this route its owners and it renders against real storage rather than a
  // fake — the same class of check as the launch test above, one route deeper.
  testWidgets('real navigation: home → 換句 renders against real storage', (
    tester,
  ) async {
    await tester.pumpWidget(await app.bootstrap());
    await tester.pumpAndSettle();

    final entry = find.text(AppStrings.shiftAction);
    expect(entry, findsOneWidget, reason: 'the home offers no 換句 entry');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.shiftTitle), findsOneWidget);
  });
}
