// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/washi_background.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';
import '../support/restore_recovery_test_support.dart';

const _iosSwipeCaptureKey = Key('ios_edge_swipe_capture');

/// A screen point still covered by the sliding [LessonsScreen] after the second
/// mid-swipe delta. On the pre-washi iOS fallback (c306f403) Home's progress
/// ring accent bleeds through the transparent scaffold here.
const _lessonsMidSwipeOpaqueProbe = Offset(220, 420);

/// #141: the custom ink builder dropped iOS edge-swipe back. Host probe with
/// production App / Home / Lessons / AppTheme — not iPhone device acceptance
/// (that remains #13).
void main() {
  testWidgets('iOS Home→Lessons edge swipe pops back to Home', (tester) async {
    await _runIos(() async {
      await _pumpApp(tester);

      await tester.tap(find.text(AppStrings.learnNewKanaAction));
      await tester.pumpAndSettle();
      expect(find.byType(LessonsScreen), findsOneWidget);

      await _edgeSwipeBack(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LessonsScreen), findsNothing);
    });
  });

  testWidgets(
    'iOS Lessons mid edge swipe keeps opaque washi (no Home bleed-through)',
    (tester) async {
      await _runIos(() async {
        await _pumpApp(tester);

        await tester.tap(find.text(AppStrings.learnNewKanaAction));
        await tester.pumpAndSettle();
        expect(find.byType(LessonsScreen), findsOneWidget);

        final route = _lessonsRoute(tester);
        final gesture = await tester.startGesture(const Offset(1, 300));

        // First delta only hands the edge drag to Cupertino's recognizer.
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        expect(route.popGestureInProgress, isTrue);
        expect(tester.getTopLeft(find.byType(LessonsScreen)).dx, 0);

        // Second delta actually slides the route; Home may peek on the left.
        await gesture.moveBy(const Offset(120, 0));
        await tester.pump();
        expect(route.popGestureInProgress, isTrue);
        expect(
          tester.getTopLeft(find.byType(LessonsScreen)).dx,
          greaterThan(80),
        );

        final lessonsTransition = find.ancestor(
          of: find.byType(LessonsScreen),
          matching: find.byType(CupertinoPageTransition),
        );
        expect(
          find.descendant(
            of: lessonsTransition,
            matching: find.byType(WashiBackground),
          ),
          findsOneWidget,
        );

        final probeColor = await _sampleScreenPixel(
          tester,
          _lessonsMidSwipeOpaqueProbe,
        );
        expect(probeColor.alpha, 255);
        expect(
          _colorsNear(probeColor, AppColors.accent),
          isFalse,
          reason:
              'Home progress-ring accent bled through Lessons mid-swipe '
              '(transparent scaffold without route washi)',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byType(LessonsScreen), findsOneWidget);
      });
    },
  );

  testWidgets('iOS Home→Lessons short edge swipe cancels and stays', (
    tester,
  ) async {
    await _runIos(() async {
      await _pumpApp(tester);

      await tester.tap(find.text(AppStrings.learnNewKanaAction));
      await tester.pumpAndSettle();
      expect(find.byType(LessonsScreen), findsOneWidget);

      await _edgeSwipeCancel(tester);
      expect(find.byType(LessonsScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  });

  testWidgets('iOS Lessons AppBar back still returns Home', (tester) async {
    await _runIos(() async {
      await _pumpApp(tester);

      await tester.tap(find.text(AppStrings.learnNewKanaAction));
      await tester.pumpAndSettle();
      expect(find.byType(LessonsScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LessonsScreen), findsNothing);
    });
  });

  testWidgets(
    'iOS Study あ行 swipe-back stops leftover audio; cancel keeps the card',
    (tester) async {
      await _runIos(() async {
        final speech = HangingSpeechService();
        await _pumpApp(tester, speech: speech);

        await tester.tap(find.text(AppStrings.learnNewKanaAction));
        await tester.pumpAndSettle();
        await tester.tap(find.text('あ行'));
        await tester.pumpAndSettle();
        expect(find.byType(StudyScreen), findsOneWidget);
        expect(speech.spoken, ['あ']);
        expect(speech.stopCount, 0);

        await _edgeSwipeCancel(tester);
        expect(find.byType(StudyScreen), findsOneWidget);
        expect(find.byType(LessonsScreen), findsNothing);
        expect(speech.stopCount, 0);
        expect(speech.spoken, ['あ']);

        await _edgeSwipeBack(tester);
        expect(find.byType(LessonsScreen), findsOneWidget);
        expect(find.byType(StudyScreen), findsNothing);
        expect(speech.stopCount, greaterThan(0));
      });
    },
  );
}

/// Binding checks foundation debug vars after the test body, so the override
/// must be cleared before [_runIos] returns — not in package:test tearDown.
Future<void> _runIos(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

ModalRoute<void> _lessonsRoute(WidgetTester tester) {
  final route = ModalRoute.of(tester.element(find.byType(LessonsScreen)));
  expect(route, isNotNull);
  return route!;
}

Future<void> _edgeSwipeBack(WidgetTester tester) async {
  await tester.timedDragFrom(
    const Offset(1, 300),
    const Offset(340, 0),
    const Duration(milliseconds: 450),
  );
  await tester.pumpAndSettle();
}

Future<void> _edgeSwipeCancel(WidgetTester tester) async {
  await tester.timedDragFrom(
    const Offset(1, 300),
    const Offset(40, 0),
    const Duration(milliseconds: 450),
  );
  await tester.pumpAndSettle();
}

Future<Color> _sampleScreenPixel(WidgetTester tester, Offset position) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_iosSwipeCaptureKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final x = position.dx.floor().clamp(0, image!.width - 1);
  final y = position.dy.floor().clamp(0, image!.height - 1);
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    data!.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

bool _colorsNear(Color a, Color b, {int tolerance = 10}) {
  return (a.red - b.red).abs() <= tolerance &&
      (a.green - b.green).abs() <= tolerance &&
      (a.blue - b.blue).abs() <= tolerance;
}

Future<void> _pumpApp(WidgetTester tester, {SpeechService? speech}) async {
  // Issue #141 host probe: iPhone 14/15 logical size.
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({});
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final words = await WordProgressRepository.load();
  final recovery = await idleRestoreRecovery();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _iosSwipeCaptureKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
              health: [
                kana.statsHealth,
                kana.learnedUnitsHealth,
                kana.seenUnlocksHealth,
                kanji.statsHealth,
                words.statsHealth,
              ],
            ),
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
          Provider<SpeechService>.value(
            value: speech ?? const SilentSpeechService(),
          ),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const KanaLoopApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
