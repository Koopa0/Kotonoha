// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

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
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 漢字の声 honest flow: a never-seen reading is TAUGHT (ear-first, reading +
/// meaning shown), a seen reading is RECALLed cold (meaning hidden, choose the
/// reading from 4 options). No score on screen; no clock (latencyMs null).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 人 with two readings; ジン's example word differs from the reading, so the
  // reading text is unambiguous to find.
  const jin = Reading(
    text: 'ジン',
    kind: ReadingKind.on,
    exampleWord: 'がいこくじん',
    exampleMeaning: '外國人',
  );
  const entry = KanjiEntry(
    char: '人',
    meaningZh: '人、人類',
    readings: [
      Reading(text: 'ひと', kind: ReadingKind.kun),
      jin,
    ],
  );
  const readingId = 'reading:人#ジン';

  Future<void> pump(
    WidgetTester tester,
    KanjiReadingRepository repo,
    AnalyticsLog analytics,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: repo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: () async {},
              kanjiFlush: repo.flushPending,
              wordFlush: () async {},
            ),
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: MaterialApp(
          home: KanjiQuizScreen(
            prompts: const [KanjiPrompt(entry: entry, reading: jin)],
            title: AppStrings.kanjiTitle,
            rng: Random(1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a NEVER-SEEN reading is taught ear-first (reading + meaning shown)',
    (tester) async {
      final repo = await KanjiReadingRepository.load();
      final analytics = InMemoryAnalyticsLog();
      await pump(tester, repo, analytics); // empty repo → teach

      expect(find.text('人'), findsOneWidget);
      expect(find.text('ジン'), findsOneWidget); // the reading is shown (encode)
      expect(find.text('人、人類'), findsOneWidget); // meaning shown as context
      expect(find.text(AppStrings.kanjiChooseReading), findsNothing);
      expect(
        find.byType(AnswerOptionButton),
        findsNothing,
      ); // no test on first meet
      expect(find.textContaining('%'), findsNothing); // never a score

      await tester.tap(find.text(AppStrings.kanjiNext));
      await tester.pumpAndSettle();

      // The encode advanced the SRS (now seen) and logged a teach beat.
      expect(repo.statForReading(readingId).seenCount, 1);
      final logged = await analytics.all();
      expect(logged.single.meta['beat'], 'teach');
      expect(logged.single.correct, isTrue);
      expect(logged.single.rtMs, 0); // clock off — the kanji track is untimed
    },
  );

  testWidgets('a SEEN reading is recalled cold — meaning hidden, 4 options', (
    tester,
  ) async {
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    await repo.recordAnswer(readingId, correct: true, at: DateTime(2026, 6));
    await pump(tester, repo, analytics); // now seen → recall

    expect(find.text('人'), findsOneWidget);
    expect(find.text(AppStrings.kanjiOnyomi), findsOneWidget); // on/kun cue
    expect(find.text(AppStrings.kanjiChooseReading), findsOneWidget);
    // The owned-meaning crutch and the example (which contains the reading) are
    // ABSENT while asking — not merely dimmed.
    expect(find.text('人、人類'), findsNothing);
    expect(find.text('がいこくじん'), findsNothing);
    expect(find.byType(AnswerOptionButton), findsNWidgets(4));
    expect(find.textContaining('%'), findsNothing);

    // Pick the reading. After answering, the meaning is revealed as confirmation.
    await tester.tap(find.widgetWithText(AnswerOptionButton, 'ジン'));
    await tester.pumpAndSettle();
    expect(find.text('人、人類'), findsOneWidget); // now shown
    final logged = await analytics.all();
    expect(logged.single.meta['beat'], 'recall');
    expect(logged.single.correct, isTrue);
    expect(logged.single.itemType, ItemType.kanji);

    // Close in stillness — the count is the muted footnote, no %.
    await tester.tap(find.text(AppStrings.seeResults));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
