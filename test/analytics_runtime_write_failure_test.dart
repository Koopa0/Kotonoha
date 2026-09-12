// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm') // dart:io file I/O — not the web build
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production [FileAnalyticsLog] + the real answering caller
/// ([QuizViewModel.selectAnswer]). #27 already keeps the attempt in
/// memory without an uncaught error; this file pins the follow-on
/// notify gap: [recordObserved] must raise the existing persistence
/// banner, and [ProgressPersistenceController.retry] must flush the
/// original rows once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('kotonoha-log-failure-');
    file = File('${dir.path}/log.jsonl');
    await file.create();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProgressPersistenceController ownerFor(
    KanaProgressRepository repo,
    FileAnalyticsLog log,
  ) {
    final owner = ProgressPersistenceController(
      kanaFlush: repo.flushPending,
      kanjiFlush: () async {},
      wordFlush: () async {},
      analyticsFlush: log.flushPending,
    );
    bindObservedWriteNotify(log, owner.trackAnalytics);
    return owner;
  }

  Future<QuizViewModel> makeVm({
    required FileAnalyticsLog log,
    required KanaProgressRepository repo,
    required ProgressPersistenceController owner,
    required List<QuizQuestion> questions,
  }) async {
    return QuizViewModel(
      items: [
        for (final q in questions)
          SessionItem(question: q, mode: PracticeMode.daily),
      ],
      repository: repo,
      persistence: owner,
      analytics: log,
    );
  }

  QuizQuestion question(Kana kana) => QuizQuestion(
    target: kana,
    direction: QuizDirection.kanaToRomaji,
    options: [kana.romaji, 'xx', 'yy', 'zz'],
    correctIndex: 0,
  );

  Future<void> settleObservedWrite(
    FileAnalyticsLog log, {
    required int count,
  }) async {
    for (var i = 0; i < 100; i++) {
      if (await log.count() >= count) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('analytics write never reached count $count');
  }

  Future<void> settleBanner(ProgressPersistenceController owner) async {
    for (var i = 0; i < 100; i++) {
      if (owner.hasWriteFailure) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('persistence owner never raised a write failure');
  }

  test(
    'recordObserved notifies the bound owner once; record does not',
    () async {
      final log = InMemoryAnalyticsLog();
      final writes = <Future<void>>[];
      bindObservedWriteNotify(log, writes.add);
      final attempt = Attempt(
        ts: 1,
        itemId: 'あ',
        mode: PracticeMode.daily.name,
        correct: true,
        rtMs: 0,
        sessionId: 's',
      );
      log.recordObserved(attempt);
      expect(writes, hasLength(1));
      await log.record(attempt);
      expect(writes, hasLength(1));
    },
  );

  test('runtime write failure is observed, retains the attempt, raises '
      'the persistence surface, and leaves formal progress alone', () async {
    final log = FileAnalyticsLog.forFile(file);
    await log.all();
    await dir.delete(recursive: true);

    final repo = await KanaProgressRepository.load();
    final owner = ownerFor(repo, log);
    final q = question(kHiraganaGojuon.first);
    final vm = await makeVm(log: log, repo: repo, owner: owner, questions: [q]);

    Object? uncaught;
    await runZonedGuarded(() async {
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 1);
      await settleBanner(owner);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (e, _) => uncaught = e);

    await repo.flushPending();
    expect(uncaught, isNull);
    expect(vm.lastWasCorrect, isTrue);
    expect(vm.isAnswered, isTrue);
    expect(repo.statFor(q.target).seenCount, 1);
    expect(await log.count(), 1);
    expect(log.unpersistedCount, 1);
    expect(owner.hasWriteFailure, isTrue);
    expect(await file.exists(), isFalse);
  });

  test('a later answer still works while the path is down, then recovery '
      'writes each attempt once', () async {
    final log = FileAnalyticsLog.forFile(file);
    await log.all();
    await dir.delete(recursive: true);

    final repo = await KanaProgressRepository.load();
    final owner = ownerFor(repo, log);
    final first = kHiraganaGojuon[0];
    final second = kHiraganaGojuon[1];
    final third = kHiraganaGojuon[2];
    final vm = await makeVm(
      log: log,
      repo: repo,
      owner: owner,
      questions: [question(first), question(second), question(third)],
    );

    Object? uncaught;
    await runZonedGuarded(() async {
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 1);
      await settleBanner(owner);
      expect(vm.lastWasCorrect, isTrue);
      expect(owner.hasWriteFailure, isTrue);
      vm.advance();

      // Path still gone — answering must not block, flip to wrong, or
      // replay the first item. The banner stays up.
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 2);
      expect(vm.lastWasCorrect, isTrue);
      expect(vm.index, 1);
      expect(await log.count(), 2);
      expect(log.unpersistedCount, 2);
      expect(repo.statFor(first).seenCount, 1);
      expect(repo.statFor(second).seenCount, 1);
      expect(owner.hasWriteFailure, isTrue);

      await dir.create(recursive: true);
      vm.advance();
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 3);
      await log.flushPending();
    }, (e, _) => uncaught = e);

    expect(uncaught, isNull);
    expect(await log.count(), 3);
    expect(log.unpersistedCount, 0);
    expect(owner.hasWriteFailure, isFalse);
    final ids = (await log.all()).map((a) => a.itemId).toList();
    expect(ids, [first.id, second.id, third.id]);
    final lines = await file.readAsLines();
    expect(lines.where((l) => l.trim().isNotEmpty).length, 3);
    final reopened = FileAnalyticsLog.forFile(file);
    expect((await reopened.all()).map((a) => a.itemId), ids);
  });

  test(
    'public retry after the path returns flushes each attempt once',
    () async {
      final log = FileAnalyticsLog.forFile(file);
      await log.all();
      await dir.delete(recursive: true);

      final repo = await KanaProgressRepository.load();
      final owner = ownerFor(repo, log);
      final first = kHiraganaGojuon[0];
      final second = kHiraganaGojuon[1];
      final vm = await makeVm(
        log: log,
        repo: repo,
        owner: owner,
        questions: [question(first), question(second)],
      );

      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 1);
      await settleBanner(owner);
      vm.advance();
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 2);
      await settleBanner(owner);

      expect(owner.hasWriteFailure, isTrue);
      expect(log.unpersistedCount, 2);
      expect(repo.statFor(first).seenCount, 1);
      expect(repo.statFor(second).seenCount, 1);
      expect(await file.exists(), isFalse);

      await dir.create(recursive: true);
      await owner.retry();

      expect(owner.hasWriteFailure, isFalse);
      expect(log.unpersistedCount, 0);
      expect(repo.statFor(first).seenCount, 1);
      expect(repo.statFor(second).seenCount, 1);
      final ids = (await log.all()).map((a) => a.itemId).toList();
      expect(ids, [first.id, second.id]);
      final lines = await file.readAsLines();
      expect(lines.where((l) => l.trim().isNotEmpty).length, 2);
      final reopened = FileAnalyticsLog.forFile(file);
      expect((await reopened.all()).map((a) => a.itemId), ids);
    },
  );

  testWidgets(
    'FileAnalyticsLog failure shows the banner; retry lands each row once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late FileAnalyticsLog log;
      late KanaProgressRepository repo;
      late ProgressPersistenceController owner;
      late QuizViewModel vm;
      late QuizQuestion q;

      await tester.runAsync(() async {
        log = FileAnalyticsLog.forFile(file);
        await log.all();
        await dir.delete(recursive: true);
        repo = await KanaProgressRepository.load();
        owner = ownerFor(repo, log);
        q = question(kHiraganaGojuon.first);
        vm = await makeVm(log: log, repo: repo, owner: owner, questions: [q]);
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: owner,
          child: const MaterialApp(
            home: PersistenceBanner(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(AppStrings.persistFailedLine), findsNothing);

      await tester.runAsync(() async {
        vm.selectAnswer(0);
        await settleObservedWrite(log, count: 1);
        await settleBanner(owner);
      });
      await tester.pump();
      await tester.pump();

      expect(owner.hasWriteFailure, isTrue);
      expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
      expect(find.text(AppStrings.persistRetry), findsOneWidget);
      expect(repo.statFor(q.target).seenCount, 1);
      expect(log.unpersistedCount, 1);

      List<String> ids = const [];
      await tester.runAsync(() async {
        await dir.create(recursive: true);
        await owner.retry();
        expect(log.unpersistedCount, 0);
        expect(repo.statFor(q.target).seenCount, 1);
        final reopened = FileAnalyticsLog.forFile(file);
        ids = (await reopened.all()).map((a) => a.itemId).toList();
        final lines = await file.readAsLines();
        expect(lines.where((l) => l.trim().isNotEmpty).length, 1);
      });
      await tester.pump();
      await tester.pump();

      expect(find.text(AppStrings.persistFailedLine), findsNothing);
      expect(owner.hasWriteFailure, isFalse);
      expect(ids, [q.target.id]);
    },
  );
}
