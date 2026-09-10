// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'both 話 prompts have identical accessible stem despite different targets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final labels = <String>[];
      for (final reading in ['わ', 'はな']) {
        SharedPreferences.setMockInitialValues({});
        final target = kKanjiUnits.singleWhere(
          (u) => u.id == 'unit:話#$reading',
        );
        final repo = await KanjiReadingRepository.load();
        await repo.recordAnswer(
          target.id,
          correct: true,
          at: DateTime(2026, 9, 10),
        );
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
                units: [target],
                title: 'probe',
                rng: Random(0),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final data = tester
            .getSemantics(find.byKey(KanjiQuizScreen.promptStemKey))
            .getSemanticsData();
        labels.add(data.label);
      }
      expect(
        labels[0],
        isNot(labels[1]),
        reason:
            'Nonvisual users need to know which occurrence of 話 is being asked',
      );
    },
  );
}
