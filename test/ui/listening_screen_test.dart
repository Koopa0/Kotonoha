// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

const _station = Phrase(
  kana: 'えきは どこ',
  romaji: 'eki wa doko',
  meaning: '車站在哪裡',
);
const _repeat = Phrase(
  kana: 'もういちど いってください',
  romaji: 'mou ichido itte kudasai',
  meaning: '請再說一次',
);
const _ticket = Word(kana: 'きっぷ', romaji: 'kippu', meaning: '車票');
const _kimi = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');
const _ame = Word(kana: 'あめ', romaji: 'ame', meaning: '雨');

/// iOS-like flutter_tts MethodChannel: stop returns 1 and does not
/// settle a pending speak. First speak stays open until [completeFirstSpeak].
class _IosLikeTtsChannel {
  Completer<int>? pendingFirstSpeak;
  final List<String> spoken = <String>[];
  Object? subsequentSpeakResult = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'speak':
        final Object? args = call.arguments;
        if (args is! String) {
          throw StateError('expected speak text, got ${args.runtimeType}');
        }
        spoken.add(args);
        if (pendingFirstSpeak == null) {
          pendingFirstSpeak = Completer<int>();
          return pendingFirstSpeak!.future;
        }
        return subsequentSpeakResult;
      case 'stop':
        return 1;
      case 'getEngines':
        return <String>['com.google.android.tts'];
      case 'setLanguage':
      case 'setEngine':
        return 1;
      default:
        return 1;
    }
  }

  void completeFirstSpeak(int result) {
    final pending = pendingFirstSpeak;
    if (pending == null || pending.isCompleted) {
      throw StateError('first speak is not pending');
    }
    pending.complete(result);
  }
}

Future<_IosLikeTtsChannel> _installProductionTts(WidgetTester tester) async {
  final tts = _IosLikeTtsChannel();
  const channel = MethodChannel('flutter_tts');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    tts.handle,
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
  return tts;
}

Future<void> _expectAmeHasNoListeningEvidence({
  required WordProgressRepository words,
  required InMemoryAnalyticsLog analytics,
}) async {
  await words.flushPending();
  final reloaded = await WordProgressRepository.load();
  expect(reloaded.statForItem('word:あめ').srsLevel, 0);
  expect(reloaded.statForItem('word:あめ').isSeen, isFalse);
  expect(words.statForItem('word:あめ').srsLevel, 0);
  final logged = await analytics.all();
  expect(
    logged.where(
      (a) =>
          a.itemId.contains('あめ') &&
          a.meta[AttemptMeta.heard] == true &&
          a.meta[AttemptMeta.prompted] == false &&
          a.meta[AttemptMeta.scored] == true,
    ),
    isEmpty,
  );
  expect(find.text(AppStrings.listeningHeard), findsNothing);
}

