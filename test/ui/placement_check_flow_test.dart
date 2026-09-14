// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/placement/placement_check_screen.dart';
import 'package:kotonoha/ui/placement/placement_result_screen.dart';
import 'package:kotonoha/ui/placement/placement_scope_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('beginner 手解き path still teaches first — romaji is shown', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.text(AppStrings.learnNewKanaAction));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
    expect(find.text(AppStrings.placementEntry), findsOneWidget);
    expect(find.text(AppStrings.placementStart), findsNothing);

    await tester.tap(find.text('あ行'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.text('あ'), findsWidgets);
    expect(find.text('a'), findsOneWidget);
    expect(find.text(AppStrings.placementUnknown), findsNothing);
  });

  testWidgets('placement asks first; no one-tap all-fluent', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text(AppStrings.learnNewKanaAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.placementEntry));
    await tester.pumpAndSettle();
    expect(find.byType(PlacementScopeScreen), findsOneWidget);
    expect(find.text(AppStrings.placementIntro), findsOneWidget);
    expect(find.text('全部會了'), findsNothing);
    expect(find.text('一鍵全熟'), findsNothing);

    await tester.tap(find.text(AppStrings.placementStart));
    await tester.pumpAndSettle();
    expect(find.byType(PlacementCheckScreen), findsNothing);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'あ行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.placementStart));
    await tester.pumpAndSettle();

    expect(find.byType(PlacementCheckScreen), findsOneWidget);
    expect(find.text('あ'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    expect(find.text(AppStrings.readPrompt), findsOneWidget);
    expect(find.text(AppStrings.placementUnknown), findsOneWidget);
  });

  testWidgets(
    'partial familiarity: independent / prompted / unknown stay split',
    (tester) async {
      final repos = await _pumpApp(tester);
      await _openAoCheck(tester);

      await _independentCorrect(tester);
      await tester.tap(find.text(AppStrings.continueLabel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.recallHint));
      await tester.pumpAndSettle();
      expect(find.text('i'), findsOneWidget);
      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.continueLabel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.placementUnknown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.continueLabel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.placementUnknown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.continueLabel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.placementUnknown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.seeResults));
      await tester.pumpAndSettle();

      expect(find.byType(PlacementResultScreen), findsOneWidget);
      expect(find.text(AppStrings.placementClose), findsOneWidget);
      expect(find.text(AppStrings.placementIndependent), findsOneWidget);
      expect(find.text(AppStrings.placementPrompted), findsOneWidget);
      expect(find.text(AppStrings.placementForgotten), findsOneWidget);
      expect(find.text('%'), findsNothing);
      expect(find.textContaining('XP'), findsNothing);
      expect(repos.kana.isUnitLearned('hira_row_0'), isFalse);
      expect(repos.kana.statFor(_kanaOf(repos.kana, 'あ')).correctCount, 1);
      expect(repos.kana.statFor(_kanaOf(repos.kana, 'い')).correctCount, 0);
      expect(repos.kana.statFor(_kanaOf(repos.kana, 'い')).seenCount, 1);
      expect(repos.kana.statFor(_kanaOf(repos.kana, 'う')).wrongCount, 1);
      expect(
        StudySet.learned(repos.kana).map((k) => k.character),
        isNot(contains('さ')),
      );
      expect(find.text(AppStrings.placementNextFill), findsOneWidget);

      await tester.tap(find.text(AppStrings.placementNextFill));
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsOneWidget);
      expect(find.text('い'), findsOneWidget);
      expect(find.text('i'), findsOneWidget);
      expect(find.text('あ'), findsNothing);
    },
  );

  testWidgets('mid-exit resume does not invent the unanswered kana', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    await _openAoCheck(tester);
    await tester.tap(find.text(AppStrings.placementUnknown));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(PlacementScopeScreen), findsOneWidget);
    expect(repos.kana.statFor(_kanaOf(repos.kana, 'あ')).wrongCount, 1);
    expect(repos.kana.statFor(_kanaOf(repos.kana, 'い')).seenCount, 0);

    final persisted = await PlacementCheckRepository.load();
    expect(persisted.draft.records.single.kanaId, 'あ');
    expect(persisted.draft.pendingKanaIds.first, 'い');
    expect(persisted.draft.pendingKanaIds, isNot(contains('あ')));

    await tester.tap(find.text(AppStrings.placementResume));
    await tester.pumpAndSettle();
    expect(find.byType(PlacementCheckScreen), findsOneWidget);
    expect(find.text('い'), findsOneWidget);
    expect(find.text('あ'), findsNothing);
    expect(find.text('i'), findsNothing);
  });

  testWidgets('all-independent row marks learned; unselected stays out', (
    tester,
  ) async {
    final repos = await _pumpApp(tester);
    await _openAoCheck(tester);
    for (var i = 0; i < 5; i++) {
      await _independentCorrect(tester);
      await tester.tap(
        find.text(i == 4 ? AppStrings.seeResults : AppStrings.continueLabel),
      );
      await tester.pumpAndSettle();
    }

    expect(find.byType(PlacementResultScreen), findsOneWidget);
    await tester.pump();
    expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
    expect(repos.kana.isUnitLearned('hira_row_1'), isFalse);
    expect(StudySet.learned(repos.kana).map((k) => k.character).toSet(), {
      'あ',
      'い',
      'う',
      'え',
      'お',
    });
    expect(find.text(AppStrings.placementNextDaily), findsOneWidget);
    expect(find.text(AppStrings.placementNextFill), findsNothing);

    await tester.tap(find.text(AppStrings.placementNextDaily));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
  });

  testWidgets(
    'needsRecovery blocks placement flow entry and completion without false success',
    (tester) async {
      final repos = await _pumpApp(tester, needsRecovery: true);

      // Home learning buttons are blocked
      await tester.tap(find.text(AppStrings.learnNewKanaAction));
      await tester.pumpAndSettle();
      expect(find.byType(LessonsScreen), findsNothing);

      // 1. LessonsScreen directly: placement entry is blocked when needsRecovery is true
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
            ChangeNotifierProvider<PlacementCheckRepository>.value(
              value: await PlacementCheckRepository.load(),
            ),
            ChangeNotifierProvider<ProgressPersistenceController>.value(
              value: ProgressPersistenceController(
                kanaFlush: repos.kana.flushPending,
                kanjiFlush: repos.kanji.flushPending,
                wordFlush: repos.words.flushPending,
              ),
            ),
            ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
              value: repos.recovery,
            ),
            Provider<SpeechService>.value(value: const SilentSpeechService()),
            Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          ],
          child: const MaterialApp(home: LessonsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LessonsScreen), findsOneWidget);
      await tester.tap(find.text(AppStrings.placementEntry));
      await tester.pumpAndSettle();
      expect(find.byType(PlacementScopeScreen), findsNothing);

      // 2. Direct PlacementScopeScreen with needsRecovery blocks starting checks
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
            ChangeNotifierProvider<PlacementCheckRepository>.value(
              value: await PlacementCheckRepository.load(),
            ),
            ChangeNotifierProvider<ProgressPersistenceController>.value(
              value: ProgressPersistenceController(
                kanaFlush: repos.kana.flushPending,
                kanjiFlush: repos.kanji.flushPending,
                wordFlush: repos.words.flushPending,
              ),
            ),
            ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
              value: repos.recovery,
            ),
            Provider<SpeechService>.value(value: const SilentSpeechService()),
            Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          ],
          child: const MaterialApp(home: PlacementScopeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CheckboxListTile, 'あ行'));
      await tester.pumpAndSettle();
      // Button disabled because blocked
      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, AppStrings.placementStart),
      );
      expect(startButton.onPressed, isNull);

      // 3. Attempting placement result screen completion under blocking journal
      // preserves draft and does not modify learned_units (no false success)
      final catalog = Lessons.fromKana(repos.kana.allKana);
      final draft = PlacementCheck.record(
        PlacementCheck.record(
          PlacementCheck.record(
            PlacementCheck.record(
              PlacementCheck.record(
                PlacementCheck.start([catalog.first])!,
                'あ',
                PlacementOutcome.independent,
              ),
              'い',
              PlacementOutcome.independent,
            ),
            'う',
            PlacementOutcome.independent,
          ),
          'え',
          PlacementOutcome.independent,
        ),
        'お',
        PlacementOutcome.independent,
      );
      final checkRepo = await PlacementCheckRepository.load();
      await checkRepo.save(draft);

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
            ChangeNotifierProvider<PlacementCheckRepository>.value(
              value: checkRepo,
            ),
            ChangeNotifierProvider<ProgressPersistenceController>.value(
              value: ProgressPersistenceController(
                kanaFlush: repos.kana.flushPending,
                kanjiFlush: repos.kanji.flushPending,
                wordFlush: repos.words.flushPending,
                placementFlush: checkRepo.flushPending,
              ),
            ),
            ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
              value: repos.recovery,
            ),
            Provider<SpeechService>.value(value: const SilentSpeechService()),
            Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          ],
          child: MaterialApp(
            home: PlacementResultScreen(draft: draft, checks: checkRepo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Row must NOT be marked learned, draft must NOT be cleared
      expect(repos.kana.isUnitLearned('hira_row_0'), isFalse);
      expect(repos.kana.learnedUnitCount, 0);
      expect(checkRepo.draft.hasProgress, isTrue);

      // 4. Retry recovery clearing needsRecovery unblocks applying and marks row learned
      await repos.recovery.retry();
      await tester.pumpAndSettle();
      expect(repos.kana.isUnitLearned('hira_row_0'), isTrue);
      expect(repos.kana.learnedUnitCount, 1);
    },
  );
}

