// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

/// Home → 目利き → QuizScreen must stay inside the learned set.
/// Pure Confusable unit tests are not enough if Home still passes the
/// full gojūon.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<KanaProgressRepository> loadKana() => KanaProgressRepository.load();

  Future<void> markRows(
    KanaProgressRepository kana,
    Iterable<String> ids,
  ) async {
    for (final id in ids) {
      await kana.markUnitLearned(id);
    }
    for (final unlock in Unlock.values) {
      await kana.markUnlockSeen(unlock.id);
    }
  }

  Future<void> pumpHome(
    WidgetTester tester,
    KanaProgressRepository kana,
  ) async {
    final prefs = await PreferencesService.create();
    final kanji = await KanjiReadingRepository.load(prefs);
    final words = await WordProgressRepository.load(prefs);
    final recovery = recoveryForRepos(
      prefs: prefs,
      kana: kana,
      kanji: kanji,
      words: words,
    );
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final travel = await TravelFocusRepository.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
            ),
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectQuizInsideLearned(QuizScreen quiz, List<Kana> learned) {
    final learnedIds = learned.map((k) => k.id).toSet();
    final romajiByScript = <KanaScript, Set<String>>{};
    for (final k in learned) {
      romajiByScript.putIfAbsent(k.script, () => <String>{}).add(k.romaji);
    }
    expect(quiz.items, isNotEmpty);
    for (final item in quiz.items) {
      final q = item.question;
      expect(
        learnedIds.contains(q.target.id),
        isTrue,
        reason: 'unlearned target ${q.target.character}',
      );
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4);
      if (q.direction == QuizDirection.romajiToKana ||
          q.direction == QuizDirection.soundToKana) {
        for (final o in q.options) {
          expect(
            learnedIds.contains(o),
            isTrue,
            reason: 'unlearned option $o on ${q.target.character}',
          );
        }
      } else {
        final allowed = romajiByScript[q.target.script] ?? const <String>{};
        for (final o in q.options) {
          expect(
            allowed.contains(o),
            isTrue,
            reason: 'unlearned romaji $o on ${q.target.character}',
          );
        }
      }
    }
  }

  Future<QuizScreen> tapConfusable(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.confusableEntry));
    await tester.pumpAndSettle();
    return tester.widget<QuizScreen>(find.byType(QuizScreen));
  }

  testWidgets('first row: Home tap stays inside あいうえお', (tester) async {
    final kana = await loadKana();
    await markRows(kana, [Lessons.fromKana(kana.allKana).first.id]);
    final learned = StudySet.learned(kana);
    expect(learned.map((k) => k.id).toSet(), {'あ', 'い', 'う', 'え', 'お'});

    await pumpHome(tester, kana);
    final quiz = await tapConfusable(tester);
    final learnedIds = learned.map((k) => k.id).toSet();
    final unknown = quiz.items
        .where((i) => !learnedIds.contains(i.question.target.id))
        .toList();
    expect(unknown, isEmpty);
    expectQuizInsideLearned(quiz, learned);
  });

  testWidgets('several rows: no unlearned targets or kana options', (
    tester,
  ) async {
    final kana = await loadKana();
    final lessons = Lessons.fromKana(kana.allKana);
    await markRows(kana, lessons.take(4).map((l) => l.id));
    final learned = StudySet.learned(kana);
    expect(learned.length, 20);

    await pumpHome(tester, kana);
    expectQuizInsideLearned(await tapConfusable(tester), learned);
  });

  testWidgets('early katakana uses learned units, not any-katakana-seen', (
    tester,
  ) async {
    final kana = await loadKana();
    final lessons = Lessons.fromKana(kana.allKana);
    final hira0 = lessons.firstWhere((l) => l.id == 'hira_row_0');
    final kata0 = lessons.firstWhere((l) => l.id == 'kata_row_0');
    await markRows(kana, [hira0.id, kata0.id]);
    // A stray seen katakana outside the learned unit must not open the
    // whole katakana gojūon.
    final stray = kana
        .gojuonForScript(KanaScript.katakana)
        .firstWhere((k) => k.character == 'カ');
    await kana.recordAnswer(
      stray,
      correct: true,
      at: DateTime(2026, 9, 10),
      latencyMs: 400,
    );
    final learned = StudySet.learned(kana);
    final learnedIds = learned.map((k) => k.id).toSet();
    expect(learnedIds.contains('カ'), isFalse);
    expect(learnedIds.containsAll({'ア', 'イ', 'ウ', 'エ', 'オ'}), isTrue);

    await pumpHome(tester, kana);
    final quiz = await tapConfusable(tester);
    expectQuizInsideLearned(quiz, learned);
    for (final item in quiz.items) {
      expect(item.question.target.character, isNot('カ'));
    }
  });

  testWidgets('full gojūon sets stay inside learned characters', (
    tester,
  ) async {
    final kana = await loadKana();
    await markRows(kana, Lessons.fromKana(kana.allKana).map((l) => l.id));
    final learned = StudySet.learned(kana).where((k) => k.isGojuon).toList();

    await pumpHome(tester, kana);
    expectQuizInsideLearned(await tapConfusable(tester), learned);
  });
}
