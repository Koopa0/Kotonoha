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
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    '手話で話す: accessible stems name different local words, not readings',
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
                title: AppStrings.kanjiTitle,
                rng: Random(0),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final text = tester.widget<Text>(
          find.byKey(KanjiQuizScreen.promptStemKey),
        );
        final label = text.semanticsLabel ?? '';
        labels.add(label);

        expect(label, isNotEmpty, reason: target.id);
        expect(
          label,
          AppStrings.kanjiAccessibleStem(
            sentence: KanjiPrompt.stemOf(target),
            localWord: KanjiPrompt.localWord(target),
            written: target.written,
          ),
        );
        expect(label, contains('手話で話す'));
        expect(
          label,
          isNot(contains(reading)),
          reason: 'must not leak $reading',
        );
      }

      expect(labels[0], isNot(labels[1]));
      expect(labels[0], contains('「手話」裡的「話」'));
      expect(labels[1], contains('「話す」裡的「話」'));
    },
  );
}