Kana _kanaOf(KanaProgressRepository store, String character) =>
    store.allKana.firstWhere((k) => k.character == character);

Future<
  ({
    KanaProgressRepository kana,
    KanjiReadingRepository kanji,
    WordProgressRepository words,
    ProgressRestoreRecoveryController recovery,
  })
>
_pumpApp(WidgetTester tester, {bool needsRecovery = false}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await PreferencesService.create();
  final kana = await KanaProgressRepository.load(prefs);
  final kanji = await KanjiReadingRepository.load(prefs);
  final words = await WordProgressRepository.load(prefs);
  final checks = await PlacementCheckRepository.load(prefs);
  final recovery = recoveryForRepos(
    prefs: prefs,
    kana: kana,
    kanji: kanji,
    words: words,
    needsRecovery: needsRecovery,
  );
  final travel = await TravelFocusRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<PlacementCheckRepository>.value(value: checks),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            kanjiFlush: kanji.flushPending,
            wordFlush: words.flushPending,
            placementFlush: checks.flushPending,
          ),
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (kana: kana, kanji: kanji, words: words, recovery: recovery);
}

Future<void> _openAoCheck(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.learnNewKanaAction));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.placementEntry));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckboxListTile, 'あ行'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.placementStart));
  await tester.pumpAndSettle();
}

Future<void> _independentCorrect(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.iReadIt));
  await tester.pumpAndSettle();
}
