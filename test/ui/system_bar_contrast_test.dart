// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_theme.dart';
import 'package:kotonoha/ui/core/widgets/kana_card.dart';
import 'package:kotonoha/ui/core/widgets/kana_detail_sheet.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/learn/learn_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

/// #166: every page sits on light washi paper, so the status-bar icons must
/// stay dark throughout — including after returning to the home, which has no
/// AppBar of its own to re-assert a style.
///
/// Each step reads the annotation the renderer itself would read — the
/// `SystemUiOverlayStyle` under the top-centre of the screen — rather than
/// the last style pushed to the platform. That distinction is the bug: with
/// no annotation there, nothing is pushed and the previous route's icons
/// simply stay. The pushed styles are recorded too, so the platform-facing
/// value is checked as well. Host evidence about the requested style, not a
/// physical-device observation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<Object?, Object?>> pushed;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pushed = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            pushed.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// What the platform was last told about the status bar, or null if the
  /// app never asked.
  String? lastStatusBarIcons() {
    for (final style in pushed.reversed) {
      final icons = style['statusBarIconBrightness'];
      if (icons != null) return icons as String;
    }
    return null;
  }

  /// The style annotated under the status bar right now — what
  /// `RendererBinding` reads each frame. Null means nothing claims it, and
  /// the device keeps whatever was set last.
  SystemUiOverlayStyle? annotatedNow(WidgetTester tester) {
    final RenderView view = tester.binding.renderViews.first;
    final ContainerLayer layer = view.debugLayer!;
    return layer.find<SystemUiOverlayStyle>(Offset(view.size.width / 2, 0));
  }

  void expectDarkIcons(WidgetTester tester, {required String where}) {
    expect(
      annotatedNow(tester)?.statusBarIconBrightness,
      Brightness.dark,
      reason: 'no dark-icon style is claimed at $where',
    );
    expect(lastStatusBarIcons(), 'Brightness.dark', reason: 'pushed at $where');
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final kana = await KanaProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    final words = await WordProgressRepository.load();
    final travel = await TravelFocusRepository.load();
    final recovery = await idleRestoreRecovery();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
            ),
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const KanaLoopApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the shared style asks for dark icons on light paper', () {
    expect(AppTheme.systemOverlay.statusBarIconBrightness, Brightness.dark);
    expect(AppTheme.systemOverlay.statusBarBrightness, Brightness.light);
    expect(
      AppTheme.light().appBarTheme.systemOverlayStyle,
      AppTheme.systemOverlay,
      reason:
          'a transparent AppBar would otherwise be guessed as dark and ask '
          'for light icons',
    );
  });

  testWidgets('home, 五十音図, a kana sheet and back all keep dark icons', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    // The home has no AppBar, so only a root annotation can claim this.
    expectDarkIcons(tester, where: 'the home at launch');

    await tester.tap(find.text(AppStrings.learnHiragana));
    await tester.pumpAndSettle();
    expect(find.byType(LearnScreen), findsOneWidget);
    expectDarkIcons(tester, where: '五十音図');

    await tester.tap(find.byType(KanaCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(KanaDetailSheet), findsOneWidget);
    expectDarkIcons(tester, where: 'an open kana sheet');

    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();
    expect(find.byType(KanaDetailSheet), findsNothing);
    expectDarkIcons(tester, where: '五十音図 after the sheet closes');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    // The reported symptom: without a root annotation nothing claims the bar
    // here, so the previous route's icons stay on a light page.
    expectDarkIcons(tester, where: 'the home after popping back');
  });
}
