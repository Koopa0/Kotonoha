// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm') // dart:io file I/O — not the web build
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production [FileAnalyticsLog] + the real answering caller
/// ([QuizViewModel.selectAnswer]). Replaces the issue #27 probe: a
/// filesystem fault after a successful open must not escape as an
/// uncaught async error, must keep the attempt in memory without
/// claiming disk success, and must not touch formal progress.
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

  test('runtime write failure is observed, retains the attempt, and leaves '
      'formal progress alone', () async {
    final log = FileAnalyticsLog.forFile(file);
    await log.all();
    await dir.delete(recursive: true);

    final repo = await KanaProgressRepository.load();
    final owner = ProgressPersistenceController(
      kanaFlush: repo.flushPending,
      kanjiFlush: () async {},
      wordFlush: () async {},
    );
    final q = question(kHiraganaGojuon.first);
    final vm = await makeVm(log: log, repo: repo, owner: owner, questions: [q]);

    Object? uncaught;
    await runZonedGuarded(() async {
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 1);
      // Give a rejected write a chance to escape if it were unobserved.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (e, _) => uncaught = e);

    await repo.flushPending();
    expect(uncaught, isNull);
    expect(vm.lastWasCorrect, isTrue);
    expect(vm.isAnswered, isTrue);
    expect(repo.statFor(q.target).seenCount, 1);
    expect(await log.count(), 1);
    expect(log.unpersistedCount, 1);
    expect(owner.hasWriteFailure, isFalse);
    expect(await file.exists(), isFalse);
  });

  test('a later answer still works while the path is down, then recovery '
      'writes each attempt once', () async {
    final log = FileAnalyticsLog.forFile(file);
    await log.all();
    await dir.delete(recursive: true);

    final repo = await KanaProgressRepository.load();
    final owner = ProgressPersistenceController(
      kanaFlush: repo.flushPending,
      kanjiFlush: () async {},
      wordFlush: () async {},
    );
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
      expect(vm.lastWasCorrect, isTrue);
      vm.advance();

      // Path still gone — answering must not block, flip to wrong, or
      // replay the first item.
      vm.selectAnswer(0);
      await settleObservedWrite(log, count: 2);
      expect(vm.lastWasCorrect, isTrue);
      expect(vm.index, 1);
      expect(await log.count(), 2);
      expect(log.unpersistedCount, 2);
      expect(repo.statFor(first).seenCount, 1);
      expect(repo.statFor(second).seenCount, 1);
      expect(owner.hasWriteFailure, isFalse);

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
}
