// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hear → assemble the kana → logs a dictation attempt', (
    tester,
  ) async {
    // Fresh store (seenCount 0) keeps the occasional 凪 余韻 out of this flow test.
    final store = await KanaProgressRepository.load();
    final analytics = InMemoryAnalyticsLog();
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: DictationScreen(words: words, title: AppStrings.dictationTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the き then み tiles (distractors never include the word's own kana).
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('み'));
    await tester.pumpAndSettle();

    // Auto-checked at full length → result + next.
    expect(find.text(AppStrings.dictationNext), findsOneWidget);
    final logged = await analytics.all();
    expect(logged.single.mode, PracticeMode.dictation.name);
    expect(logged.single.correct, isTrue);
    expect(logged.single.itemId, 'きみ');

    await tester.tap(find.text(AppStrings.dictationNext));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);
  });

  testWidgets('wrong assembly is graded incorrect and reveals the answer', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: DictationScreen(words: words, title: AppStrings.dictationTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Assemble in the wrong order: み then き → みき ≠ きみ.
    await tester.tap(find.text('み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();

    // Graded incorrect; the correct answer's kana + romaji + meaning is revealed.
    expect((await analytics.all()).single.correct, isFalse);
    expect(find.text('きみ'), findsOneWidget);
    expect(find.text('kimi'), findsOneWidget);
    expect(find.text('你'), findsOneWidget);
    expect(find.text(AppStrings.dictationNext), findsOneWidget);
  });

  testWidgets('rtMs times the assembly from the injected clock', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    var now = DateTime(2026, 6);
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: MaterialApp(
          home: DictationScreen(
            words: words,
            title: AppStrings.dictationTitle,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    now = now.add(const Duration(milliseconds: 1200)); // time spent assembling
    await tester.tap(find.text('き'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('み'));
    await tester.pumpAndSettle();

    expect((await analytics.all()).single.rtMs, 1200);
  });
}
