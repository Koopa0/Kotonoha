// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #17: a recall of 日 must show 帰国の日 before the answer, so picking the
/// other taught reading is a real miss and picking ひ is not punished.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final hi = kKanjiUnits.singleWhere((u) => u.id == 'unit:日#ひ');
  final nichi = kKanjiUnits.singleWhere((u) => u.id == 'unit:日#にち');
  final kuru = kKanjiUnits.singleWhere((u) => u.id == 'unit:来#く');
  final ki = kKanjiUnits.singleWhere((u) => u.id == 'unit:来#き');
  final rai = kKanjiUnits.singleWhere((u) => u.id == 'unit:来#らい');
  final au = kKanjiUnits.singleWhere((u) => u.id == 'unit:会#あ');
  final kai = kKanjiUnits.singleWhere((u) => u.id == 'unit:会#かい');

  Future<({KanjiReadingRepository repo, InMemoryAnalyticsLog analytics})>
  pumpSession(
    WidgetTester tester, {
    required List<KanjiUnit> units,
    Random? rng,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    final now = DateTime(2026, 9, 10);
    for (final u in units) {
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(u.id, correct: true, at: now);
      }
    }
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
            units: units,
            title: AppStrings.kanjiTitle,
            rng: rng ?? Random(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (repo: repo, analytics: analytics);
  }

  String stemOf(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(KanjiQuizScreen.promptStemKey));
    return text.textSpan!.toPlainText();
  }

  testWidgets('日#ひ shows 帰国の日; picking ひ is correct and keeps the Leitner', (
    tester,
  ) async {
    final seeded = await pumpSession(
      tester,
      units: [hi, nichi],
      rng: Random(0),
    );
    final before = seeded.repo.statForUnit(hi.id);

    expect(find.text('日'), findsOneWidget);
    expect(stemOf(tester), KanjiPrompt.stemOf(hi));
    expect(stemOf(tester), '帰国の日');
    expect(find.text(hi.example.meaning), findsNothing);
    expect(find.text(hi.reading), findsOneWidget); // option only
    expect(find.widgetWithText(AnswerOptionButton, 'ひ'), findsOneWidget);
    expect(find.widgetWithText(AnswerOptionButton, 'にち'), findsOneWidget);

    await tester.tap(find.widgetWithText(AnswerOptionButton, 'ひ'));
    await tester.pumpAndSettle();

    final after = seeded.repo.statForUnit(hi.id);
    final attempts = await seeded.analytics.all();
    expect(attempts.single.correct, isTrue);
    expect(after.wrongCount, before.wrongCount);
    expect(after.srsLevel, greaterThan(before.srsLevel));
    expect(find.text(hi.example.meaning), findsOneWidget);
  });

  testWidgets('日#ひ with context: にち is a real miss, not a hidden-stem trap', (
    tester,
  ) async {
    final seeded = await pumpSession(
      tester,
      units: [hi, nichi],
      rng: Random(0),
    );
    expect(stemOf(tester), '帰国の日');

    await tester.tap(find.widgetWithText(AnswerOptionButton, 'にち'));
    await tester.pumpAndSettle();

    final after = seeded.repo.statForUnit(hi.id);
    final attempts = await seeded.analytics.all();
    expect(attempts.single.correct, isFalse);
    expect(after.wrongCount, 1);
    expect(after.srsLevel, 0);
    expect(seeded.repo.statForUnit(nichi.id).srsLevel, 3);
  });

  testWidgets('毎年の秋: ねん is legal and does not drop the Leitner', (
    tester,
  ) async {
    final toshi = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#とし');
    final nen = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#ねん');
    final seeded = await pumpSession(
      tester,
      units: [toshi, nen],
      rng: Random(0),
    );
    final before = seeded.repo.statForUnit(toshi.id);

    expect(stemOf(tester), '毎年の秋');
    expect(find.widgetWithText(AnswerOptionButton, 'ねん'), findsOneWidget);
    expect(find.widgetWithText(AnswerOptionButton, 'とし'), findsOneWidget);

    await tester.tap(find.widgetWithText(AnswerOptionButton, 'ねん'));
    await tester.pumpAndSettle();

    final after = seeded.repo.statForUnit(toshi.id);
    final attempts = await seeded.analytics.all();
    expect(attempts.single.correct, isTrue);
    expect(after.wrongCount, before.wrongCount);
    expect(after.srsLevel, greaterThan(before.srsLevel));
  });

  testWidgets('来 / 会 stems are visible before the answer', (tester) async {
    for (final unit in [kuru, au]) {
      SharedPreferences.setMockInitialValues({});
      final repo = await KanjiReadingRepository.load();
      await repo.recordAnswer(
        unit.id,
        correct: true,
        at: DateTime(2026, 9, 10),
      );
      await tester.binding.setSurfaceSize(const Size(420, 1400));
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
            Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
            Provider<SpeechService>.value(value: const SilentSpeechService()),
          ],
          child: MaterialApp(
            home: KanjiQuizScreen(
              key: UniqueKey(),
              units: [unit, ki, rai, kai],
              title: AppStrings.kanjiTitle,
              rng: Random(1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(stemOf(tester), KanjiPrompt.stemOf(unit), reason: unit.id);
      final labels = tester
          .widgetList<AnswerOptionButton>(find.byType(AnswerOptionButton))
          .map((b) => b.label);
      expect(labels, contains(unit.reading), reason: unit.id);
      expect(find.text(unit.example.meaning), findsNothing, reason: unit.id);
    }
  });
}
