// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('hear → see → read-back advances and logs a ferry attempt', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    const words = [
      Word(kana: 'きみ', romaji: 'kimi', meaning: '你'),
      Word(kana: 'やま', romaji: 'yama', meaning: '山'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: FerryScreen(words: words, title: AppStrings.ferryTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> oneWord() async {
      // Beat 1: hear — the kana is hidden.
      expect(find.text(AppStrings.ferryHear), findsOneWidget);
      await tester.tap(find.text(AppStrings.ferryShowText));
      await tester.pumpAndSettle();
      // Beat 2: the kana has inked in.
      expect(find.text(AppStrings.ferrySee), findsOneWidget);
      await tester.tap(find.text(AppStrings.ferryReadSelf));
      await tester.pumpAndSettle();
      // Beat 3: read back.
      expect(find.text(AppStrings.ferryReadback), findsOneWidget);
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
    }

    // First word hides its kana on beat 1.
    expect(find.text('きみ'), findsNothing);
    await oneWord();
    await oneWord();

    expect(find.text(AppStrings.readingSummary(2, 2)), findsOneWidget);
    final logged = await analytics.all();
    expect(logged.length, 2);
    expect(logged.every((a) => a.mode == PracticeMode.ferry.name), isTrue);
    expect(logged.first.itemId, 'きみ');
  });
}
