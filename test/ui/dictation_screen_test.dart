// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('hear → assemble the kana → logs a dictation attempt', (
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
}
