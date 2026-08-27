// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// The home's repo → TrackDue summarising (home_screen._trackDue /
// _kanjiTrackDue) is the one hop between the repositories and Guidance that
// guidance_test's hand-fed TrackDues cannot see. Drive it end-to-end: real
// repositories, real stats, and assert the ambient line the learner reads.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    // Every row learned and no kana due → the kana era is quiet, so the
    // reading-era branches decide the line. Unlock lines already acknowledged —
    // this test is about the guidance step that lives in the same slot.
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
    for (final unlock in Unlock.values) {
      await kana.markUnlockSeen(unlock.id);
    }
    return (kana: kana, kanji: kanji, words: words);
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

  testWidgets('a due word routes the ambient line to 文字起こし', (tester) async {
    final repos = await kanaGraduated();
    // Met two days ago at level 1 (due after 1 day) → overdue now.
    await repos.words.recordAnswer(
      'word:いぬ',
      correct: true,
      at: DateTime.now().subtract(const Duration(days: 2)),
    );

    await pumpHome(tester, repos);

    expect(find.textContaining('等著再會'), findsOneWidget);
  });

  testWidgets('an older kanji due outranks a younger word due (fairness)', (
    tester,
  ) async {
    final repos = await kanaGraduated();
    await repos.words.recordAnswer(
      'word:いぬ',
      correct: true,
      at: DateTime.now().subtract(const Duration(days: 2)),
    );
    // The kanji reading has waited longer — its line wins even though the
    // words track has a due item too.
    await repos.kanji.recordAnswer(
      'reading:人#ひと',
      correct: true,
      at: DateTime.now().subtract(const Duration(days: 10)),
    );

    await pumpHome(tester, repos);

    expect(find.textContaining('個讀音該複習'), findsOneWidget);
    expect(find.textContaining('等著再會'), findsNothing);
  });

  testWidgets('nothing due yet: the line invites meeting new words', (
    tester,
  ) async {
    final repos = await kanaGraduated();

    await pumpHome(tester, repos);

    expect(find.textContaining('渡し舟'), findsWidgets);
    expect(find.textContaining('去見新的詞'), findsOneWidget);
  });
}
