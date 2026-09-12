// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/kanji/ui/kanji_sentence_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _haru = Word(kana: 'はる', romaji: 'haru', meaning: '春天');
const _nami = Word(kana: 'なみ', romaji: 'nami', meaning: '波浪');
const _sora = Phrase(kana: 'そらが あおい', romaji: 'sora ga aoi', meaning: '天空是藍的');
const _hito = KanjiUnit(
  written: '人',
  reading: 'ひと',
  example: KanjiPhrase(
    segments: [RubySegment(text: '人', furigana: 'ひと')],
    romaji: 'hito',
    meaning: '人',
  ),
);
const _gakkou = KanjiUnit(
  written: '学校',
  reading: 'がっこう',
  example: KanjiPhrase(
    segments: [
      RubySegment(text: '学校', furigana: 'がっこう'),
      RubySegment(text: 'へ'),
      RubySegment(text: '行', furigana: 'い'),
      RubySegment(text: 'く'),
    ],
    romaji: 'gakkou e iku',
    meaning: '去學校',
  ),
);

/// iOS-like flutter_tts MethodChannel: stop returns 1 and does not settle
/// a pending speak. Every speak stays open until [completeSpeak].
class _IosLikeTtsChannel {
  final List<Completer<int>> pendingSpeaks = <Completer<int>>[];
  final List<String> spoken = <String>[];
  int stopCount = 0;

  Completer<int> get pendingFirstSpeak => pendingSpeaks.first;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'speak':
        final Object? args = call.arguments;
        if (args is! String) {
          throw StateError('expected speak text, got ${args.runtimeType}');
        }
        spoken.add(args);
        final pending = Completer<int>();
        pendingSpeaks.add(pending);
        return pending.future;
      case 'stop':
        stopCount++;
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

