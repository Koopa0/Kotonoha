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
    expect(wordRepo.statForItem('word:きみ').srsLevel, 1);
    expect(wordRepo.statForItem('word:きみ').correctCount, 1);
    expect(wordRepo.statForItem('word:やま').srsLevel, 1);
    expect(wordRepo.statForItem('word:やま').correctCount, 1);
  });

  testWidgets(
    'first 讀不出來 marks introduced without encode credit; seen miss stays put',
    (tester) async {
      final store = await KanaProgressRepository.load();
      final wordRepo = await WordProgressRepository.load();
      final persistence = ProgressPersistenceController(
        kanaFlush: store.flushPending,
        kanjiFlush: () async {},
        wordFlush: wordRepo.flushPending,
      );
      final analytics = InMemoryAnalyticsLog();
      const words = [
        Word(kana: 'えき', romaji: 'eki', meaning: '車站'),
        Word(kana: 'ここ', romaji: 'koko', meaning: '這裡'),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
            ChangeNotifierProvider<WordProgressRepository>.value(
              value: wordRepo,
            ),
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

      Future<void> gradeCurrent({required bool correct}) async {
        await tester.tap(find.text(AppStrings.ferryShowText));
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.ferryReadSelf));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(correct ? AppStrings.iReadIt : AppStrings.iCouldnt),
        );
        await tester.pumpAndSettle();
      }

      await gradeCurrent(correct: false);
      expect(wordRepo.statForItem('word:えき').isSeen, isTrue);
      expect(wordRepo.statForItem('word:えき').correctCount, 0);
      expect(wordRepo.statForItem('word:えき').srsLevel, 0);
      expect(wordRepo.statForItem('word:えき').wrongCount, 0);

      await gradeCurrent(correct: true);
      expect(wordRepo.statForItem('word:ここ').correctCount, 1);
      expect(wordRepo.statForItem('word:ここ').srsLevel, 1);

      final logged = await analytics.all();
      expect(logged.map((a) => a.correct), [false, true]);
    },
  );

  testWidgets('seen ferry 讀不出來 / 讀對了 do not add a second encode', (
    tester,
  ) async {
    final store = await KanaProgressRepository.load();
    final wordRepo = await WordProgressRepository.load();
    final now = DateTime(2026, 9, 11, 12);
    await wordRepo.introduce('word:えき', at: now);
    await wordRepo.introduce('word:ここ', at: now);
    expect(wordRepo.statForItem('word:えき').srsLevel, 1);
    expect(wordRepo.statForItem('word:ここ').correctCount, 1);
    final persistence = ProgressPersistenceController(
      kanaFlush: store.flushPending,
      kanjiFlush: () async {},
      wordFlush: wordRepo.flushPending,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
          ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: persistence,
          ),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: FerryScreen(
            words: [
              Word(kana: 'えき', romaji: 'eki', meaning: '車站'),
              Word(kana: 'ここ', romaji: 'koko', meaning: '這裡'),
            ],
            title: AppStrings.ferryTitle,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> gradeCurrent({required bool correct}) async {
      await tester.tap(find.text(AppStrings.ferryShowText));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.ferryReadSelf));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(correct ? AppStrings.iReadIt : AppStrings.iCouldnt),
      );
      await tester.pumpAndSettle();
    }

    await gradeCurrent(correct: false);
    expect(wordRepo.statForItem('word:えき').srsLevel, 1);
    expect(wordRepo.statForItem('word:えき').correctCount, 1);
    expect(wordRepo.statForItem('word:えき').wrongCount, 0);

    await gradeCurrent(correct: true);
    expect(wordRepo.statForItem('word:ここ').srsLevel, 1);
    expect(wordRepo.statForItem('word:ここ').correctCount, 1);
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

  testWidgets('320×640 / 2x keeps つかえません and 不能用 reachable before seen', (
    tester,
  ) async {
    final wordRepo = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    _phone320x640At2x(tester);
    await _pumpFerry(
      tester,
      words: const [
        Word(kana: 'つかえません', romaji: 'tsukaemasen', meaning: '不能用'),
      ],
      kana: wordRepo,
      wordRepo: words,
    );

    expect(find.text('つかえません'), findsNothing);
    expect(words.statForItem('word:つかえません').isSeen, isFalse);
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pumpAndSettle();
    expect(find.text('つかえません'), findsOneWidget);
    expect(find.text('不能用'), findsOneWidget);
    expect(
      find.text(AppStrings.ferryReadSelf).hitTestable(),
      findsNothing,
      reason: '完成鈕必須在否定與意思之後，不能沒看完就按',
    );
    expect(words.statForItem('word:つかえません').isSeen, isFalse);

    await tester.ensureVisible(find.text('不能用'));
    await tester.pumpAndSettle();
    _expectFullyOnScreen(tester, find.text('不能用'));
    _expectKanaTailAboveMeaning(
      tester,
      kana: find.text('つかえません'),
      meaning: find.text('不能用'),
    );
    expect(words.statForItem('word:つかえません').isSeen, isFalse);

    await tester.ensureVisible(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ferryReadSelf).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.iReadIt).hitTestable(), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(words.statForItem('word:つかえません').isSeen, isTrue);
  });

  testWidgets(
    '320×640 / 2x keeps short ふく readable and back does not mark seen',
    (tester) async {
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      _phone320x640At2x(tester);
      await _pumpFerry(
        tester,
        words: const [Word(kana: 'ふく', romaji: 'fuku', meaning: '衣服')],
        kana: kana,
        wordRepo: words,
        pushRoute: true,
      );

      await tester.tap(find.text(AppStrings.ferryShowText));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('衣服'));
      await tester.pumpAndSettle();
      _expectFullyOnScreen(tester, find.text('衣服'));
      expect(find.text('ふく'), findsOneWidget);
      expect(words.statForItem('word:ふく').isSeen, isFalse);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsNothing);
      expect(words.statForItem('word:ふく').isSeen, isFalse);
    },
  );
}

void _phone320x640At2x(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.binding.setSurfaceSize(null);
  });
}

void _expectFullyOnScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.height, greaterThan(0), reason: '$finder has no height');
  expect(rect.top, greaterThanOrEqualTo(-1), reason: '$finder top ${rect.top}');
  expect(
    rect.bottom,
    lessThanOrEqualTo(641),
    reason: '$finder bottom ${rect.bottom}',
  );
}

void _expectKanaTailAboveMeaning(
  WidgetTester tester, {
  required Finder kana,
  required Finder meaning,
}) {
  final kanaRect = tester.getRect(kana);
  final meaningRect = tester.getRect(meaning);
  expect(kanaRect.bottom, greaterThan(0));
  expect(kanaRect.bottom, lessThanOrEqualTo(meaningRect.top + 1));
  expect(
    kanaRect.bottom,
    lessThanOrEqualTo(641),
    reason: 'せん must sit on-screen just above the meaning',
  );
}

Future<void> _pumpFerry(
  WidgetTester tester, {
  required List<Word> words,
  required KanaProgressRepository kana,
  required WordProgressRepository wordRepo,
  bool pushRoute = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            kanjiFlush: () async {},
            wordFlush: wordRepo.flushPending,
          ),
        ),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
      ],
      child: MaterialApp(
        home: pushRoute
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(FerryScreen.route(words, AppStrings.ferryTitle)),
                      child: const Text('open'),
                    ),
                  ),
                ),
              )
            : FerryScreen(words: words, title: AppStrings.ferryTitle),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushRoute) {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}
