// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/result/quiz_result_screen.dart';
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
    'opening boost or 交通 meet then leaving does not consume the day',
    (tester) async {
      final repos = await seedPartialTransport();
      final kanaBefore = _kanaSeenTotal(repos.kana);
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
      expect(repos.travel.plan.kanaBoostOn, isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
      expect(repos.travel.plan.kanaBoostOn, isNull);
      expect(_kanaSeenTotal(repos.kana), kanaBefore);

      await tester.tap(find.text(AppStrings.travelPrepSkipAction));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(find.textContaining('接著練「交通」'), findsOneWidget);

      await tester.tap(find.text(AppStrings.travelPrepMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(
        find.text(
          AppStrings.travelSceneMeetTitle(AppStrings.travelSceneTransport),
        ),
        findsOneWidget,
      );
      expect(repos.travel.plan.servedOn[TravelSceneId.transport], isNull);
      expect(repos.words.seenItemCount, 0);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(repos.travel.plan.servedOn[TravelSceneId.transport], isNull);
      expect(repos.words.seenItemCount, 0);

      final reloaded = await TravelFocusRepository.load();
      expect(reloaded.plan.kanaBoostOn, DateTime(2026, 9, 11));
      expect(reloaded.plan.servedOn[TravelSceneId.transport], isNull);
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

  testWidgets('travel focus picker lists restaurant and convenience', (
    tester,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final travel = await TravelFocusRepository.load();
    await pumpHome(tester, kana: kana, words: words, travel: travel);
    await tester.ensureVisible(find.text(AppStrings.travelFocusAction));
    await tester.tap(find.text(AppStrings.travelFocusAction));
    await tester.pumpAndSettle();
    expect(find.byType(TravelFocusScreen), findsOneWidget);
    expect(find.text(AppStrings.travelSceneTransport), findsOneWidget);
    expect(find.text(AppStrings.travelSceneRestaurant), findsOneWidget);
    expect(find.text(AppStrings.travelSceneConvenience), findsOneWidget);
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

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelPrepBoostAction), findsOneWidget);
    expect(repos.travel.plan.kanaBoostOn, isNull);
  });

  testWidgets(
    'finishing a daily round consumes boost; reload stays consistent',
    (tester) async {
      final repos = await seedPartialTransport();
      await pumpHome(
        tester,
        kana: repos.kana,
        words: repos.words,
        travel: repos.travel,
      );

      await tester.tap(find.text(AppStrings.travelPrepBoostAction));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      expect(repos.travel.plan.kanaBoostOn, isNull);

      await _finishDailyRound(tester);
      await _popToTravelHome(tester);

      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(repos.travel.plan.kanaBoostOn, DateTime(2026, 9, 11));
      expect(_kanaSeenTotal(repos.kana), greaterThan(1));

      final reloaded = await TravelFocusRepository.load();
      expect(reloaded.plan.kanaBoostOn, DateTime(2026, 9, 11));
      expect(reloaded.plan.servedOn[TravelSceneId.transport], isNull);
    },
  );

  testWidgets(
    'quiet success uses the same boost contract; re-entry does not skip meet',
    (tester) async {
      final repos = await seedPartialTransport();
      await pumpHome(
        tester,
        kana: repos.kana,
        words: repos.words,
        travel: repos.travel,
      );

      await tester.tap(find.text(AppStrings.quietPracticeAction));
      await tester.pumpAndSettle();
      expect(repos.travel.plan.kanaBoostOn, isNull);

      await _finishDailyRound(tester);
      await _popToTravelHome(tester);

      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(repos.travel.plan.kanaBoostOn, DateTime(2026, 9, 11));

      await tester.tap(find.text(AppStrings.quietPracticeAction));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(repos.travel.plan.kanaBoostOn, DateTime(2026, 9, 11));
    },
  );

  testWidgets('finishing 交通 meet consumes servedOn; abandon does not', (
    tester,
  ) async {
    final repos = await seedPartialTransport();
    await pumpHome(
      tester,
      kana: repos.kana,
      words: repos.words,
      travel: repos.travel,
    );

    await tester.tap(find.text(AppStrings.travelPrepSkipAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelPrepMeetAction));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
    expect(repos.travel.plan.servedOn[TravelSceneId.transport], isNull);
    expect(repos.words.seenItemCount, 0);

    await tester.tap(find.text(AppStrings.travelPrepMeetAction));
    await tester.pumpAndSettle();
    await _finishFerryRound(tester);
    expect(find.text(AppStrings.done), findsOneWidget);
    expect(
      repos.travel.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );
    expect(repos.words.seenItemCount, greaterThan(0));

    await _popToTravelHome(tester);
    expect(find.textContaining('接著練「交通」'), findsNothing);
    expect(
      repos.travel.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );

    final reloaded = await TravelFocusRepository.load();
    expect(reloaded.plan.kanaBoostOn, DateTime(2026, 9, 11));
    expect(
      reloaded.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );
  });

  testWidgets('explicit skip consumes the step without writing mastery', (
    tester,
  ) async {
    final repos = await seedPartialTransport();
    final kanaBefore = _kanaSeenTotal(repos.kana);
    await pumpHome(
      tester,
      kana: repos.kana,
      words: repos.words,
      travel: repos.travel,
    );

    await tester.tap(find.text(AppStrings.travelPrepSkipAction));
    await tester.pumpAndSettle();
    expect(repos.travel.plan.kanaBoostOn, DateTime(2026, 9, 11));
    expect(_kanaSeenTotal(repos.kana), kanaBefore);
    expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.travelPrepSkipAction));
    await tester.pumpAndSettle();
    expect(
      repos.travel.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );
    expect(repos.words.seenItemCount, 0);
    expect(find.textContaining('接著練「交通」'), findsNothing);
  });

  testWidgets(
    'Home restaurant focus: meet then finish advances the next step',
    (tester) async {
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      final travel = await TravelFocusRepository.load();
      await kana.markUnitLearned('hira_row_0');
      await kana.markUnitLearned('hira_row_2');
      for (final unlock in Unlock.values) {
        await kana.markUnlockSeen(unlock.id);
      }
      await travel.saveFocuses(const [
        TravelFocus(scene: TravelSceneId.restaurant),
      ]);

      await pumpHome(tester, kana: kana, words: words, travel: travel);
      expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);
      expect(find.textContaining('接著練「餐廳」'), findsOneWidget);

      await tester.tap(find.text(AppStrings.travelPrepMeetAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(
        find.text(
          AppStrings.travelSceneMeetTitle(AppStrings.travelSceneRestaurant),
        ),
        findsOneWidget,
      );
      expect(find.text('ふくろ'), findsNothing);
      expect(find.text('えき'), findsNothing);
      expect(travel.plan.servedOn[TravelSceneId.restaurant], isNull);

      await _finishFerryRound(tester);
      expect(
        travel.plan.servedOn[TravelSceneId.restaurant],
        DateTime(2026, 9, 11),
      );
      expect(words.seenItemCount, greaterThan(0));

      await _popToTravelHome(tester);
      expect(find.textContaining('接著練「餐廳」'), findsNothing);
      expect(find.text(AppStrings.guidanceTravelHold), findsOneWidget);

      final reloaded = await TravelFocusRepository.load();
      expect(
        reloaded.plan.servedOn[TravelSceneId.restaurant],
        DateTime(2026, 9, 11),
      );
    },
  );

  testWidgets('due えき plus unread ここ recalls first; finish then continues', (
    tester,
  ) async {
    final repos = await seedPartialTransport();
    await repos.travel.markKanaBoost(now);
    await repos.words.introduce(
      'word:えき',
      at: now.subtract(const Duration(days: 2)),
    );
    final learnedChars = StudySet.learned(repos.kana)
        .map((k) => k.character)
        .toSet();
    final view = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: learnedChars,
      stats: repos.words.stats,
      now: now,
    );
    expect(view.dueReadable.map((i) => i.progressId), contains('word:えき'));
    expect(view.unreadReadable.map((i) => i.progressId), contains('word:ここ'));

    await pumpHome(
      tester,
      kana: repos.kana,
      words: repos.words,
      travel: repos.travel,
    );
    expect(find.text(AppStrings.travelPrepRecallAction), findsOneWidget);
    expect(find.textContaining('見過的該回想'), findsOneWidget);
    expect(find.text(AppStrings.travelPrepMeetAction), findsNothing);
    expect(find.textContaining('還沒見過的先見面'), findsNothing);

    await tester.tap(find.text(AppStrings.travelPrepRecallAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(
      find.text(
        AppStrings.travelSceneRecallTitle(AppStrings.travelSceneTransport),
      ),
      findsOneWidget,
    );
    expect(repos.travel.plan.servedOn[TravelSceneId.transport], isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.travelPrepRecallAction), findsOneWidget);
    expect(repos.travel.plan.servedOn[TravelSceneId.transport], isNull);

    await tester.tap(find.text(AppStrings.travelPrepRecallAction));
    await tester.pumpAndSettle();
    await _finishReadingRound(tester);
    expect(find.text(AppStrings.done), findsOneWidget);
    expect(
      repos.travel.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );

    await _popToTravelHome(tester);
    expect(find.text(AppStrings.travelPrepRecallAction), findsNothing);
    expect(find.textContaining('接著練「交通」'), findsNothing);
    expect(find.text(AppStrings.travelPrepMeetAction), findsOneWidget);

    final reloaded = await TravelFocusRepository.load();
    expect(reloaded.plan.kanaBoostOn, DateTime(2026, 9, 11));
    expect(
      reloaded.plan.servedOn[TravelSceneId.transport],
      DateTime(2026, 9, 11),
    );
    expect(reloaded.plan.servedOn[TravelSceneId.clothing], isNull);
  });
}

