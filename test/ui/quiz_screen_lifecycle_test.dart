// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Formal inversion of the #19 wall-clock probe: QuizScreen lifecycle
/// wiring through a real repository + analytics, not a VM-only clock jump.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final kana = kHiraganaGojuon.first;

  SessionItem item() => SessionItem(
    question: QuizQuestion(
      target: kana,
      direction: QuizDirection.kanaToRomaji,
      options: [kana.romaji, 'i', 'u', 'e'],
      correctIndex: 0,
    ),
    mode: PracticeMode.quickReview,
  );

  Future<
    ({
      KanaProgressRepository repo,
      InMemoryAnalyticsLog log,
      DateTime Function() clock,
      int Function() elapsed,
      void Function(DateTime) setNow,
      void Function(int) setElapsed,
    })
  >
  seedRepo() async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final repo = await KanaProgressRepository.load();
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    return (
      repo: repo,
      log: InMemoryAnalyticsLog(),
      clock: () => now,
      elapsed: () => elapsed,
      setNow: (DateTime v) => now = v,
      setElapsed: (int v) => elapsed = v,
    );
  }

  Future<void> pumpQuiz(
    WidgetTester tester, {
    required KanaProgressRepository repo,
    required InMemoryAnalyticsLog log,
    required DateTime Function() clock,
    required int Function() elapsed,
    List<SessionItem>? items,
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
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: log),
        ],
        child: MaterialApp(
          home: QuizScreen(
            items: items ?? [item()],
            title: 'probe',
            clock: clock,
            monotonicMs: elapsed,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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

  testWidgets(
    '10-minute background through QuizScreen does not pollute RT evidence',
    (tester) async {
      final env = await seedRepo();
      expect(env.repo.statFor(kana).avgLatencyMs, 500);
      expect(env.repo.statFor(kana).srsLevel, 3);

      await pumpQuiz(
        tester,
        repo: env.repo,
        log: env.log,
        clock: env.clock,
        elapsed: env.elapsed,
      );

      pauseApp(tester);
      await tester.pump();
      env.setNow(
        env.clock().add(const Duration(minutes: 10, milliseconds: 500)),
      );
      env.setElapsed(600500);
      resumeApp(tester);
      await tester.pump();

      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      await env.repo.flushPending();

      final after = (await KanaProgressRepository.load()).statFor(kana);
      final attempt = (await env.log.all()).single;
      expect(after.avgLatencyMs, 500);
      expect(after.srsLevel, 3);
      expect(after.correctCount, 4);
      expect(after.seenCount, 4);
      expect(attempt.rtMs, 0);
      expect(attempt.correct, isTrue);
      expect(Weakness.score(after, now: env.clock()), 0);
    },
  );

  testWidgets('auto-advance background does not double-record or auto-wrong', (
    tester,
  ) async {
    final env = await seedRepo();
    await pumpQuiz(
      tester,
      repo: env.repo,
      log: env.log,
      clock: env.clock,
      elapsed: env.elapsed,
      items: [item(), item()],
    );

    env.setElapsed(500);
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    expect(env.repo.statFor(kana).seenCount, 4);
    expect(env.repo.statFor(kana).correctCount, 4);

    pauseApp(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(env.repo.statFor(kana).seenCount, 4);
    expect(env.repo.statFor(kana).wrongCount, 0);
    expect((await env.log.all()).length, 1);
  });

  testWidgets('uninterrupted 500ms through QuizScreen stays timed', (
    tester,
  ) async {
    final env = await seedRepo();
    await pumpQuiz(
      tester,
      repo: env.repo,
      log: env.log,
      clock: env.clock,
      elapsed: env.elapsed,
    );
    env.setElapsed(500);
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    await env.repo.flushPending();
    expect(env.repo.statFor(kana).avgLatencyMs, 500);
    expect(env.repo.statFor(kana).srsLevel, 4);
    expect((await env.log.all()).single.rtMs, 500);
  });

  testWidgets(
    'unshown background visual Q2 starts RT on first answerable frame',
    (tester) async {
      addTearDown(() => resumeApp(tester));
      final env = await seedRepo();
      await pumpQuiz(
        tester,
        repo: env.repo,
        log: env.log,
        clock: env.clock,
        elapsed: env.elapsed,
        items: [item(), item(), item()],
      );

      env.setElapsed(500);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      expect((await env.log.all()).single.rtMs, 500);
      expect(env.repo.statFor(kana).srsLevel, 4);
      expect(env.repo.statFor(kana).correctCount, 4);

      pauseApp(tester);
      await tester.pump(const Duration(milliseconds: 800));
      expect((await env.log.all()).length, 1);
      expect(env.repo.statFor(kana).wrongCount, 0);
      expect(env.repo.statFor(kana).srsLevel, 4);

      resumeApp(tester);
      await tester.pump();
      env.setElapsed(1000);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      await env.repo.flushPending();
      expect((await env.log.all()).map((a) => a.rtMs), [500, 500]);
      expect(env.repo.statFor(kana).srsLevel, 5);
      expect(env.repo.statFor(kana).correctCount, 5);
      expect(env.repo.statFor(kana).avgLatencyMs, 500);

      await tester.pump(const Duration(milliseconds: 800));
      env.setElapsed(1500);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      await env.repo.flushPending();

      final attempts = await env.log.all();
      expect(attempts.map((a) => a.rtMs), [500, 500, 500]);
      expect(attempts.every((a) => a.correct), isTrue);
      expect(attempts, hasLength(3));
      final after = (await KanaProgressRepository.load()).statFor(kana);
      expect(after.srsLevel, 6);
      expect(after.avgLatencyMs, 500);
      expect(after.correctCount, 6);
      expect(after.wrongCount, 0);
      expect(after.seenCount, 6);
    },
  );

  testWidgets(
    'Q2 painted during lingering inactive after hidden stays untimed',
    (tester) async {
      addTearDown(() => resumeApp(tester));
      final env = await seedRepo();
      await pumpQuiz(
        tester,
        repo: env.repo,
        log: env.log,
        clock: env.clock,
        elapsed: env.elapsed,
        items: [item(), item(), item()],
      );

      env.setElapsed(500);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      expect((await env.log.all()).single.rtMs, 500);
      expect(env.repo.statFor(kana).srsLevel, 4);

      pauseApp(tester);
      await tester.pump(const Duration(milliseconds: 800));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      env.setNow(env.clock().add(const Duration(seconds: 10)));
      env.setElapsed(10500);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final gesture = await tester.press(find.text(kana.romaji));
      await tester.pump();
      env.setElapsed(11000);
      await gesture.up();
      await tester.pump();
      await env.repo.flushPending();
      expect((await env.log.all()).map((a) => a.rtMs), [500, 0]);
      expect(env.repo.statFor(kana).srsLevel, 4);
      expect(env.repo.statFor(kana).correctCount, 5);
      expect(env.repo.statFor(kana).avgLatencyMs, 500);

      await tester.pump(const Duration(milliseconds: 800));
      env.setElapsed(11500);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      await env.repo.flushPending();
      final attempts = await env.log.all();
      expect(attempts.map((a) => a.rtMs), [500, 0, 500]);
      expect(attempts.every((a) => a.correct), isTrue);
      final after = (await KanaProgressRepository.load()).statFor(kana);
      expect(after.srsLevel, 5);
      expect(after.avgLatencyMs, 500);
      expect(after.wrongCount, 0);
    },
  );

  testWidgets(
    'shown visual item stays untimed after resume and later questions time',
    (tester) async {
      addTearDown(() => resumeApp(tester));
      final env = await seedRepo();
      await pumpQuiz(
        tester,
        repo: env.repo,
        log: env.log,
        clock: env.clock,
        elapsed: env.elapsed,
        items: [item(), item()],
      );

      pauseApp(tester);
      await tester.pump();
      resumeApp(tester);
      await tester.pump();
      pauseApp(tester);
      await tester.pump();
      resumeApp(tester);
      await tester.pump();
      env.setElapsed(500);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      expect((await env.log.all()).single.rtMs, 0);
      expect(env.repo.statFor(kana).srsLevel, 3);
      expect(env.repo.statFor(kana).correctCount, 4);

      await tester.pump(const Duration(milliseconds: 800));
      env.setElapsed(1000);
      await tester.tap(find.text(kana.romaji));
      await tester.pump();
      await env.repo.flushPending();
      expect((await env.log.all()).map((a) => a.rtMs), [0, 500]);
      expect(env.repo.statFor(kana).srsLevel, 4);
      expect((await env.log.all()).every((a) => a.correct), isTrue);
    },
  );

  testWidgets('unshown Q2 that is later interrupted stays untimed', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final env = await seedRepo();
    await pumpQuiz(
      tester,
      repo: env.repo,
      log: env.log,
      clock: env.clock,
      elapsed: env.elapsed,
      items: [item(), item()],
    );

    env.setElapsed(500);
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    pauseApp(tester);
    await tester.pump(const Duration(milliseconds: 800));
    resumeApp(tester);
    await tester.pump();
    pauseApp(tester);
    await tester.pump();
    resumeApp(tester);
    await tester.pump();
    env.setElapsed(1000);
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    await env.repo.flushPending();
    expect((await env.log.all()).map((a) => a.rtMs), [500, 0]);
    expect(env.repo.statFor(kana).srsLevel, 4);
    expect(env.repo.statFor(kana).correctCount, 5);
  });

  testWidgets('inactive without hide is presented and stays untimed', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final env = await seedRepo();
    await pumpQuiz(
      tester,
      repo: env.repo,
      log: env.log,
      clock: env.clock,
      elapsed: env.elapsed,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    env.setElapsed(500);
    resumeApp(tester);
    await tester.pump();
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    await env.repo.flushPending();
    expect((await env.log.all()).single.rtMs, 0);
    expect(env.repo.statFor(kana).srsLevel, 3);
    expect(env.repo.statFor(kana).correctCount, 4);
  });

  testWidgets('Q2 born under stable inactive is presented and stays untimed', (
    tester,
  ) async {
    addTearDown(() => resumeApp(tester));
    final env = await seedRepo();
    await pumpQuiz(
      tester,
      repo: env.repo,
      log: env.log,
      clock: env.clock,
      elapsed: env.elapsed,
      items: [item(), item()],
    );

    env.setElapsed(500);
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 800));
    resumeApp(tester);
    await tester.pump();
    env.setElapsed(1000);
    await tester.tap(find.text(kana.romaji));
    await tester.pump();
    await env.repo.flushPending();
    expect((await env.log.all()).map((a) => a.rtMs), [500, 0]);
    expect(env.repo.statFor(kana).srsLevel, 4);
    expect(env.repo.statFor(kana).correctCount, 5);
  });
}
