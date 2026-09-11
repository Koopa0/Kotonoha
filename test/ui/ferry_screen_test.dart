// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/false_friend.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hear → see → read-back advances and logs a ferry attempt', (
    tester,
  ) async {
    // Fresh store (seenCount 0) keeps the occasional 凪 余韻 out of this flow test.
    final store = await KanaProgressRepository.load();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: store.flushPending,
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    final analytics = InMemoryAnalyticsLog();
    const words = [
      Word(kana: 'きみ', romaji: 'kimi', meaning: '你'),
      Word(kana: 'やま', romaji: 'yama', meaning: '山'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persistence,
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: FerryScreen(words: words, title: AppStrings.ferryTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> oneWord() async {
      // Beat 1: hear — the kana is hidden.
      expect(find.text(AppStrings.ferryHear), findsOneWidget);
      await tester.tap(find.text(AppStrings.ferryShowText));
      await tester.pumpAndSettle();
      // Beat 2: the kana has inked in.
      expect(find.text(AppStrings.ferrySee), findsOneWidget);
      await tester.tap(find.text(AppStrings.ferryReadSelf));
      await tester.pumpAndSettle();
      // Beat 3: read back.
      expect(find.text(AppStrings.ferryReadback), findsOneWidget);
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
    }

    // First word hides its kana on beat 1.
    expect(find.text('きみ'), findsNothing);
    await oneWord();
    await oneWord();

    expect(find.text(AppStrings.readingSummary(2, 2)), findsOneWidget);
    final logged = await analytics.all();
    expect(logged.length, 2);
    expect(logged.every((a) => a.mode == PracticeMode.ferry.name), isTrue);
    expect(logged.every((a) => a.itemType == ItemType.word), isTrue);
    expect(logged.first.itemId, 'きみ');
  });

  testWidgets('rtMs times only the read-back, not the see-beat dwell', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final wordRepo = await WordProgressRepository.load();
    final persistence = ProgressPersistenceController(
      kanaFlush: store.flushPending,
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );
    final analytics = InMemoryAnalyticsLog();
    var now = DateTime(2026, 6);
    const words = [Word(kana: 'きみ', romaji: 'kimi', meaning: '你')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persistence,
          ),
          Provider<AnalyticsLog>.value(value: analytics),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: MaterialApp(
          home: FerryScreen(
            words: words,
            title: AppStrings.ferryTitle,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.ferryShowText)); // → see beat
    await tester.pumpAndSettle();
    expect(
      find.text('你'),
      findsOneWidget,
    ); // the meaning is revealed with the kana
    expect(find.text('kimi'), findsOneWidget); // romaji confirms the reading
    now = now.add(const Duration(seconds: 5)); // dwell on SEE — must NOT count
    await tester.tap(
      find.text(AppStrings.ferryReadSelf),
    ); // read-back starts now
    await tester.pumpAndSettle();
    now = now.add(const Duration(milliseconds: 800)); // the read-back — counts
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();

    expect((await analytics.all()).single.rtMs, 800);
  });

  testWidgets('a 同形異義語 offers a gentle note, hidden until tapped', (
    tester,
  ) async {
    const word = Word(
      kana: 'てがみ',
      romaji: 'tegami',
      meaning: '信',
      falseFriend: FalseFriend(
        kanji: '手紙',
        jaMeaning: '信',
        zhNote: '中文直覺的「廁紙」,日文是別的詞。',
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: FerryScreen(words: [word], title: AppStrings.ferryTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Hear beat: nothing revealed, so no note trigger yet.
    expect(find.text(AppStrings.falseFriendTrigger), findsNothing);

    await tester.tap(find.text(AppStrings.ferryShowText)); // → reveal
    await tester.pumpAndSettle();
    // The trigger appears post-reveal; the note itself stays folded (pull).
    expect(find.text(AppStrings.falseFriendTrigger), findsOneWidget);
    expect(find.textContaining('廁紙'), findsNothing);

    await tester.tap(find.text(AppStrings.falseFriendTrigger));
    await tester.pumpAndSettle();
    expect(find.textContaining('廁紙'), findsOneWidget); // unfolded on demand
  });

  testWidgets('320x640 at 2x text keeps つかえません meaning reachable on see beat', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      () => tester.platformDispatcher.textScaleFactorTestValue = null,
    );

    const word = Word(
      kana: 'つかえません',
      romaji: 'tsukaemasen',
      meaning: '不能用',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: FerryScreen(words: [word], title: AppStrings.ferryTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('つかえません'), findsOneWidget);
    expect(find.text('不能用'), findsOneWidget);

    await tester.ensureVisible(find.text('不能用'));
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.ferryReadback), findsOneWidget);

    await tester.ensureVisible(find.text(AppStrings.iReadIt));
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
