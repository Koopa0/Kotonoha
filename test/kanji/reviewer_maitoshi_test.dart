// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'actual corpus 毎年 remains linguistically ambiguous after context fix',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final target = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#とし');
      final other = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#ねん');
      final repo = await KanjiReadingRepository.load();
      final analytics = InMemoryAnalyticsLog();
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(
          target.id,
          correct: true,
          at: DateTime(2026, 9, 10),
        );
        await repo.recordAnswer(
          other.id,
          correct: true,
          at: DateTime(2026, 9, 10),
        );
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
              units: [target, other],
              title: 'probe',
              rng: Random(0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('年'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(KanjiQuizScreen.promptStemKey))
            .textSpan!
            .toPlainText(),
        '毎年の秋',
      );
      expect(KanjiPrompt.uniquelySelects(target), isFalse);
      expect(find.widgetWithText(AnswerOptionButton, 'ねん'), findsOneWidget);
      expect(find.widgetWithText(AnswerOptionButton, 'とし'), findsOneWidget);
      await tester.tap(find.widgetWithText(AnswerOptionButton, 'ねん'));
      await tester.pumpAndSettle();
      final after = repo.statForUnit(target.id);
      expect(
        after.wrongCount,
        0,
        reason: 'まいねん is a valid reading of 毎年; adding の秋 does not select only まいとし',
      );
    },
  );
}
