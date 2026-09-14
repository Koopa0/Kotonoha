// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';
import '../support/restore_recovery_test_support.dart';

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
        expect(find.byType(ProgressRing), findsNothing);

        final gesture = await tester.startGesture(const Offset(1, 300));
        await gesture.moveBy(const Offset(140, 0));
        await tester.pump();

        expect(find.byType(LessonsScreen), findsOneWidget);
        expect(find.byType(ProgressRing), findsNothing);
        expect(find.text(AppStrings.learnNewKanaAction), findsNothing);

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
    MultiProvider(
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
  );
  await tester.pumpAndSettle();
}
