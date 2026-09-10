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
import 'package:kotonoha/kanji/ui/ruby_text.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final toshi = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#とし');
  final nen = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#ねん');
  final hi = kKanjiUnits.singleWhere((u) => u.id == 'unit:日#ひ');
  final nichi = kKanjiUnits.singleWhere((u) => u.id == 'unit:日#にち');

  testWidgets('answering ねん must not fade the untested とし reading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    final now = DateTime(2026, 9, 10);
    for (var i = 0; i < 2; i++) {
      await repo.recordAnswer(toshi.id, correct: true, at: now);
    }
    for (var i = 0; i < 6; i++) {
      await repo.recordAnswer(nen.id, correct: true, at: now);
    }
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<double> rubyOpacity() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RubyText(
              phrase: toshi.example,
              srsLevelOf: (id) => repo.statForUnit(id).srsLevel,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<Opacity>(
            find.ancestor(of: find.text('とし'), matching: find.byType(Opacity)),
          )
          .opacity;
    }

    final beforeToshi = repo.statForUnit(toshi.id);
    final beforeNen = repo.statForUnit(nen.id);
    final beforeOpacity = await rubyOpacity();
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
            units: [toshi, nen],
            title: 'probe',
            rng: Random(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(KanjiQuizScreen.promptStemKey))
          .textSpan!
          .toPlainText(),
      '毎年の秋',
    );
    await tester.tap(find.widgetWithText(AnswerOptionButton, 'ねん'));
    await tester.pumpAndSettle();
    final afterToshi = repo.statForUnit(toshi.id);
    final afterNen = repo.statForUnit(nen.id);
    final afterOpacity = await rubyOpacity();
    final attempt = (await analytics.all()).single;
    expect(
      afterOpacity,
      beforeOpacity,
      reason: 'No とし retrieval happened; a correct ねん answer must not remove the とし reading support',
    );
    expect(afterToshi.srsLevel, beforeToshi.srsLevel);
    expect(afterToshi.correctCount, beforeToshi.correctCount);
    expect(afterToshi.dueAt, beforeToshi.dueAt);
    expect(afterNen.correctCount, beforeNen.correctCount + 1);
    expect(attempt.itemId, nen.id);
    expect(attempt.meta['reading'], 'ねん');
    expect(attempt.meta['chosen'], 'ねん');
    expect(attempt.correct, isTrue);
    expect(attempt.meta['scheduled'], toshi.id);
  });

  testWidgets('answering とし credits とし and leaves ねん / its ruby alone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    final now = DateTime(2026, 9, 10);
    for (var i = 0; i < 2; i++) {
      await repo.recordAnswer(toshi.id, correct: true, at: now);
    }
    for (var i = 0; i < 6; i++) {
      await repo.recordAnswer(nen.id, correct: true, at: now);
    }
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<double> rubyOpacity() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RubyText(
              phrase: toshi.example,
              srsLevelOf: (id) => repo.statForUnit(id).srsLevel,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<Opacity>(
            find.ancestor(of: find.text('とし'), matching: find.byType(Opacity)),
          )
          .opacity;
    }

    final beforeToshi = repo.statForUnit(toshi.id);
    final beforeNen = repo.statForUnit(nen.id);
    final beforeOpacity = await rubyOpacity();
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
            units: [toshi, nen],
            title: 'probe',
            rng: Random(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AnswerOptionButton, 'とし'));
    await tester.pumpAndSettle();
    final afterToshi = repo.statForUnit(toshi.id);
    final afterNen = repo.statForUnit(nen.id);
    final afterOpacity = await rubyOpacity();
    final attempt = (await analytics.all()).single;
    expect(afterToshi.srsLevel, beforeToshi.srsLevel + 1);
    expect(afterToshi.correctCount, beforeToshi.correctCount + 1);
    expect(afterNen.srsLevel, beforeNen.srsLevel);
    expect(afterNen.correctCount, beforeNen.correctCount);
    expect(afterOpacity, 0);
    expect(beforeOpacity, 0.4);
    expect(attempt.itemId, toshi.id);
    expect(attempt.meta['reading'], 'とし');
    expect(attempt.meta['chosen'], 'とし');
    expect(attempt.correct, isTrue);
    expect(attempt.meta.containsKey('scheduled'), isFalse);
  });

  testWidgets('帰国の日: にち is still a real miss on ひ, not an alternate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    final now = DateTime(2026, 9, 10);
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(hi.id, correct: true, at: now);
      await repo.recordAnswer(nichi.id, correct: true, at: now);
    }
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<double> rubyOpacity() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RubyText(
              phrase: hi.example,
              srsLevelOf: (id) => repo.statForUnit(id).srsLevel,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<Opacity>(
            find.ancestor(of: find.text('ひ'), matching: find.byType(Opacity)),
          )
          .opacity;
    }

    final beforeHi = repo.statForUnit(hi.id);
    final beforeNichi = repo.statForUnit(nichi.id);
    final beforeOpacity = await rubyOpacity();
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
            units: [hi, nichi],
            title: 'probe',
            rng: Random(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(KanjiQuizScreen.promptStemKey))
          .textSpan!
          .toPlainText(),
      '帰国の日',
    );
    await tester.tap(find.widgetWithText(AnswerOptionButton, 'にち'));
    await tester.pumpAndSettle();
    final afterHi = repo.statForUnit(hi.id);
    final afterNichi = repo.statForUnit(nichi.id);
    final afterOpacity = await rubyOpacity();
    final attempt = (await analytics.all()).single;
    expect(afterHi.srsLevel, 0);
    expect(afterHi.wrongCount, beforeHi.wrongCount + 1);
    expect(afterNichi.srsLevel, beforeNichi.srsLevel);
    expect(afterNichi.correctCount, beforeNichi.correctCount);
    expect(afterOpacity, 1);
    expect(beforeOpacity, 0);
    expect(attempt.itemId, hi.id);
    expect(attempt.meta['reading'], 'ひ');
    expect(attempt.meta['chosen'], 'にち');
    expect(attempt.correct, isFalse);
  });
}