  void completeSpeak(int index, int result) {
    final pending = pendingSpeaks[index];
    if (pending.isCompleted) {
      throw StateError('speak $index is not pending');
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

void _pauseApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _resumeApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

/// Marks the next drawable frame inactive before post-frame callbacks.
/// Flutter still paints while inactive; this is not a paused forced-frame.
void _armInactiveBeforePostFrame(WidgetTester tester) {
  var armed = true;
  tester.binding.addPersistentFrameCallback((_) {
    if (!armed) return;
    armed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  });
}

Future<void> _learnUnits(
  KanaProgressRepository kana,
  Iterable<String> unitIds,
) async {
  for (final id in unitIds) {
    await kana.markUnitLearned(id);
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FlutterTtsSpeechService speech,
  Iterable<String> learnedUnits = const [],
  Iterable<String> seenUnlocks = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final words = await WordProgressRepository.load();
  await _learnUnits(kana, learnedUnits);
  for (final id in seenUnlocks) {
    await kana.markUnlockSeen(id);
  }
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
            health: [
              kana.statsHealth,
              kana.learnedUnitsHealth,
              kana.seenUnlocksHealth,
              kanji.statsHealth,
              words.statsHealth,
            ],
          ),
        ),
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProviders(
  WidgetTester tester, {
  required FlutterTtsSpeechService speech,
  required Widget home,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final words = await WordProgressRepository.load();
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
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('は行+ら行 unlocks はる (and ふれる) for Home 學單字', () async {
    final kana = await KanaProgressRepository.load();
    await _learnUnits(kana, const ['hira_row_5', 'hira_row_8']);
    final chars = StudySet.learned(kana).map((k) => k.character).toSet();
    expect(ReadingSet.readable(kWords, chars).map((w) => w.kana).toSet(), {
      'はる',
      'ふれる',
    });
  });

  test('あ行+さ行+ら行+が行 only unlocks そらが あおい', () {
    final chars = {
      for (final k in kHiraganaGojuon)
        if (k.row == 0 || k.row == 2 || k.row == 8) k.character,
      for (final k in kHiraganaDakuten)
        if (k.row == 1) k.character,
    };
    expect(ReadingSet.readable(kPhrases, chars).map((p) => p.kana), [
      'そらが あおい',
    ]);
  });

  testWidgets(
    'Home 學單字 speak(はる) then pop sends a leave stop and settles pending',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      expect(speech.ready, isTrue);
      await _pumpApp(
        tester,
        speech: speech,
        learnedUnits: const ['hira_row_5', 'hira_row_8'],
        seenUnlocks: [Unlock.words.id],
      );
      expect(find.text(AppStrings.meetWordsAction), findsOneWidget);

      await tester.tap(find.text(AppStrings.meetWordsAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(tts.spoken, anyOf(equals(['はる']), equals(['ふれる'])));
      expect(tts.pendingSpeaks, hasLength(1));
      expect(tts.pendingFirstSpeak.isCompleted, isFalse);
      expect(tts.stopCount, 1, reason: 'only the pre-play stop so far');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(FerryScreen), findsNothing);
      expect(tts.stopCount, greaterThan(1), reason: 'leave must send stop');

      tts.completeSpeak(0, 1);
      await tester.idle();
      expect(tts.spoken, anyOf(equals(['はる']), equals(['ふれる'])));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home 讀短句 speak(そらがあおい) then pop sends a leave stop', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    expect(speech.ready, isTrue);
    await _pumpApp(
      tester,
      speech: speech,
      learnedUnits: const [
        'hira_row_0',
        'hira_row_2',
        'hira_row_8',
        'hira_dakuten_1',
      ],
      seenUnlocks: [Unlock.words.id, Unlock.phrases.id],
    );
    expect(find.text(AppStrings.readPhrasesAction), findsOneWidget);

    await tester.tap(find.text(AppStrings.readPhrasesAction));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(tts.spoken, isEmpty);

    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pump();
    expect(tts.spoken, ['そらがあおい']);
    expect(tts.pendingSpeaks, hasLength(1));
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ReadingScreen), findsNothing);
    expect(tts.stopCount, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('old Ferry cleanup must not stop a newer Reading play', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(FerryScreen.route(const [_haru], AppStrings.ferryTitle)),
                child: const Text('open-ferry'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  ReadingScreen.route(const [_sora], AppStrings.sentenceTitle),
                ),
                child: const Text('open-reading'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-ferry'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['はる']);
    final ferryGen = speech.generation;
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));

    await tester.tap(find.text('open-reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pump();
    expect(tts.spoken, ['はる', 'そらがあおい']);
    final stopsAfterReading = tts.stopCount;
    expect(speech.generation, isNot(ferryGen));

    await speech.stop(generation: ferryGen);
    expect(tts.stopCount, stopsAfterReading);
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);

    tts.completeSpeak(0, 1);
    await tester.idle();
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);
    tts.completeSpeak(1, 1);
    await tester.idle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ferry background cancel sends stop; rapid replay starts a new play',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      await _pumpProviders(
        tester,
        speech: speech,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(FerryScreen.route(const [_haru], AppStrings.ferryTitle)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['はる']);
      expect(tts.stopCount, 1);

      _pauseApp(tester);
      await tester.pump();
      expect(tts.stopCount, greaterThan(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.tap(find.byTooltip(AppStrings.playSound));
      await tester.tap(find.byTooltip(AppStrings.playSound));
      await tester.pump();
      expect(tts.spoken.length, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reading natural completion then leave is safe', (tester) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              ReadingScreen.route(const [_sora], AppStrings.sentenceTitle),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pump();
    expect(tts.spoken, ['そらがあおい']);
    expect(tts.stopCount, 1);

    tts.completeSpeak(0, 1);
    await tester.idle();
    await tester.pump();
    final stopsAfterComplete = tts.stopCount;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(tts.stopCount, greaterThanOrEqualTo(stopsAfterComplete));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Study あ行 true route leave stops leftover あ', (tester) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpApp(tester, speech: speech);
    await tester.tap(find.text(AppStrings.learnNewKanaAction));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
    await tester.tap(find.text('あ行'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(tts.spoken, ['あ']);
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsScreen), findsOneWidget);
    expect(tts.stopCount, greaterThan(1));
  });

  testWidgets('Kanji teach route leave stops leftover がっこう', (tester) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              KanjiQuizScreen.route(const [_gakkou], AppStrings.kanjiTitle),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['がっこう']);
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));
  });

  testWidgets('Kanji sentence reveal leave stops leftover reading', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              KanjiSentenceScreen.route(const [
                KanjiPhrase(
                  segments: [
                    RubySegment(text: '空', furigana: 'そら'),
                    RubySegment(text: 'が'),
                    RubySegment(text: '青', furigana: 'あお'),
                    RubySegment(text: 'い'),
                  ],
                  romaji: 'sora ga aoi',
                  meaning: '天空是藍的',
                ),
              ], AppStrings.kanjiSentenceTitle),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, isEmpty);
    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pump();
    expect(tts.spoken, ['そらがあおい']);
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));
  });

  testWidgets(
    'Ferry next-word post-frame does not autoplay after inactive stop',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      await _pumpProviders(
        tester,
        speech: speech,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                FerryScreen.route(const [_haru, _nami], AppStrings.ferryTitle),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['はる']);

      await tester.tap(find.text(AppStrings.ferryShowText));
      await tester.pump();
      expect(tts.spoken, ['はる', 'はる']);

      await tester.tap(find.text(AppStrings.ferryReadSelf));
      await tester.pump();
      _armInactiveBeforePostFrame(tester);
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pump();
      expect(tts.spoken, ['はる', 'はる']);
      expect(find.text(AppStrings.ferryHear), findsOneWidget);

      _resumeApp(tester);
      await tester.pump();
      expect(tts.spoken, ['はる', 'はる']);
      await tester.tap(find.byTooltip(AppStrings.playSound));
      await tester.pump();
      expect(tts.spoken, ['はる', 'はる', 'なみ']);
    },
  );

  testWidgets(
    'Home 學單字 已讀 next-word stays silent if inactive before the frame',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      await _pumpApp(
        tester,
        speech: speech,
        learnedUnits: const ['hira_row_5', 'hira_row_8'],
        seenUnlocks: [Unlock.words.id],
      );
      await tester.tap(find.text(AppStrings.meetWordsAction));
      await tester.pumpAndSettle();
      expect(find.byType(FerryScreen), findsOneWidget);
      expect(tts.spoken, hasLength(1));

      await tester.tap(find.text(AppStrings.ferryShowText));
      await tester.pump();
      expect(tts.spoken, hasLength(2));
      await tester.tap(find.text(AppStrings.ferryReadSelf));
      await tester.pump();
      _armInactiveBeforePostFrame(tester);
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pump();
      expect(tts.spoken, hasLength(2));
      expect(find.byType(FerryScreen), findsOneWidget);
    },
  );

  testWidgets('Ferry foreground next-word still autoplays', (tester) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              FerryScreen.route(const [_haru, _nami], AppStrings.ferryTitle),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pump();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pump();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pump();
    expect(tts.spoken, ['はる', 'はる', 'なみ']);
  });

  testWidgets('Study next-card PageView does not autoplay after inactive', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpApp(tester, speech: speech);
    await tester.tap(find.text(AppStrings.learnNewKanaAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text('あ行'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['あ']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.tap(find.text(AppStrings.nextCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(tts.spoken, ['あ']);
  });

  testWidgets(
    'Kanji teach next-unit post-frame does not autoplay after inactive',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      await _pumpProviders(
        tester,
        speech: speech,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                KanjiQuizScreen.route(const [
                  _gakkou,
                  _hito,
                ], AppStrings.kanjiTitle),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['がっこう']);

      _armInactiveBeforePostFrame(tester);
      await tester.tap(find.text(AppStrings.kanjiNext));
      await tester.pump();
      expect(tts.spoken, ['がっこう']);
    },
  );

  testWidgets('Ferry last-word grade stops owned play before 名残', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push(FerryScreen.route(const [_haru], AppStrings.ferryTitle)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['はる']);

    await tester.tap(find.text(AppStrings.ferryShowText));
    await tester.pump();
    await tester.tap(find.text(AppStrings.ferryReadSelf));
    await tester.pump();
    expect(find.text(AppStrings.ferryReadback), findsOneWidget);
    final stopsBeforeSummary = tts.stopCount;
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);

    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pump();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);
    expect(tts.stopCount, greaterThan(stopsBeforeSummary));
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reading reveal→grade stops owned play before 名残', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              ReadingScreen.route(const [_sora], AppStrings.sentenceTitle),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, isEmpty);

    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pump();
    expect(tts.spoken, ['そらがあおい']);
    final stopsBeforeSummary = tts.stopCount;
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);

    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await tester.pump();
    expect(find.text(AppStrings.readingSummary(1, 1)), findsOneWidget);
    expect(tts.stopCount, greaterThan(stopsBeforeSummary));
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);
    expect(tester.takeException(), isNull);
  });
}
