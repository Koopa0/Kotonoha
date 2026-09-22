// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final id in [
    'unit:空港#くうこう',
    'unit:飛行機#ひこうき',
    'unit:荷物#にもつ',
    'unit:改札#かいさつ',
    'unit:予約#よやく',
    'unit:両替#りょうがえ',
  ]) {
    testWidgets(
      '$id moves from introduction to independent kanji recall at 320px / 2x',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final unit = kKanjiUnits.singleWhere((u) => u.id == id);
        final words = await WordProgressRepository.load();
        await words.introduce('word:${unit.reading}', at: DateTime(2026, 9));
        final wordBefore = words.statForItem('word:${unit.reading}').srsLevel;
        final kanji = await KanjiReadingRepository.load();
        final analytics = InMemoryAnalyticsLog();
        expect(kanji.statForUnit(id).isSeen, isFalse);

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<KanjiReadingRepository>.value(
                  value: kanji,
                ),
                ChangeNotifierProvider<ProgressPersistenceController>(
                  create: (_) => ProgressPersistenceController(
                    kanaFlush: () async {},
                    kanjiFlush: kanji.flushPending,
                    wordFlush: words.flushPending,
                  ),
                ),
                Provider<AnalyticsLog>.value(value: analytics),
                Provider<SpeechService>.value(
                  value: const SilentSpeechService(),
                ),
              ],
              child: MaterialApp(
                home: KanjiQuizScreen(
                  units: [unit],
                  title: AppStrings.kanjiTitle,
                  rng: Random(1),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await open();
        expect(find.text(unit.written), findsOneWidget);
        expect(find.text(unit.reading), findsOneWidget);
        expect(find.text(unit.example.written), findsOneWidget);
        expect(find.byType(AnswerOptionButton), findsNothing);
        await tester.tap(find.text(AppStrings.kanjiNext));
        await tester.pumpAndSettle();
        expect(kanji.statForUnit(id).isSeen, isTrue);
        final afterTeach = kanji.statForUnit(id).srsLevel;
        await open();
        expect(find.text(unit.example.meaning), findsNothing);
        expect(
          find.byType(AnswerOptionButton).evaluate().length,
          inInclusiveRange(2, 4),
        );
        expect(find.text(unit.reading), findsOneWidget);
        final answer = find.widgetWithText(AnswerOptionButton, unit.reading);
        await tester.ensureVisible(answer);
        await tester.pumpAndSettle();
        await tester.tap(answer);
        await tester.pumpAndSettle();
        expect(find.text(unit.example.meaning), findsOneWidget);
        expect(kanji.statForUnit(id).srsLevel, afterTeach + 1);
        expect(words.statForItem('word:${unit.reading}').srsLevel, wordBefore);
        expect((await analytics.all()).map((a) => a.meta['beat']), [
          'teach',
          'recall',
        ]);
        await kanji.flushPending();
        expect(
          (await KanjiReadingRepository.load()).statForUnit(id).srsLevel,
          afterTeach + 1,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
