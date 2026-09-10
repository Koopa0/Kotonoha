// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #15: Home guidance → tap → the kanji session the line promised.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
    })
  >
  kanaGraduated() async {
    final kana = await KanaProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    final words = await WordProgressRepository.load();
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
    for (final unlock in Unlock.values) {
      await kana.markUnlockSeen(unlock.id);
    }
    return (kana: kana, kanji: kanji, words: words);
  }

  Future<void> openOtherTracks(
    ({
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
    })
    repos,
  ) async {
    final justNow = DateTime.now().subtract(const Duration(minutes: 5));
    await repos.words.recordAnswer(
      kWords.first.progressId,
      correct: true,
      at: justNow,
    );
    await repos.words.recordAnswer(
      kPhrases.first.progressId,
      correct: true,
      at: justNow,
    );
    await repos.words.recordAnswer(
      kKanjiPhrases.first.progressId,
      correct: true,
      at: justNow,
    );
  }

  Future<void> pumpHome(
    WidgetTester tester,
    ({
      KanaProgressRepository kana,
      KanjiReadingRepository kanji,
      WordProgressRepository words,
    })
    repos,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(
            value: repos.kana,
          ),
          ChangeNotifierProvider<KanjiReadingRepository>.value(
            value: repos.kanji,
          ),
          ChangeNotifierProvider<WordProgressRepository>.value(
            value: repos.words,
          ),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: repos.kana.flushPending,
              kanjiFlush: repos.kanji.flushPending,
              wordFlush: repos.words.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('review line opens due recalls, not a session of new teach', (
    tester,
  ) async {
    final repos = await kanaGraduated();
    await openOtherTracks(repos);
    final overdue = DateTime.now().subtract(const Duration(days: 2));
    final due = kKanjiUnits.take(12).toList();
    for (final u in due) {
      await repos.kanji.recordAnswer(u.id, correct: true, at: overdue);
    }

    await pumpHome(tester, repos);
    expect(find.textContaining('個讀音該複習'), findsOneWidget);

    await tester.tap(find.textContaining('個讀音該複習'));
    await tester.pumpAndSettle();

    final quiz = tester.widget<KanjiQuizScreen>(find.byType(KanjiQuizScreen));
    expect(quiz.units.length, 12);
    expect(
      quiz.units.every((u) => repos.kanji.statForUnit(u.id).isSeen),
      isTrue,
    );
    expect(quiz.units.map((u) => u.id).toSet(), {for (final u in due) u.id});
    expect(find.text(AppStrings.kanjiChooseReading), findsOneWidget);
    expect(find.text(AppStrings.kanjiTeachHint), findsNothing);
    expect(find.byType(AnswerOptionButton), findsWidgets);
  });

  testWidgets('meet line opens a teach beat for unmet units', (tester) async {
    final repos = await kanaGraduated();
    await openOtherTracks(repos);
    // Kanji never opened → D0 meet 漢字の声.

    await pumpHome(tester, repos);
    expect(find.text(AppStrings.guidanceMeetKanji), findsOneWidget);

    await tester.tap(find.text(AppStrings.guidanceMeetKanji));
    await tester.pumpAndSettle();

    final quiz = tester.widget<KanjiQuizScreen>(find.byType(KanjiQuizScreen));
    expect(quiz.units.length, KanjiSession.kDefaultMaxNew);
    expect(
      quiz.units.every((u) => !repos.kanji.statForUnit(u.id).isSeen),
      isTrue,
    );
    expect(find.text(AppStrings.kanjiTeachHint), findsOneWidget);
    expect(find.text(AppStrings.kanjiChooseReading), findsNothing);
    expect(find.byType(AnswerOptionButton), findsNothing);
  });
}
