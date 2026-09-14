// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/theme/app_theme.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

/// #137 — production home filled CTA: 12px Japanese line stays 12px and
/// meets 4.5:1 on the actual button fill (rest / pressed / focused).
void main() {
  test('ColorScheme primary/onPrimary pairing meets 4.5:1', () {
    final scheme = AppTheme.light().colorScheme;
    expect(scheme.primary, AppColors.buttonFill);
    expect(scheme.onPrimary, AppColors.onButton);
    expect(
      _contrast(scheme.onPrimary, scheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(
        Color.alphaBlend(AppColors.onButtonMuted, scheme.primary),
        scheme.primary,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(AppColors.accent, const Color(0xFF5E9387));
  });

  testWidgets('FilledButton rest, pressed, and focused stay ≥4.5:1', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FilledButton(onPressed: () {}, child: const Text('稽古')),
        ),
      ),
    );
    final buttonFinder = find.byType(FilledButton);
    final context = tester.element(buttonFinder);
    final style = _mergedFilledStyle(
      context,
      tester.widget<FilledButton>(buttonFinder),
    );

    for (final states in <Set<WidgetState>>[
      <WidgetState>{},
      {WidgetState.pressed},
      {WidgetState.focused},
    ]) {
      final bg = _resolveFill(style, Theme.of(context).colorScheme, states);
      final fg = style.foregroundColor?.resolve(states) ?? AppColors.onButton;
      expect(
        _contrast(fg, bg),
        greaterThanOrEqualTo(4.5),
        reason: 'onPrimary vs fill $states',
      );
      expect(
        _contrast(Color.alphaBlend(AppColors.onButtonMuted, bg), bg),
        greaterThanOrEqualTo(4.5),
        reason: 'onButtonMuted vs fill $states',
      );
    }
  });

  testWidgets('returning home 今日の稽古 is 12px and ≥4.5:1 on the painted fill', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpReturningHome(tester);

    expect(find.text(AppStrings.dailySession), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);

    final subtitle = tester.widget<Text>(find.text(AppStrings.dailySession));
    expect(subtitle.style?.fontSize, 12);
    expect(subtitle.style?.fontWeight, FontWeight.w500);

    final title = tester.widget<Text>(find.text(AppStrings.reviewKanaAction));
    expect(
      title.style?.fontSize,
      isNull,
    ); // inherits FilledButton 17, not inflated

    final buttonFinder = find.ancestor(
      of: find.text(AppStrings.dailySession),
      matching: find.byType(FilledButton),
    );
    expect(buttonFinder, findsOneWidget);
    final context = tester.element(buttonFinder);
    final button = tester.widget<FilledButton>(buttonFinder);
    final style = _mergedFilledStyle(context, button);
    final scheme = Theme.of(context).colorScheme;

    final rawFg = subtitle.style!.color!;
    expect(rawFg.a, closeTo(0.82, 0.01));

    for (final states in <Set<WidgetState>>[
      <WidgetState>{},
      {WidgetState.pressed},
      {WidgetState.focused},
    ]) {
      final bg = _resolveFill(style, scheme, states);
      final fg = Color.alphaBlend(rawFg, bg);
      final ratio = _contrast(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '今日の稽古 vs fill $states → $ratio',
      );
      final titleColor =
          DefaultTextStyle.of(
            tester.element(find.text(AppStrings.reviewKanaAction)),
          ).style.color ??
          scheme.onPrimary;
      expect(
        _contrast(titleColor, bg),
        greaterThanOrEqualTo(4.5),
        reason: '假名複習 vs fill $states',
      );
    }

    final outlined = find.ancestor(
      of: find.text(AppStrings.continueLearning),
      matching: find.byType(OutlinedButton),
    );
    expect(outlined, findsOneWidget);
    final outlinedSubtitle = tester.widget<Text>(
      find.text(AppStrings.continueLearning),
    );
    expect(outlinedSubtitle.style?.fontSize, 12);
    expect(
      _contrast(AppColors.inkMuted, AppColors.paper),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('1.6x type on 320 keeps home actions and the 12px line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await _pumpReturningHome(tester, setSurface: false);
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.dailySession), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(AppStrings.dailySession)).style?.fontSize,
      12,
    );
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}

Future<void> _pumpReturningHome(
  WidgetTester tester, {
  bool setSurface = true,
}) async {
  if (setSurface) {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  SharedPreferences.setMockInitialValues({});
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final words = await WordProgressRepository.load();
  await kana.markUnitLearned('hira_row_0');
  for (final k in kana.gojuonForScript(KanaScript.hiragana).take(5)) {
    await kana.recordAnswer(
      k,
      correct: true,
      at: DateTime(2026),
      latencyMs: 300,
    );
  }
  final recovery = await idleRestoreRecovery();
  final travel = await TravelFocusRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
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
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

ButtonStyle _mergedFilledStyle(BuildContext context, FilledButton button) {
  final theme = Theme.of(context);
  return const ButtonStyle()
      .merge(theme.filledButtonTheme.style)
      .merge(button.style);
}

Color _resolveFill(
  ButtonStyle style,
  ColorScheme scheme,
  Set<WidgetState> states,
) {
  final bg = style.backgroundColor?.resolve(states) ?? scheme.primary;
  final overlay = style.overlayColor?.resolve(states);
  if (overlay == null || overlay.a == 0) return bg;
  return Color.alphaBlend(overlay, bg);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
