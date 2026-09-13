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
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/widgets/kana_detail_sheet.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/learn/learn_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_screen.dart';
import 'package:kotonoha/ui/writing/writing_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

const _eki = Word(kana: 'えき', romaji: 'eki', meaning: '車站');
const _kimi = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');
DateTime _noon() => DateTime(2026, 9, 11, 12);

final _ki = kHiraganaGojuon.firstWhere((k) => k.character == 'き');

SessionItem _soundKi() => SessionItem(
  question: QuizQuestion(
    target: _ki,
    direction: QuizDirection.soundToKana,
    options: [_ki.character, 'い', 'う', 'え'],
    correctIndex: 0,
  ),
  mode: PracticeMode.daily,
);

/// iOS-like flutter_tts MethodChannel: stop returns 1 and does not settle
/// a pending speak. Every speak stays open until [completeSpeak].
class _IosLikeTtsChannel {
  final List<Completer<int>> pendingSpeaks = <Completer<int>>[];
  final List<String> spoken = <String>[];
  int stopCount = 0;

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

Future<void> _learnUnits(
  KanaProgressRepository kana,
  Iterable<String> unitIds,
) async {
  for (final id in unitIds) {
    await kana.markUnitLearned(id);
  }
}

Future<void> _learnAllLessons(KanaProgressRepository kana) async {
  for (final lesson in Lessons.fromKana(kana.allKana)) {
    await kana.markUnitLearned(lesson.id);
  }
}

Future<void> _pumpProviders(
  WidgetTester tester, {
  required FlutterTtsSpeechService speech,
  required Widget home,
  KanaProgressRepository? kana,
  WordProgressRepository? words,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (kana == null && words == null) {
    SharedPreferences.setMockInitialValues({});
  }
  final prefs = await PreferencesService.create();
  final resolvedKana = kana ?? await KanaProgressRepository.load(prefs);
  final kanji = await KanjiReadingRepository.load(prefs);
  final resolvedWords = words ?? await WordProgressRepository.load(prefs);
  final recovery = recoveryForRepos(
    prefs: prefs,
    kana: resolvedKana,
    kanji: kanji,
    words: resolvedWords,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(
          value: resolvedKana,
        ),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(
          value: resolvedWords,
        ),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: resolvedKana.flushPending,
            kanjiFlush: kanji.flushPending,
            wordFlush: resolvedWords.flushPending,
          ),
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FlutterTtsSpeechService speech,
  required KanaProgressRepository kana,
  required WordProgressRepository words,
  DateTime Function()? clock,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final kanji = await KanjiReadingRepository.load();
  final recovery = recoveryForRepos(
    prefs: await PreferencesService.create(),
    kana: kana,
    kanji: kanji,
    words: words,
  );
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
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: MaterialApp(home: HomeScreen(clock: clock)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finishFirstListeningClip(
  WidgetTester tester,
  _IosLikeTtsChannel tts,
) async {
  expect(tts.spoken, ['えき']);
  expect(tts.pendingSpeaks, hasLength(1));
  tts.completeSpeak(0, 1);
  await tester.idle();
  await tester.pump();
  await tester.tap(find.text(AppStrings.listeningReveal));
  await tester.pump();
  expect(find.text(AppStrings.listeningHeard), findsOneWidget);
  await tester.tap(find.text(AppStrings.listeningHeard));
  await tester.pumpAndSettle();
  expect(find.text(AppStrings.practiceAgain), findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Listening もう一回 replace keeps the new autoplay after old dispose',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      await _pumpProviders(
        tester,
        speech: speech,
        home: Builder(
          builder: (context) {
            void start({bool replace = false}) {
              final route = ListeningScreen.route(
                const [_eki],
                AppStrings.listeningTitle,
                clock: _noon,
                onMore: () => start(replace: true),
              );
              final nav = Navigator.of(context);
              replace ? nav.pushReplacement(route) : nav.push(route);
            }

            return Scaffold(
              body: TextButton(onPressed: start, child: const Text('open')),
            );
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _finishFirstListeningClip(tester, tts);
      final stopsAtNagi = tts.stopCount;
      final genAtNagi = speech.generation;

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningScreen), findsOneWidget);
      expect(tts.spoken, ['えき', 'えき']);
      expect(find.text(AppStrings.listeningInterrupted), findsNothing);
      expect(speech.generation, greaterThan(genAtNagi));
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);
      expect(tts.stopCount, stopsAtNagi + 1);
    },
  );

  testWidgets(
    'Home 先聽再揭曉 もう一回 does not let old Listening cancel the new page',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      await _learnAllLessons(kana);
      await words.introduce('word:えき', at: _noon());
      await _pumpApp(
        tester,
        speech: speech,
        kana: kana,
        words: words,
        clock: _noon,
      );
      await tester.tap(find.text(AppStrings.listenFirstAction));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningScreen), findsOneWidget);
      await _finishFirstListeningClip(tester, tts);
      final stopsAtNagi = tts.stopCount;

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningScreen), findsOneWidget);
      expect(tts.spoken, ['えき', 'えき']);
      expect(find.text(AppStrings.listeningInterrupted), findsNothing);
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);
      expect(tts.stopCount, stopsAtNagi + 1);
    },
  );

  testWidgets('Listening leave and background still cancel the owned play', (
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
              ListeningScreen.route(
                const [_eki],
                AppStrings.listeningTitle,
                clock: _noon,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['えき']);
    expect(tts.stopCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(tts.stopCount, greaterThan(1));
    expect(find.text(AppStrings.listeningInterrupted), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
    'Listening replay after もう一回 still does not write SRS until heard',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      final words = await WordProgressRepository.load();
      final analytics = InMemoryAnalyticsLog();
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final kana = await KanaProgressRepository.load();
      final kanji = await KanjiReadingRepository.load();
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
            Provider<AnalyticsLog>.value(value: analytics),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                void start({bool replace = false}) {
                  final route = ListeningScreen.route(
                    const [_eki],
                    AppStrings.listeningTitle,
                    clock: _noon,
                    onMore: () => start(replace: true),
                  );
                  final nav = Navigator.of(context);
                  replace ? nav.pushReplacement(route) : nav.push(route);
                }

                return Scaffold(
                  body: TextButton(onPressed: start, child: const Text('open')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _finishFirstListeningClip(tester, tts);
      expect(words.statForItem('word:えき').srsLevel, 1);

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppStrings.replaySound));
      await tester.pump();
      await tester.tap(find.text(AppStrings.listeningReveal));
      await tester.pump();
      expect(find.text(AppStrings.listeningHeard), findsNothing);
      expect(find.text(AppStrings.listeningSkip), findsOneWidget);
      expect(words.statForItem('word:えき').srsLevel, 1);
      expect(
        (await analytics.all()).where(
          (a) => a.mode == PracticeMode.listening.name,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('Writing speaker leave sends a stop and settles pending', (
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
              WritingScreen.route(const [
                Kana(character: 'あ', romaji: 'a', row: 0, column: 0),
              ], AppStrings.writingTitle),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, ['あ']);
    expect(tts.stopCount, 1);
    expect(tts.pendingSpeaks.single.isCompleted, isFalse);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));
    expect(speech.generation, greaterThan(1));
  });

  testWidgets('Home 手習い speaker then back sends a leave stop', (tester) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await _learnUnits(kana, const ['hira_row_0']);
    await _pumpApp(tester, speech: speech, kana: kana, words: words);
    await tester.tap(find.text(AppStrings.writingEntry));
    await tester.pumpAndSettle();
    expect(find.byType(WritingScreen), findsOneWidget);
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, hasLength(1));
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Writing grade to next kana stops the previous owned play', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    final row = kHiraganaGojuon.take(5).toList();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(WritingScreen.route(row, AppStrings.writingTitle)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, ['あ']);
    expect(tts.stopCount, 1);
    final firstGen = speech.generation;
    expect(tts.pendingSpeaks.single.isCompleted, isFalse);

    await tester.tap(find.text(AppStrings.revealAnswer));
    await tester.pump();
    await tester.tap(find.text(AppStrings.iGotIt));
    await tester.pump();
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('i'), findsOneWidget);
    expect(tts.stopCount, greaterThan(1));
    expect(speech.generation, greaterThan(firstGen));

    tts.completeSpeak(0, 1);
    await tester.idle();
    await tester.pump();
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('i'), findsOneWidget);
    expect(tts.spoken, ['あ']);

    final stopsAfterAdvance = tts.stopCount;
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, ['あ', 'い']);
    final nextGen = speech.generation;
    await speech.stop(generation: firstGen);
    expect(tts.stopCount, stopsAfterAdvance + 1);
    expect(speech.generation, nextGen);
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);
  });

  testWidgets('Home 手習い speaker then 寫對 stops leftover before 2/5', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await _learnUnits(kana, const ['hira_row_0']);
    await _pumpApp(tester, speech: speech, kana: kana, words: words);
    expect(find.text(AppStrings.shiftAction), findsOneWidget);
    await tester.tap(find.text(AppStrings.writingEntry));
    await tester.pumpAndSettle();
    expect(find.byType(WritingScreen), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, hasLength(1));
    expect(tts.stopCount, 1);

    await tester.tap(find.text(AppStrings.revealAnswer));
    await tester.pump();
    await tester.tap(find.text(AppStrings.iGotIt));
    await tester.pump();
    expect(find.text('2 / 5'), findsOneWidget);
    expect(tts.stopCount, greaterThan(1));
  });

  testWidgets('Writing background cancel then resume still allows replay', (
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
              WritingScreen.route(
                kHiraganaGojuon.take(2).toList(),
                AppStrings.writingTitle,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.stopCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tts.stopCount, greaterThan(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, ['あ', 'あ']);
  });

  testWidgets('KanaDetailSheet speaker then barrier dismiss sends a stop', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    final kana = kHiraganaGojuon.first;
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                KanaDetailSheet.show(context, kana, const KanaStat()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, ['あ']);
    expect(tts.stopCount, 1);
    expect(tts.pendingSpeaks.single.isCompleted, isFalse);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Home 五十音図 あ詳情 speaker then barrier sends a leave stop', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(tester, speech: speech, home: const KanaLoopApp());
    await tester.tap(find.text(AppStrings.learnHiragana));
    await tester.pumpAndSettle();
    expect(find.byType(LearnScreen), findsOneWidget);
    await tester.tap(find.text('あ'));
    await tester.pumpAndSettle();
    expect(find.byType(KanaDetailSheet), findsOneWidget);
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    expect(tts.spoken, ['あ']);
    expect(tts.stopCount, 1);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(tts.stopCount, greaterThan(1));
    expect(find.byType(KanaDetailSheet), findsNothing);
  });

  testWidgets(
    'Home 聞き取り More keeps new autoplay and does not re-climb after reload',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      await _learnAllLessons(kana);
      await words.markIntroduced('word:えき', at: _noon());
      await _pumpApp(
        tester,
        speech: speech,
        kana: kana,
        words: words,
        clock: _noon,
      );
      expect(find.text(AppStrings.shiftAction), findsOneWidget);
      expect(find.text(AppStrings.travelSceneAction), findsOneWidget);
      await tester.ensureVisible(find.text(AppStrings.listenFirstAction));
      await tester.tap(find.text(AppStrings.listenFirstAction));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningScreen), findsOneWidget);
      await _finishFirstListeningClip(tester, tts);
      expect(words.statForItem('word:えき').srsLevel, 1);
      final stopsAtNagi = tts.stopCount;
      final genAtNagi = speech.generation;

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      final second = tester.widget<ListeningScreen>(
        find.byType(ListeningScreen),
      );
      expect(second.alreadyTransferredIds, contains('word:えき'));
      expect(tts.spoken, ['えき', 'えき']);
      expect(find.text(AppStrings.listeningInterrupted), findsNothing);
      expect(speech.generation, greaterThan(genAtNagi));
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);
      expect(tts.stopCount, stopsAtNagi + 1);

      tts.completeSpeak(1, 1);
      await tester.idle();
      await tester.pump();
      await tester.tap(find.text(AppStrings.listeningReveal));
      await tester.pump();
      await tester.tap(find.text(AppStrings.listeningHeard));
      await tester.pumpAndSettle();
      expect(words.statForItem('word:えき').srsLevel, 1);
      await words.flushPending();
      final reloaded = await WordProgressRepository.load();
      expect(reloaded.statForItem('word:えき').srsLevel, 1);
    },
  );

  testWidgets(
    'Travel 聽力 More keeps new autoplay and does not re-climb after reload',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      await kana.markUnitLearned('hira_row_0');
      await kana.markUnitLearned('hira_row_1');
      await words.markIntroduced('word:えき', at: _noon());
      await _pumpProviders(
        tester,
        speech: speech,
        kana: kana,
        words: words,
        home: const TravelSceneHub(
          scene: TravelSceneId.transport,
          clock: _noon,
        ),
      );
      await tester.tap(find.text(AppStrings.travelSceneListenAction));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningScreen), findsOneWidget);
      await _finishFirstListeningClip(tester, tts);
      expect(words.statForItem('word:えき').srsLevel, 1);
      final stopsAtNagi = tts.stopCount;
      final genAtNagi = speech.generation;

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      final second = tester.widget<ListeningScreen>(
        find.byType(ListeningScreen),
      );
      expect(second.alreadyTransferredIds, contains('word:えき'));
      expect(tts.spoken, ['えき', 'えき']);
      expect(find.text(AppStrings.listeningInterrupted), findsNothing);
      expect(speech.generation, greaterThan(genAtNagi));
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);
      expect(tts.stopCount, stopsAtNagi + 1);

      tts.completeSpeak(1, 1);
      await tester.idle();
      await tester.pump();
      await tester.tap(find.text(AppStrings.listeningReveal));
      await tester.pump();
      await tester.tap(find.text(AppStrings.listeningHeard));
      await tester.pumpAndSettle();
      expect(words.statForItem('word:えき').srsLevel, 1);
      await words.flushPending();
      final reloaded = await WordProgressRepository.load();
      expect(reloaded.statForItem('word:えき').srsLevel, 1);
    },
  );

  testWidgets(
    'Dictation もう一回 replace keeps the new autoplay after old dispose',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      await _pumpProviders(
        tester,
        speech: speech,
        home: Builder(
          builder: (context) {
            void start({bool replace = false}) {
              final route = DictationScreen.route(
                const [_kimi],
                AppStrings.dictationTitle,
                clock: _noon,
                onMore: () => start(replace: true),
              );
              final nav = Navigator.of(context);
              replace ? nav.pushReplacement(route) : nav.push(route);
            }

            return Scaffold(
              body: TextButton(onPressed: start, child: const Text('open')),
            );
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['きみ']);
      tts.completeSpeak(0, 1);
      await tester.idle();
      await tester.pump();
      await tester.tap(find.text('き'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('み'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.dictationNext), findsOneWidget);
      await tester.tap(find.text(AppStrings.dictationNext));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.practiceAgain), findsOneWidget);
      final stopsAtNagi = tts.stopCount;
      final genAtNagi = speech.generation;

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.byType(DictationScreen), findsOneWidget);
      expect(tts.spoken.last, 'きみ');
      expect(find.text(AppStrings.dictationInterrupted), findsNothing);
      expect(speech.generation, greaterThan(genAtNagi));
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);
      expect(tts.stopCount, stopsAtNagi + 1);

      await tester.tap(find.byKey(const ValueKey<String>('dictation-replay')));
      await tester.pump();
      expect(tts.spoken.where((s) => s == 'きみ').length, greaterThan(2));
      expect(find.text(AppStrings.dictationInterrupted), findsNothing);
    },
  );

  testWidgets('Dictation leave still cancels the owned play', (tester) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              DictationScreen.route(
                const [_kimi],
                AppStrings.dictationTitle,
                clock: _noon,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['きみ']);
    expect(tts.stopCount, 1);
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(tts.stopCount, greaterThan(1));
  });

  testWidgets(
    'Quiz soundToKana pushReplacement keeps the new autoplay after old dispose',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      late void Function() replaceWithNew;
      await _pumpProviders(
        tester,
        speech: speech,
        home: Builder(
          builder: (context) {
            replaceWithNew = () {
              Navigator.of(context).pushReplacement(
                QuizScreen.routeItems(
                  items: [_soundKi()],
                  title: AppStrings.dailySession,
                ),
              );
            };
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  QuizScreen.routeItems(
                    items: [_soundKi()],
                    title: AppStrings.dailySession,
                  ),
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['き']);
      final firstGen = speech.generation;
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);

      replaceWithNew();
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      expect(tts.spoken, ['き', 'き']);
      expect(find.text(AppStrings.quizSoundInterrupted), findsNothing);
      expect(speech.generation, greaterThan(firstGen));
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);
      final stopsAfterReplace = tts.stopCount;

      await speech.stop(generation: firstGen);
      expect(tts.stopCount, stopsAfterReplace);
      expect(tts.pendingSpeaks.last.isCompleted, isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('quiz-replay')));
      await tester.pump();
      expect(tts.spoken, ['き', 'き', 'き']);
      expect(find.text(AppStrings.quizSoundInterrupted), findsNothing);
    },
  );

  testWidgets('Quiz soundToKana leave still cancels the owned play', (
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
              QuizScreen.routeItems(
                items: [_soundKi()],
                title: AppStrings.dailySession,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['き']);
    expect(tts.stopCount, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(tts.stopCount, greaterThan(1));
  });

  testWidgets('Quiz soundToKana もう一回 via results keeps the new autoplay', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    await _pumpProviders(
      tester,
      speech: speech,
      home: Builder(
        builder: (context) {
          void start({bool replace = false}) {
            final route = QuizScreen.routeItems(
              items: [_soundKi()],
              title: AppStrings.dailySession,
              onAgain: () => start(replace: true),
            );
            final nav = Navigator.of(context);
            replace ? nav.pushReplacement(route) : nav.push(route);
          }

          return Scaffold(
            body: TextButton(onPressed: start, child: const Text('open')),
          );
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['き']);
    tts.completeSpeak(0, 1);
    await tester.idle();
    await tester.pump();
    await tester.tap(find.text('き'));
    await tester.pump();
    await tester.tap(find.text(AppStrings.seeResults));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.practiceAgain), findsOneWidget);
    final stopsAtResult = tts.stopCount;
    final genAtResult = speech.generation;

    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(tts.spoken.last, 'き');
    expect(find.text(AppStrings.quizSoundInterrupted), findsNothing);
    expect(speech.generation, greaterThan(genAtResult));
    expect(tts.pendingSpeaks.last.isCompleted, isFalse);
    expect(tts.stopCount, stopsAtResult + 1);
  });
}
