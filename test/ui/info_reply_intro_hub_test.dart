// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/info/info_hub_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  DateTime noon() => DateTime(2026, 9, 10, 12);
  DateTime night() => DateTime(2026, 9, 10, 19);

  Future<({KanaProgressRepository kana, WordProgressRepository words})> pumpHub(
    WidgetTester tester,
    Widget home,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await tester.binding.setSurfaceSize(const Size(420, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
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
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
    return (kana: kana, words: words);
  }

  Future<void> learnAllKana(KanaProgressRepository kana) async {
    for (final lesson in Lessons.fromKana(kana.allKana)) {
      await kana.markUnitLearned(lesson.id);
    }
  }

  Future<void> finishFerryWord(WidgetTester tester) async {
    expect(find.text(AppStrings.ferryHear), findsOneWidget);
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
  }

  Future<void> finishReadingItem(WidgetTester tester) async {
    await tester.ensureVisible(find.text(AppStrings.iReadUnprompted));
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(AppStrings.iReadIt));
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
  }

  testWidgets('info hub first-teach is eight then seven, then hub is ready', (
    tester,
  ) async {
    final repos = await pumpHub(tester, InfoHubScreen(clock: noon));
    await learnAllKana(repos.kana);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.infoStartAction), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('info-meet')));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text('1 / 8'), findsOneWidget);
    final first = tester.widget<FerryScreen>(find.byType(FerryScreen));
    expect(first.words, hasLength(8));
    final firstIds = first.words.map((w) => w.progressId).toSet();

    for (var i = 0; i < 8; i++) {
      await finishFerryWord(tester);
    }
    expect(find.text(AppStrings.practiceAgain), findsOneWidget);
    expect(find.text(AppStrings.infoStartAction), findsNothing);
    for (final id in firstIds) {
      expect(repos.words.statForItem(id).isSeen, isTrue);
    }
    final firstLevels = {
      for (final id in firstIds) id: repos.words.statForItem(id).srsLevel,
    };

    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text('1 / 7'), findsOneWidget);
    final second = tester.widget<FerryScreen>(find.byType(FerryScreen));
    expect(second.words, hasLength(7));
    expect(
      second.words.map((w) => w.progressId).toSet().intersection(firstIds),
      isEmpty,
    );
    for (var i = 0; i < 7; i++) {
      await finishFerryWord(tester);
    }
    expect(find.text(AppStrings.practiceAgain), findsOneWidget);
    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsNothing);
    expect(find.byType(InfoHubScreen), findsOneWidget);
    expect(find.text(AppStrings.infoStartAction), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsNothing);
    for (final id in firstIds) {
      expect(repos.words.statForItem(id).srsLevel, firstLevels[id]);
    }
  });

  testWidgets('info hub leave-and-reenter continues unseen words only', (
    tester,
  ) async {
    final repos = await pumpHub(tester, InfoHubScreen(clock: noon));
    await learnAllKana(repos.kana);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('info-meet')));
    await tester.pumpAndSettle();
    final first = tester.widget<FerryScreen>(find.byType(FerryScreen));
    final firstIds = first.words.map((w) => w.progressId).toSet();
    for (var i = 0; i < 8; i++) {
      await finishFerryWord(tester);
    }
    await tester.tap(find.text(AppStrings.done));
    await tester.pumpAndSettle();
    expect(find.byType(InfoHubScreen), findsOneWidget);
    expect(find.text(AppStrings.travelSceneMeetAction), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('info-meet')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 7'), findsOneWidget);
    final second = tester.widget<FerryScreen>(find.byType(FerryScreen));
    expect(
      second.words.map((w) => w.progressId).toSet().intersection(firstIds),
      isEmpty,
    );
  });

  testWidgets(
    'clothing reply first-teach is eight words, not the full fourteen',
    (tester) async {
      final repos = await pumpHub(
        tester,
        ReplyHubScreen(scene: ReplySceneId.clothing, clock: noon),
      );
      await learnAllKana(repos.kana);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.replyStartAction), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('reply-meet')));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(find.text('1 / 8'), findsOneWidget);
      expect(find.text('1 / 14'), findsNothing);
      final ferry = tester.widget<FerryScreen>(find.byType(FerryScreen));
      expect(ferry.words, hasLength(8));
      expect(ferry.words.map((w) => w.progressId), isNot(contains('word:えき')));
      expect(find.text('えきは どこ'), findsNothing);
    },
  );

  testWidgets('hotel info first-teach stays six words then two phrases', (
    tester,
  ) async {
    final repos = await pumpHub(
      tester,
      InfoHubScreen(
        clock: noon,
        drills: kHotelInfoDrills,
        title: AppStrings.travelSceneHotel,
        purpose: AppStrings.infoHotelPurpose,
        meetTitle: AppStrings.infoHotelMeetTitle,
        entryName: AppStrings.infoHotelEntry,
      ),
    );
    await learnAllKana(repos.kana);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.infoStartAction), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('info-meet')));
    await tester.pumpAndSettle();
    expect(find.byType(FerryScreen), findsOneWidget);
    expect(find.text('1 / 6'), findsOneWidget);
    final ferry = tester.widget<FerryScreen>(find.byType(FerryScreen));
    expect(ferry.words, hasLength(6));
    expect(ferry.words.map((w) => w.progressId), isNot(contains('word:さんぜん')));
    for (var i = 0; i < 6; i++) {
      await finishFerryWord(tester);
    }
    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
    expect(reading.items, hasLength(2));
    expect(
      reading.items.map((i) => i.progressId),
      containsAll(['phrase:あさごはんは ありますか', 'phrase:あした でます']),
    );
    expect(find.text(AppStrings.infoStartAction), findsNothing);
  });

  testWidgets(
    'travel phrase meet summary keeps もう一回 at noon and hides it at night',
    (tester) async {
      Future<void> run(
        DateTime Function() clock, {
        required bool showMore,
      }) async {
        SharedPreferences.setMockInitialValues({});
        final repos = await pumpHub(
          tester,
          TravelSceneHub(scene: TravelSceneId.shrine, clock: clock),
        );
        await learnAllKana(repos.kana);
        final leftover = 'phrase:こころが しずか';
        for (final item in TravelScene.items(TravelSceneId.shrine)) {
          if (item.progressId == leftover) continue;
          await repos.words.markIntroduced(item.progressId, at: noon());
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.travelSceneMeetAction));
        await tester.pumpAndSettle();
        expect(find.byType(ReadingScreen), findsOneWidget);
        final screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
        expect(screen.clock, isNotNull);
        expect(screen.clock!(), clock());
        expect(screen.items, hasLength(1));
        await finishReadingItem(tester);
        expect(find.text(AppStrings.done), findsOneWidget);
        expect(
          find.text(AppStrings.practiceAgain),
          showMore ? findsOneWidget : findsNothing,
        );
      }

      await run(noon, showMore: true);
      await run(night, showMore: false);
    },
  );

  testWidgets(
    'travel recall summary keeps もう一回 at noon and hides it at night',
    (tester) async {
      Future<void> run(
        DateTime Function() clock, {
        required bool showMore,
      }) async {
        SharedPreferences.setMockInitialValues({});
        final repos = await pumpHub(
          tester,
          TravelSceneHub(scene: TravelSceneId.shrine, clock: clock),
        );
        await repos.kana.markUnitLearned('hira_row_0');
        await repos.kana.markUnitLearned('hira_row_2');
        await repos.words.markIntroduced('word:いし', at: noon());
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.travelSceneRecallAction));
        await tester.pumpAndSettle();
        expect(find.byType(ReadingScreen), findsOneWidget);
        final screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
        expect(screen.clock, isNotNull);
        expect(screen.clock!(), clock());
        await finishReadingItem(tester);
        expect(find.text(AppStrings.done), findsOneWidget);
        expect(
          find.text(AppStrings.practiceAgain),
          showMore ? findsOneWidget : findsNothing,
        );
      }

      await run(noon, showMore: true);
      await run(night, showMore: false);
    },
  );

  testWidgets('reply phrase reading summary uses the hub clock', (
    tester,
  ) async {
    Future<void> run(
      DateTime Function() clock, {
      required bool showMore,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await pumpHub(
        tester,
        ReplyHubScreen(scene: ReplySceneId.station, clock: clock),
      );
      await learnAllKana(repos.kana);
      for (final word in ReplySession.unreadRequiredWords(
        learnedChars: {for (final kana in repos.kana.allKana) kana.character},
        stats: const {},
        scene: ReplySceneId.station,
      )) {
        await repos.words.markIntroduced(word.progressId, at: noon());
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('reply-meet')));
      await tester.pumpAndSettle();
      expect(find.byType(ReadingScreen), findsOneWidget);
      final screen = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      expect(screen.clock, isNotNull);
      expect(screen.clock!(), clock());
      final count = screen.items.length;
      expect(count, greaterThan(0));
      expect(count, lessThanOrEqualTo(8));
      for (var i = 0; i < count; i++) {
        await finishReadingItem(tester);
      }
      expect(find.text(AppStrings.done), findsOneWidget);
      expect(
        find.text(AppStrings.practiceAgain),
        showMore ? findsOneWidget : findsNothing,
      );
    }

    await run(noon, showMore: true);
    await run(night, showMore: false);
  });
}