int _kanaSeenTotal(KanaProgressRepository kana) =>
    kana.stats.values.fold<int>(0, (n, s) => n + s.seenCount);

Future<void> _finishDailyRound(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump();
    if (find.byType(QuizScreen).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    final canAnswer =
        find.text(AppStrings.iReadUnprompted).evaluate().isNotEmpty ||
        find.text(AppStrings.iReadIt).evaluate().isNotEmpty ||
        find.byType(AnswerOptionButton).evaluate().isNotEmpty;
    if (!canAnswer) {
      await tester.pumpAndSettle();
      if (find.byType(QuizScreen).evaluate().isEmpty) return;
      continue;
    }
    await _answerCurrentDaily(tester);
  }
  await tester.pumpAndSettle();
  expect(
    find.byType(QuizScreen),
    findsNothing,
    reason: 'daily must officially close',
  );
}

Future<void> _answerCurrentDaily(WidgetTester tester) async {
  if (find.text(AppStrings.iReadUnprompted).evaluate().isNotEmpty) {
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return;
  }
  if (find.text(AppStrings.iReadIt).evaluate().isNotEmpty &&
      find.byType(AnswerOptionButton).evaluate().isEmpty) {
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return;
  }
  if (find.byType(AnswerOptionButton).evaluate().isEmpty) {
    await tester.pumpAndSettle();
    return;
  }
  final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
  final labels = tester
      .widgetList<AnswerOptionButton>(find.byType(AnswerOptionButton))
      .map((b) => b.label)
      .toList();
  final question = quiz.items.map((item) => item.question).firstWhere((q) {
    if (!listEquals(q.options, labels)) return false;
    if (q.direction == QuizDirection.soundToKana) {
      return find.text(AppStrings.chooseBySound).evaluate().isNotEmpty;
    }
    return find.text(q.prompt).evaluate().isNotEmpty;
  });
  await tester.tap(
    find.widgetWithText(AnswerOptionButton, question.correctAnswer),
  );
  await tester.pump();
  final next = find.text(AppStrings.continueLabel);
  if (next.evaluate().isNotEmpty) {
    await tester.tap(next);
  } else if (find.text(AppStrings.seeResults).evaluate().isNotEmpty) {
    await tester.tap(find.text(AppStrings.seeResults));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _finishReadingRound(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    if (find.text(AppStrings.done).evaluate().isNotEmpty) return;
    expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
  }
  expect(find.text(AppStrings.done), findsOneWidget);
}

Future<void> _finishFerryRound(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    if (find.text(AppStrings.done).evaluate().isNotEmpty) return;
    expect(find.text(AppStrings.ferryShowText), findsOneWidget);
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
  }
  expect(find.text(AppStrings.done), findsOneWidget);
}

Future<void> _popToTravelHome(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    final overlayGone =
        find.byType(QuizScreen).evaluate().isEmpty &&
        find.byType(QuizResultScreen).evaluate().isEmpty &&
        find.byType(FerryScreen).evaluate().isEmpty &&
        find.byType(ReadingScreen).evaluate().isEmpty;
    if (overlayGone && find.byType(HomeScreen).evaluate().isNotEmpty) {
      return;
    }
    if (find.text(AppStrings.done).evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text(AppStrings.done));
      await tester.tap(find.text(AppStrings.done));
      await tester.pumpAndSettle();
      continue;
    }
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      continue;
    }
    await tester.pumpAndSettle();
  }
  expect(find.byType(QuizScreen), findsNothing);
  expect(find.byType(QuizResultScreen), findsNothing);
  expect(find.byType(HomeScreen), findsOneWidget);
}