Future<void> pumpListening(
  WidgetTester tester, {
  required SpeechService speech,
  required List<ReadingItem> items,
  InMemoryAnalyticsLog? analytics,
  WordProgressRepository? wordRepo,
  DateTime Function()? clock,
  int Function()? monotonicMs,
  Set<String> alreadyTransferredIds = const {},
  Size size = const Size(360, 800),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final store = await KanaProgressRepository.load();
  final resolvedWords = wordRepo ?? await WordProgressRepository.load();
  final resolvedAnalytics = analytics ?? InMemoryAnalyticsLog();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
        ChangeNotifierProvider<WordProgressRepository>.value(
          value: resolvedWords,
        ),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: store.flushPending,
            kanjiFlush: () async {},
            wordFlush: resolvedWords.flushPending,
          ),
        ),
        Provider<AnalyticsLog>.value(value: resolvedAnalytics),
        Provider<SpeechService>.value(value: speech),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: ListeningScreen(
              items: items,
              title: AppStrings.listeningTitle,
              clock: clock,
              monotonicMs: monotonicMs,
              alreadyTransferredIds: alreadyTransferredIds,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('answers stay hidden until reveal', (tester) async {
    final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
    await pumpListening(tester, speech: speech, items: const [_station]);

    expect(find.text('えきは どこ'), findsNothing);
    expect(find.text('eki wa doko'), findsNothing);
    expect(find.text('車站在哪裡'), findsNothing);
    expect(find.text(AppStrings.listeningPrompt), findsOneWidget);
    expect(find.text(AppStrings.listeningRecall), findsOneWidget);
    expect(speech.spoken, ['えきはどこ']);
  });

  testWidgets(
    'played → reveal → heard writes listening attempt and word stat',
    (tester) async {
      final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      var now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      await pumpListening(
        tester,
        speech: speech,
        items: const [_station, _repeat],
        analytics: analytics,
        wordRepo: words,
        clock: () => now,
        monotonicMs: () => elapsed,
      );

      await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
      await tester.pump();
      expect(find.text('えきは どこ'), findsOneWidget);
      expect(find.text('eki wa doko'), findsOneWidget);
      expect(find.text('車站在哪裡'), findsOneWidget);
      expect(find.text(AppStrings.listeningRehear), findsOneWidget);

      now = now.add(const Duration(seconds: 4));
      elapsed = 4000;
      await tester.tap(find.text(AppStrings.listeningHeard));
      await tester.pump();
      await tester.pump();

      final logged = await analytics.all();
      expect(logged, hasLength(1));
      expect(logged.single.mode, PracticeMode.listening.name);
      expect(logged.single.itemId, 'えきは どこ');
      expect(logged.single.correct, isTrue);
      expect(logged.single.rtMs, 4000);
      expect(logged.single.meta[AttemptMeta.heard], isTrue);
      expect(logged.single.meta[AttemptMeta.prompted], isFalse);
      expect(logged.single.meta[AttemptMeta.scored], isTrue);
      expect(
        logged.single.meta[AttemptMeta.playback],
        SpeechPlaybackResult.played.name,
      );
      expect(words.statForItem('phrase:えきは どこ').isSeen, isTrue);
      expect(words.statForItem('phrase:えきは どこ').correctCount, 1);
      expect(find.text('もういちど いってください'), findsNothing);
    },
  );

  testWidgets('failed play cannot grade or raise mastery', (tester) async {
    final client = FakeTtsClient(speakResult: 0);
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_ticket],
      analytics: analytics,
      wordRepo: words,
    );

    expect(client.spoken, ['きっぷ']);
    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(find.text(AppStrings.listeningFailed), findsOneWidget);
    expect(find.text(AppStrings.listeningHeard), findsNothing);
    expect(find.text(AppStrings.listeningMissed), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('listening-skip')));
    await tester.pumpAndSettle();

    expect(await analytics.all(), isEmpty);
    expect(words.statForItem('word:きっぷ').isSeen, isFalse);
    expect(find.text(AppStrings.listeningClose), findsOneWidget);
    expect(find.textContaining('聽懂'), findsNothing);
  });

  testWidgets('unavailable engine cannot be scored as a miss', (tester) async {
    final speech = FlutterTtsSpeechService(
      client: FakeTtsClient(),
      ready: false,
    );
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_station],
      analytics: analytics,
      wordRepo: words,
    );

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(find.text(AppStrings.listeningUnavailable), findsOneWidget);
    await tester.tap(find.text(AppStrings.listeningSkip));
    await tester.pumpAndSettle();
    expect(await analytics.all(), isEmpty);
    expect(words.statForItem('phrase:えきは どこ').wrongCount, 0);
  });

  testWidgets('fail then reveal then play is prompted — no SRS', (
    tester,
  ) async {
    final client = FakeTtsClient(speakResult: 0);
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_station],
      analytics: analytics,
      wordRepo: words,
    );

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(find.text('えきは どこ'), findsOneWidget);
    client.speakResult = 1;
    await tester.tap(find.byKey(const ValueKey<String>('listening-replay')));
    await tester.pump();
    expect(find.text(AppStrings.listeningHeard), findsNothing);
    expect(find.text(AppStrings.listeningPrompted), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('listening-next')));
    await tester.pumpAndSettle();

    final logged = await analytics.all();
    expect(logged, hasLength(1));
    expect(logged.single.meta[AttemptMeta.prompted], isTrue);
    expect(logged.single.meta[AttemptMeta.scored], isFalse);
    expect(logged.single.correct, isFalse);
    expect(words.statForItem('phrase:えきは どこ').isSeen, isFalse);
    expect(words.statForItem('phrase:えきは どこ').srsLevel, 0);
    expect(find.textContaining('聽懂'), findsNothing);
  });

  testWidgets('reveal while play is in flight is prompted only', (
    tester,
  ) async {
    final speech = HangingSpeechService();
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_station],
      analytics: analytics,
      wordRepo: words,
    );

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    speech.complete(SpeechPlaybackResult.played);
    await tester.pump();
    expect(find.text(AppStrings.listeningHeard), findsNothing);
    expect(find.text(AppStrings.listeningNext), findsOneWidget);
    await tester.tap(find.text(AppStrings.listeningNext));
    await tester.pumpAndSettle();
    expect(words.statForItem('phrase:えきは どこ').isSeen, isFalse);
    expect((await analytics.all()).single.meta[AttemptMeta.prompted], isTrue);
  });

  testWidgets('rapid replay stays on one speakable and does not leak text', (
    tester,
  ) async {
    final speech = ScriptedSpeechService(const [
      SpeechPlaybackResult.played,
      SpeechPlaybackResult.interrupted,
      SpeechPlaybackResult.played,
    ]);
    await pumpListening(tester, speech: speech, items: const [_station]);
    expect(find.text('えきは どこ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('listening-replay')));
    await tester.tap(find.byKey(const ValueKey<String>('listening-replay')));
    await tester.pump();
    expect(find.text('えきは どこ'), findsNothing);
    expect(speech.spoken.every((s) => s == 'えきはどこ'), isTrue);
    expect(speech.spoken.length, greaterThanOrEqualTo(2));
  });

  testWidgets('background interrupt is not a scored miss', (tester) async {
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final speech = HangingSpeechService();
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_station],
      analytics: analytics,
      wordRepo: words,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(speech.stopCount, greaterThanOrEqualTo(1));
    expect(speech.isCompleted, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(find.text(AppStrings.listeningHeard), findsNothing);
    expect(find.text(AppStrings.listeningSkip), findsOneWidget);
    expect(find.text(AppStrings.listeningInterrupted), findsOneWidget);
    await tester.tap(find.text(AppStrings.listeningSkip));
    await tester.pumpAndSettle();
    expect(await analytics.all(), isEmpty);
    expect(words.statForItem('phrase:えきは どこ').isSeen, isFalse);
  });

  testWidgets('leaving the route stops leftover playback', (tester) async {
    final speech = HangingSpeechService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(
            value: await KanaProgressRepository.load(),
          ),
          ChangeNotifierProvider<WordProgressRepository>.value(
            value: await WordProgressRepository.load(),
          ),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: () async {},
              kanjiFlush: () async {},
              wordFlush: () async {},
            ),
          ),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<SpeechService>.value(value: speech),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    ListeningScreen.route(const [
                      _station,
                    ], AppStrings.listeningTitle),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    expect(speech.spoken, ['えきはどこ']);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    expect(speech.stopCount, greaterThanOrEqualTo(1));
  });

  testWidgets('320x640 at 2x text keeps long T01 reveal reachable', (
    tester,
  ) async {
    final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
    await pumpListening(
      tester,
      speech: speech,
      items: const [_repeat],
      size: const Size(320, 640),
      textScale: 2,
    );

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('もういちど いってください'), findsOneWidget);
    expect(find.text('mou ichido itte kudasai'), findsOneWidget);
    expect(find.text('請再說一次'), findsOneWidget);
    expect(find.text(AppStrings.listeningHeard), findsOneWidget);
    expect(find.text(AppStrings.listeningMissed), findsOneWidget);
    await tester.ensureVisible(find.text(AppStrings.listeningHeard));
    await tester.tap(find.text(AppStrings.listeningHeard));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('聽懂'), findsNothing);
  });

  testWidgets('320x640 at 2x text keeps a failure line and skip reachable', (
    tester,
  ) async {
    final speech = FlutterTtsSpeechService(
      client: FakeTtsClient(speakResult: 0),
      ready: true,
    );
    await pumpListening(
      tester,
      speech: speech,
      items: const [_repeat],
      size: const Size(320, 640),
      textScale: 2,
    );

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.listeningFailed), findsOneWidget);
    expect(find.text(AppStrings.listeningSkip), findsOneWidget);
    await tester.ensureVisible(find.text(AppStrings.listeningSkip));
    await tester.tap(find.text(AppStrings.listeningSkip));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.listeningClose), findsOneWidget);
    expect(find.textContaining('聽懂'), findsNothing);
  });

  testWidgets('old speak complete before advance cannot credit the next item', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    expect(speech.ready, isTrue);
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_kimi, _ame],
      analytics: analytics,
      wordRepo: words,
    );
    expect(tts.spoken, ['きみ']);
    expect(tts.pendingFirstSpeak, isNotNull);

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    tts.completeFirstSpeak(1);
    await tester.idle();
    await tester.pump();
    expect(find.text(AppStrings.listeningHeard), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('listening-next')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    expect(find.text('あめ'), findsOneWidget);
    expect(find.text(AppStrings.listeningFailed), findsOneWidget);
    await _expectAmeHasNoListeningEvidence(words: words, analytics: analytics);
  });

  testWidgets(
    'old speak complete after advance before next frame cannot credit あめ',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      expect(speech.ready, isTrue);
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      await pumpListening(
        tester,
        speech: speech,
        items: const [_kimi, _ame],
        analytics: analytics,
        wordRepo: words,
      );

      await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('listening-skip')));
      tts.completeFirstSpeak(1);
      await tester.idle();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
      await tester.pump();
      expect(find.text('あめ'), findsOneWidget);
      expect(find.text(AppStrings.listeningHeard), findsNothing);
      expect(find.text(AppStrings.listeningFailed), findsOneWidget);
      await _expectAmeHasNoListeningEvidence(
        words: words,
        analytics: analytics,
      );
    },
  );

  testWidgets('もう一回 wrap: same id does not climb; a new grind id still does', (
    tester,
  ) async {
    final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
    final words = await WordProgressRepository.load();
    await pumpListening(
      tester,
      speech: speech,
      items: const [_station, _ticket],
      wordRepo: words,
      alreadyTransferredIds: {_station.progressId},
    );

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    await tester.tap(find.text(AppStrings.listeningHeard));
    await tester.pump();
    await tester.pump();
    expect(words.statForItem(_station.progressId).srsLevel, 0);
    expect(words.statForItem(_station.progressId).correctCount, 0);
    expect(words.statForItem(_station.progressId).isSeen, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    await tester.tap(find.text(AppStrings.listeningHeard));
    await tester.pump();
    await tester.pump();
    expect(words.statForItem(_ticket.progressId).srsLevel, 1);
    expect(words.statForItem(_ticket.progressId).correctCount, 1);
  });

  testWidgets('もう一回 wrap miss still resets SRS', (tester) async {
    final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
    final words = await WordProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    await words.recordAnswer(_station.progressId, correct: true, at: now);
    expect(words.statForItem(_station.progressId).srsLevel, 1);

    await pumpListening(
      tester,
      speech: speech,
      items: const [_station],
      wordRepo: words,
      alreadyTransferredIds: {_station.progressId},
    );
    await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
    await tester.pump();
    await tester.tap(find.text(AppStrings.listeningMissed));
    await tester.pumpAndSettle();
    expect(words.statForItem(_station.progressId).srsLevel, 0);
    expect(words.statForItem(_station.progressId).wrongCount, 1);
  });

  testWidgets('route forwards alreadyTransferredIds into the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(
            value: await KanaProgressRepository.load(),
          ),
          ChangeNotifierProvider<WordProgressRepository>.value(
            value: await WordProgressRepository.load(),
          ),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: () async {},
              kanjiFlush: () async {},
              wordFlush: () async {},
            ),
          ),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<SpeechService>.value(
            value: ScriptedSpeechService(const [SpeechPlaybackResult.played]),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    ListeningScreen.route(
                      const [_station],
                      AppStrings.listeningTitle,
                      alreadyTransferredIds: {_station.progressId},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    final screen = tester.widget<ListeningScreen>(find.byType(ListeningScreen));
    expect(screen.alreadyTransferredIds, {_station.progressId});
  });

  testWidgets(
    'old speak complete after next item failed play cannot credit あめ',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      expect(speech.ready, isTrue);
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      await pumpListening(
        tester,
        speech: speech,
        items: const [_kimi, _ame],
        analytics: analytics,
        wordRepo: words,
      );

      await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('listening-skip')));
      await tester.pump();
      expect(tts.spoken, ['きみ', 'あめ']);
      tts.completeFirstSpeak(1);
      await tester.idle();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('listening-reveal')));
      await tester.pump();
      expect(find.text('あめ'), findsOneWidget);
      expect(find.text(AppStrings.listeningHeard), findsNothing);
      expect(find.text(AppStrings.listeningFailed), findsOneWidget);
      await _expectAmeHasNoListeningEvidence(
        words: words,
        analytics: analytics,
      );
    },
  );
}
