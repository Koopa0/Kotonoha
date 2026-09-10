// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/self_portrait.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

final _ki = kHiraganaGojuon.firstWhere((k) => k.character == 'き');
final _a = kHiraganaGojuon.firstWhere((k) => k.character == 'あ');

SessionItem soundItem(Kana kana) => SessionItem(
  question: QuizQuestion(
    target: kana,
    direction: QuizDirection.soundToKana,
    options: [kana.character, 'い', 'う', 'え'],
    correctIndex: 0,
  ),
  mode: PracticeMode.daily,
);

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

void pauseApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void resumeApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> pumpSoundQuiz(
  WidgetTester tester, {
  required SpeechService speech,
  required List<SessionItem> items,
  required KanaProgressRepository repo,
  required InMemoryAnalyticsLog log,
  DateTime Function()? clock,
  int Function()? monotonicMs,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: repo),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: repo.flushPending,
            kanjiFlush: () async {},
            wordFlush: () async {},
          ),
        ),
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: log),
      ],
      child: MaterialApp(
        home: QuizScreen(
          items: items,
          title: AppStrings.dailySession,
          clock: clock,
          monotonicMs: monotonicMs,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> tapCorrect(WidgetTester tester, Kana kana) async {
  await tester.tap(find.widgetWithText(AnswerOptionButton, kana.character));
  await tester.pump();
}

Future<void> tapContinue(WidgetTester tester) async {
  final next = find.text(AppStrings.continueLabel);
  if (next.evaluate().isNotEmpty) {
    await tester.tap(next);
  } else {
    await tester.tap(find.text(AppStrings.seeResults));
  }
  await tester.pump();
}

Future<void> expectKanaHasNoSoundEvidence({
  required KanaProgressRepository repo,
  required InMemoryAnalyticsLog analytics,
  required Kana kana,
}) async {
  await repo.flushPending();
  final reloaded = await KanaProgressRepository.load();
  expect(reloaded.statFor(kana).srsLevel, 0);
  expect(reloaded.statFor(kana).isSeen, isFalse);
  expect(repo.statFor(kana).srsLevel, 0);
  final logged = await analytics.all();
  expect(
    logged.where(
      (a) =>
          a.itemId == kana.id &&
          a.meta[AttemptMeta.heard] == true &&
          a.meta[AttemptMeta.scored] == true,
    ),
    isEmpty,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Silent soundToKana correct tap does not raise SRS', (
    tester,
  ) async {
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: const SilentSpeechService(),
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
    );

    expect(find.text(AppStrings.quizSoundUnavailable), findsOneWidget);
    await tapCorrect(tester, _ki);
    await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _ki);
    final logged = await log.all();
    expect(logged.single.correct, isTrue);
    expect(logged.single.meta[AttemptMeta.heard], isFalse);
    expect(logged.single.meta[AttemptMeta.scored], isFalse);
    expect(
      logged.single.meta[AttemptMeta.playback],
      SpeechPlaybackResult.unavailable.name,
    );
  });

  testWidgets('platform speak 0 then correct tap does not raise SRS', (
    tester,
  ) async {
    final client = FakeTtsClient(speakResult: 0);
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
    );

    expect(client.spoken, ['き']);
    expect(find.text(AppStrings.quizSoundFailed), findsOneWidget);
    await tapCorrect(tester, _ki);
    await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _ki);
  });

  testWidgets('fail then replay success then tap is unprompted SRS', (
    tester,
  ) async {
    final client = FakeTtsClient(speakResult: 0);
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
    );

    client.speakResult = 1;
    await tester.tap(find.byKey(const ValueKey<String>('quiz-replay')));
    await tester.pump();
    expect(find.text(AppStrings.quizSoundFailed), findsNothing);
    await tapCorrect(tester, _ki);

    await repo.flushPending();
    expect((await KanaProgressRepository.load()).statFor(_ki).srsLevel, 1);
    expect(repo.statFor(_ki).correctCount, 1);
    final logged = await log.all();
    expect(logged.single.meta[AttemptMeta.heard], isTrue);
    expect(logged.single.meta[AttemptMeta.scored], isTrue);
    expect(logged.single.meta[AttemptMeta.prompted], isFalse);
  });

  testWidgets('played then correct tap writes soundToKana evidence', (
    tester,
  ) async {
    final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
    );

    expect(speech.spoken, ['き']);
    await tapCorrect(tester, _ki);
    expect(repo.statFor(_ki).srsLevel, 1);
    expect((await log.all()).single.meta[AttemptMeta.scored], isTrue);
  });

  testWidgets('background interrupt is not a scored hear', (tester) async {
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final speech = HangingSpeechService();
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(speech.stopCount, greaterThanOrEqualTo(1));
    expect(find.text(AppStrings.quizSoundInterrupted), findsOneWidget);

    await tapCorrect(tester, _ki);
    await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _ki);
  });

  testWidgets('kanaToRomaji still records without waiting for audio', (
    tester,
  ) async {
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: const SilentSpeechService(),
      items: [
        SessionItem(
          question: QuizQuestion(
            target: _ki,
            direction: QuizDirection.kanaToRomaji,
            options: [_ki.romaji, 'i', 'u', 'e'],
            correctIndex: 0,
          ),
          mode: PracticeMode.quickReview,
        ),
      ],
      repo: repo,
      log: log,
    );

    await tester.tap(find.widgetWithText(AnswerOptionButton, _ki.romaji));
    await tester.pump();
    expect(repo.statFor(_ki).srsLevel, 1);
    expect((await log.all()).single.meta[AttemptMeta.heard], isNull);
  });

  testWidgets('old speak complete before advance cannot credit the next kana', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    expect(speech.ready, isTrue);
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki), soundItem(_a)],
      repo: repo,
      log: log,
    );
    expect(tts.spoken, ['き']);
    expect(tts.pendingFirstSpeak, isNotNull);

    await tapCorrect(tester, _ki);
    tts.completeFirstSpeak(1);
    await tester.idle();
    await tester.pump();
    await tapContinue(tester);
    await tester.pump();
    await tester.pump();

    await tapCorrect(tester, _a);
    await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _a);
  });

  testWidgets(
    'old speak complete after advance before next frame cannot credit あ',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      expect(speech.ready, isTrue);
      final repo = await KanaProgressRepository.load();
      final log = InMemoryAnalyticsLog();
      await pumpSoundQuiz(
        tester,
        speech: speech,
        items: [soundItem(_ki), soundItem(_a)],
        repo: repo,
        log: log,
      );

      await tapCorrect(tester, _ki);
      await tapContinue(tester);
      tts.completeFirstSpeak(1);
      await tester.idle();
      await tester.pump();

      await tapCorrect(tester, _a);
      await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _a);
    },
  );

  testWidgets(
    'old speak complete after next item failed play cannot credit あ',
    (tester) async {
      final tts = await _installProductionTts(tester);
      final speech = await FlutterTtsSpeechService.create();
      expect(speech.ready, isTrue);
      final repo = await KanaProgressRepository.load();
      final log = InMemoryAnalyticsLog();
      await pumpSoundQuiz(
        tester,
        speech: speech,
        items: [soundItem(_ki), soundItem(_a)],
        repo: repo,
        log: log,
      );

      await tapCorrect(tester, _ki);
      await tapContinue(tester);
      await tester.pump();
      expect(tts.spoken, ['き', 'あ']);
      tts.completeFirstSpeak(1);
      await tester.idle();
      await tester.pump();

      await tapCorrect(tester, _a);
      await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _a);
    },
  );

  testWidgets(
    'background auto-advance play is not a scored hear after resume',
    (tester) async {
      addTearDown(() => resumeApp(tester));
      final tts = await _installProductionTts(tester);
      tts.subsequentSpeakResult = 1;
      final speech = await FlutterTtsSpeechService.create();
      expect(speech.ready, isTrue);
      final repo = await KanaProgressRepository.load();
      final log = InMemoryAnalyticsLog();
      await pumpSoundQuiz(
        tester,
        speech: speech,
        items: [soundItem(_ki), soundItem(_a)],
        repo: repo,
        log: log,
      );
      tts.completeFirstSpeak(1);
      await tester.pump();
      await tapCorrect(tester, _ki);
      expect(repo.statFor(_ki).srsLevel, 1);

      pauseApp(tester);
      await tester.pump(const Duration(milliseconds: 800));
      resumeApp(tester);
      await tester.pump();

      await tapCorrect(tester, _a);
      await expectKanaHasNoSoundEvidence(repo: repo, analytics: log, kana: _a);
      expect((await log.all()).last.rtMs, 0);
    },
  );

  testWidgets(
    'unshown soundToKana replay after background advance times from the hear',
    (tester) async {
      addTearDown(() => resumeApp(tester));
      final tts = await _installProductionTts(tester);
      tts.subsequentSpeakResult = 1;
      final speech = await FlutterTtsSpeechService.create();
      final repo = await KanaProgressRepository.load();
      var now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(_a, correct: true, at: now, latencyMs: 500);
      }
      final log = InMemoryAnalyticsLog();
      await pumpSoundQuiz(
        tester,
        speech: speech,
        items: [soundItem(_ki), soundItem(_a)],
        repo: repo,
        log: log,
        clock: () => now,
        monotonicMs: () => elapsed,
      );
      tts.completeFirstSpeak(1);
      await tester.pump();
      elapsed = 500;
      now = now.add(const Duration(milliseconds: 500));
      await tapCorrect(tester, _ki);

      pauseApp(tester);
      await tester.pump(const Duration(milliseconds: 800));
      resumeApp(tester);
      await tester.pump();

      elapsed = 1000;
      now = now.add(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey<String>('quiz-replay')));
      await tester.pump();
      elapsed = 1500;
      now = now.add(const Duration(milliseconds: 500));
      await tapCorrect(tester, _a);
      await repo.flushPending();
      expect((await log.all()).last.rtMs, 500);
      expect((await log.all()).last.meta[AttemptMeta.heard], isTrue);
      expect((await KanaProgressRepository.load()).statFor(_a).srsLevel, 4);
      expect((await KanaProgressRepository.load()).statFor(_a).avgLatencyMs, 500);
    },
  );

  testWidgets('resume replay after background advance can restore a hear', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final tts = await _installProductionTts(tester);
    tts.subsequentSpeakResult = 1;
    final speech = await FlutterTtsSpeechService.create();
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki), soundItem(_a)],
      repo: repo,
      log: log,
    );
    tts.completeFirstSpeak(1);
    await tester.pump();
    await tapCorrect(tester, _ki);

    pauseApp(tester);
    await tester.pump(const Duration(milliseconds: 800));
    resumeApp(tester);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('quiz-replay')));
    await tester.pump();
    await tapCorrect(tester, _a);
    await repo.flushPending();
    expect((await KanaProgressRepository.load()).statFor(_a).srsLevel, 1);
    expect((await log.all()).last.meta[AttemptMeta.heard], isTrue);
  });

  testWidgets('answered rehear still stops when the app backgrounds', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final client = FakeTtsClient();
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
    );
    await tapCorrect(tester, _ki);
    client.holdSpeak = Completer<Object?>();
    await tester.tap(find.byKey(const ValueKey<String>('quiz-replay')));
    await tester.pump();
    final stopsBefore = client.stopCount;
    pauseApp(tester);
    await tester.pump();
    expect(client.stopCount, greaterThan(stopsBefore));
  });

  testWidgets('engine wait is not kana RT — hear at 10s, tap 500ms later', (
    tester,
  ) async {
    final tts = await _installProductionTts(tester);
    final speech = await FlutterTtsSpeechService.create();
    final repo = await KanaProgressRepository.load();
    final now0 = DateTime(2026, 9, 10, 12);
    var now = now0;
    var elapsed = 0;
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(_ki, correct: true, at: now0, latencyMs: 500);
    }
    expect(repo.statFor(_ki).avgLatencyMs, 500);
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki)],
      repo: repo,
      log: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    elapsed = 10000;
    now = now0.add(const Duration(milliseconds: 10000));
    tts.completeFirstSpeak(1);
    await tester.pump();
    elapsed = 10500;
    now = now0.add(const Duration(milliseconds: 10500));
    await tapCorrect(tester, _ki);
    await repo.flushPending();
    expect((await log.all()).single.rtMs, 500);
    expect(
      (await KanaProgressRepository.load()).statFor(_ki).avgLatencyMs,
      500,
    );
  });

  testWidgets('three silent き→い taps stay out of SelfPortrait observations', (
    tester,
  ) async {
    final client = FakeTtsClient(speakResult: 0);
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    await pumpSoundQuiz(
      tester,
      speech: speech,
      items: [soundItem(_ki), soundItem(_ki), soundItem(_ki)],
      repo: repo,
      log: log,
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.widgetWithText(AnswerOptionButton, 'い'));
      await tester.pump();
      if (i < 2) await tapContinue(tester);
      await tester.pump();
    }
    final logged = await log.all();
    expect(logged, hasLength(3));
    expect(
      logged.every(
        (a) =>
            a.itemId == 'き' &&
            a.distractor == 'い' &&
            a.meta[AttemptMeta.heard] == false &&
            a.meta[AttemptMeta.scored] == false,
      ),
      isTrue,
    );
    expect(repo.statFor(_ki).seenCount, 0);
    expect(SelfPortrait.observe(logged), isEmpty);
  });
}
