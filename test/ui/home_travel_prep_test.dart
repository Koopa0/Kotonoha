// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/travel/travel_focus_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 11, 12);
  });

  Future<
    ({
      KanaProgressRepository kana,
      WordProgressRepository words,
      TravelFocusRepository travel,
    })
  >
  pumpHome(
    WidgetTester tester, {
    required KanaProgressRepository kana,
    required WordProgressRepository words,
    required TravelFocusRepository travel,
    Size size = const Size(420, 2400),
    double textScale = 1,
  }) async {
    final kanji = await KanjiReadingRepository.load();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
              travelFocusFlush: travel.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: HomeScreen(clock: () => now),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return (kana: kana, words: words, travel: travel);
  }

  Future<
    ({
      KanaProgressRepository kana,
      WordProgressRepository words,
      TravelFocusRepository travel,
    })
  >
  seedPartialTransport() async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final travel = await TravelFocusRepository.load();
    await kana.markUnitLearned('hira_row_0');
    await kana.markUnitLearned('hira_row_1');
    for (final unlock in Unlock.values) {
      await kana.markUnlockSeen(unlock.id);
    }
    final a = kana
        .gojuonForScript(KanaScript.hiragana)
        .firstWhere((k) => k.character == 'あ');
    await kana.recordAnswer(
      a,
      correct: false,
      at: now.subtract(const Duration(hours: 1)),
    );
    await travel.saveFocuses([
      TravelFocus(scene: TravelSceneId.transport, date: DateTime(2026, 9, 18)),
      TravelFocus(scene: TravelSceneId.clothing, date: DateTime(2026, 9, 18)),
    ]);
    return (kana: kana, words: words, travel: travel);
  }

  testWidgets(
    'partial kana: Home boost then 交通 meet, leftover rows do not block',
    (tester) async {
      final repos = await seedPartialTransport();
      await pumpHome(
        tester,
        kana: repos.kana,
        words: repos.words,
        travel: repos.travel,
      );

      expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
      expect(find.textContaining('旅行準備先做一回'), findsOneWidget);
      expect(find.text(AppStrings.guidanceLearnMore), findsNothing);

      await tester.tap(find.text(AppStrings.travelPrepBoostAction));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      expect(repos.travel.plan.kanaBoostOn, DateTime(2026, 9, 11));

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(find.textContaining('接著練「交通」'), findsOneWidget);
      expect(find.text(AppStrings.guidanceLearnMore), findsNothing);

      await tester.tap(find.text(AppStrings.travelPrepMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(
        find.text(
          AppStrings.travelSceneMeetTitle(AppStrings.travelSceneTransport),
        ),
        findsOneWidget,
      );
      expect(
        repos.travel.plan.servedOn[TravelSceneId.transport],
        DateTime(2026, 9, 11),
      );
    },
  );

  testWidgets('restart keeps the focuses; clearing does not change mastery', (
    tester,
  ) async {
    final first = await seedPartialTransport();
    await first.travel.markKanaBoost(now);
    await first.words.introduce('word:えき', at: now);
    final seenBefore = first.words.statForItem('word:えき').seenCount;

    final travel = await TravelFocusRepository.load();
    expect(travel.plan.focuses.map((f) => f.scene), [
      TravelSceneId.transport,
      TravelSceneId.clothing,
    ]);

    await pumpHome(
      tester,
      kana: first.kana,
      words: first.words,
      travel: travel,
    );
    expect(find.text(AppStrings.travelFocusEditAction), findsOneWidget);

    await tester.ensureVisible(find.text(AppStrings.travelFocusEditAction));
    await tester.tap(find.text(AppStrings.travelFocusEditAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelFocusScreen), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelFocusClear));
    await tester.pumpAndSettle();
    expect(travel.plan.isActive, isFalse);
    expect(first.words.statForItem('word:えき').seenCount, seenBefore);
  });

  testWidgets('general mode stays on 手解き when no travel plan is set', (
    tester,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final travel = await TravelFocusRepository.load();
    await kana.markUnitLearned('hira_row_0');
    await kana.markUnitLearned('hira_row_1');
    for (final unlock in Unlock.values) {
      await kana.markUnlockSeen(unlock.id);
    }
    final a = kana
        .gojuonForScript(KanaScript.hiragana)
        .firstWhere((k) => k.character == 'あ');
    await kana.recordAnswer(
      a,
      correct: true,
      at: now.subtract(const Duration(minutes: 1)),
      latencyMs: 300,
    );

    await pumpHome(tester, kana: kana, words: words, travel: travel);
    expect(find.text(AppStrings.guidanceLearnMore), findsOneWidget);
    expect(find.text(AppStrings.travelPrepBoostAction), findsNothing);
    expect(find.text(AppStrings.travelFocusAction), findsOneWidget);
  });

  testWidgets('unreadable shrine points at missing kana and 手解き', (
    tester,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final travel = await TravelFocusRepository.load();
    await kana.markUnitLearned('hira_row_0');
    for (final unlock in Unlock.values) {
      await kana.markUnlockSeen(unlock.id);
    }
    await travel.saveFocuses(const [TravelFocus(scene: TravelSceneId.shrine)]);

    await pumpHome(tester, kana: kana, words: words, travel: travel);
    expect(find.text(AppStrings.travelPrepLearnAction), findsOneWidget);
    expect(find.textContaining('還有詞句讀不動'), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelPrepLearnAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelSceneHub), findsOneWidget);
    expect(find.text(AppStrings.travelSceneLearnAction), findsOneWidget);
  });

  testWidgets('narrow phone and large text keep travel actions tappable', (
    tester,
  ) async {
    final repos = await seedPartialTransport();
    await pumpHome(
      tester,
      kana: repos.kana,
      words: repos.words,
      travel: repos.travel,
      size: const Size(320, 2400),
      textScale: 1.6,
    );
    expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
    await tester.ensureVisible(find.text(AppStrings.travelFocusEditAction));
    expect(find.text(AppStrings.travelFocusEditAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.travelPrepBoostAction));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
  });

  testWidgets('quiet practice remains available during travel prep', (
    tester,
  ) async {
    final repos = await seedPartialTransport();
    await pumpHome(
      tester,
      kana: repos.kana,
      words: repos.words,
      travel: repos.travel,
    );
    expect(find.text(AppStrings.quietPracticeAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.quietPracticeAction));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(repos.travel.plan.kanaBoostOn, isNull);
  });
}
