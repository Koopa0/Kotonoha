// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/writing/writing_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the 習字 ViewModel's contract without pumping a widget or any
/// speech service: reveal, self-grade, the kana schedule and the attempt
/// stream, the close, and the persistence owner's failure / retry path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);
  final a = kHiraganaGojuon[0];
  final i = kHiraganaGojuon[1];

  Future<
    ({
      WritingViewModel vm,
      KanaProgressRepository kana,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm(
    List<Kana> targets, {
    KanaProgressRepository? kana,
    ProgressPersistenceController? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final resolvedKana = kana ?? await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final vm = WritingViewModel(
      targets: targets,
      kana: resolvedKana,
      persistence:
          persistence ??
          ProgressPersistenceController(
            kanaFlush: () async {},
            kanjiFlush: () async {},
            wordFlush: () async {},
          ),
      analytics: log,
      sessionId: 's1',
      clock: () => now,
    );
    return (vm: vm, kana: resolvedKana, log: log);
  }

  test('opens on the first kana, hidden', () async {
    final t = await makeVm([a, i]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, a);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.correctCount, 0);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isLastItem, isFalse);
    t.vm.dispose();
  });

  test('reveal → 記住了 climbs the kana and logs a write attempt', () async {
    final t = await makeVm([a, i]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    t.vm.reveal();
    expect(t.vm.isRevealed, isTrue);
    t.vm.grade(correct: true);

    final stat = t.kana.statFor(a);
    expect(stat.correctCount, 1);
    expect(stat.srsLevel, 1);
    expect(stat.lastReviewedAt, now);
    final logged = (await t.log.all()).single;
    expect(logged.mode, PracticeMode.writing.name);
    expect(logged.itemId, a.id);
    expect(logged.correct, isTrue);
    expect(logged.rtMs, 0);
    expect(logged.sessionId, 's1');
    expect(logged.meta[AttemptMeta.direction], 'write');

    expect(t.vm.index, 1);
    expect(t.vm.current, i);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.correctCount, 1);
    expect(notifications, 2);
    t.vm.dispose();
  });

  test('a miss resets the kana', () async {
    final t = await makeVm([a]);
    await t.kana.recordAnswer(a, correct: true, at: now);
    t.vm.reveal();
    t.vm.grade(correct: false);
    final stat = t.kana.statFor(a);
    expect(stat.srsLevel, 0);
    expect(stat.wrongCount, 1);
    expect((await t.log.all()).single.correct, isFalse);
    expect(t.vm.correctCount, 0);
    t.vm.dispose();
  });

  test('a grade before reveal and a second reveal are ignored', () async {
    final t = await makeVm([a]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.grade(correct: true);
    expect(t.vm.index, 0);
    expect(await t.log.all(), isEmpty);
    t.vm.reveal();
    t.vm.reveal();
    expect(notifications, 1);
    t.vm.dispose();
  });

  test('finishes on the last kana and ignores anything after', () async {
    final t = await makeVm([a]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.reveal();
    t.vm.grade(correct: true);
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.index, 0);
    expect(notifications, 2);

    t.vm.reveal();
    t.vm.grade(correct: false);
    expect(notifications, 2);
    expect(await t.log.all(), hasLength(1));
    expect(t.kana.statFor(a).wrongCount, 0);
    t.vm.dispose();
  });

  test(
    'a failed save surfaces on the owner and retry flushes without re-climbing',
    () async {
      final fake = FakePreferencesService();
      final kana = await KanaProgressRepository.load(fake);
      fake.failWrites.add('kana_stats_v1');
      final persist = ProgressPersistenceController(
        kanaFlush: kana.flushPending,
        kanjiFlush: () async {},
        wordFlush: () async {},
      );
      final t = await makeVm([a], kana: kana, persistence: persist);

      t.vm.reveal();
      t.vm.grade(correct: true);
      expect(kana.statFor(a).srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(kana.statFor(a).srsLevel, 1);
      expect(kana.statFor(a).correctCount, 1);
      final reloaded = await KanaProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statFor(a).srsLevel, 1);
      t.vm.dispose();
    },
  );
}
