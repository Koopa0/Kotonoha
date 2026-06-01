// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reveal → self-grade records the reading and reaches summary', (
    tester,
  ) async {
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    const entry = KanjiEntry(
      char: '人',
      meaningZh: '人、人類',
      readings: [
        Reading(text: 'ひと', kind: ReadingKind.kun),
        Reading(
          text: 'ジン',
          kind: ReadingKind.on,
          exampleWord: 'がいこくじん',
          exampleMeaning: '外國人',
        ),
      ],
    );
    final prompts = [KanjiPrompt(entry: entry, reading: entry.readings[1])];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: repo),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: MaterialApp(
          home: KanjiQuizScreen(prompts: prompts, title: AppStrings.kanjiTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Prompt: kanji + on-yomi cue; the reading itself is hidden.
    expect(find.text('人'), findsOneWidget);
    expect(find.text(AppStrings.kanjiOnyomi), findsOneWidget);
    expect(find.text('ジン'), findsNothing);

    await tester.tap(find.text(AppStrings.kanjiReveal));
    await tester.pumpAndSettle();
    expect(find.text('ジン'), findsOneWidget);
    // "also reads ひと" teaching line.
    expect(find.text(AppStrings.kanjiAlsoReads('ひと')), findsOneWidget);

    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);

    // Per-reading stat + a kanji-typed Attempt were recorded.
    expect(repo.statForReading('reading:人#ジン').correctCount, 1);
    final logged = await analytics.all();
    expect(logged.single.itemType, ItemType.kanji);
    expect(logged.single.itemId, 'reading:人#ジン');
  });
}
