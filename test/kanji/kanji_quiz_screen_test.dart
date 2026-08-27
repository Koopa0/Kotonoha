// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 漢字の声 honest flow, now drilled in WORDS: a never-met unit is TAUGHT
/// (ear-first, the reading and the sentence it lives in shown), a met unit is
/// RECALLed cold (choose the reading; nothing but the written word on screen).
/// No score anywhere; no clock.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A compound whose reading cannot be assembled character by character — the
  // case the per-character model could not represent at all.
  const example = KanjiPhrase(
    segments: [
      RubySegment(text: '学校', furigana: 'がっこう'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'く'),
    ],
    romaji: 'gakkou e iku',
    meaning: '去學校',
  );
  const unit = KanjiUnit(written: '学校', reading: 'がっこう', example: example);
  final unitId = unit.id;

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
            units: const [unit],
            title: AppStrings.kanjiTitle,
            rng: Random(1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a NEVER-MET unit is taught ear-first, in its sentence', (
    tester,
  ) async {
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    await pump(tester, repo, analytics); // empty repo → teach

    expect(find.text('学校'), findsOneWidget);
    expect(find.text('がっこう'), findsOneWidget); // the reading is shown (encode)
    // A reading is never met stripped of the word it lives in.
    expect(find.text('学校へ行く'), findsOneWidget);
    expect(find.text('去學校'), findsOneWidget);
    expect(find.text(AppStrings.kanjiChooseReading), findsNothing);
    expect(find.byType(AnswerOptionButton), findsNothing); // no test on meeting
    expect(find.textContaining('%'), findsNothing); // never a score

    await tester.tap(find.text(AppStrings.kanjiNext));
    await tester.pumpAndSettle();

    // The encode advanced the SRS (now seen) and logged a teach beat.
    expect(repo.statForUnit(unitId).seenCount, 1);
    final logged = await analytics.all();
    expect(logged.single.meta['beat'], 'teach');
    expect(logged.single.itemId, unitId);
    expect(logged.single.correct, isTrue);
    expect(logged.single.rtMs, 0); // clock off — the kanji track is untimed
  });

  testWidgets('a MET unit is recalled cold — the word alone, then options', (
    tester,
  ) async {
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    await repo.recordAnswer(unitId, correct: true, at: DateTime(2026, 6));
    await pump(tester, repo, analytics); // now seen → recall

    expect(find.text('学校'), findsOneWidget);
    expect(find.text(AppStrings.kanjiChooseReading), findsOneWidget);
    // While ASKING, the context is ABSENT — not merely dimmed. The reading
    // appears exactly once, as one option among four, never also as a label.
    expect(find.text('学校へ行く'), findsNothing);
    expect(find.text('去學校'), findsNothing);
    expect(find.text('がっこう'), findsOneWidget);
    expect(find.byType(AnswerOptionButton), findsNWidgets(4));
    expect(find.textContaining('%'), findsNothing);

    // Pick the reading. The context returns afterwards as confirmation.
    await tester.tap(find.widgetWithText(AnswerOptionButton, 'がっこう'));
    await tester.pumpAndSettle();
    expect(find.text('学校へ行く'), findsOneWidget);
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
