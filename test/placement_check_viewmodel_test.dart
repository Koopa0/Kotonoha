// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/placement/placement_check_viewmodel.dart';

import 'services/fake_preferences_service.dart';
import 'support/restore_recovery_test_support.dart';

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the placement check ViewModel's contract without pumping a widget:
/// the recoverable draft and its saves, the reveal and its commit, what an
/// outcome counts as, the persisted-hint presentation, the write block,
/// and the close.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime(2026, 9, 11, 12);
  var elapsed = 0;

  setUp(() {
    now = DateTime(2026, 9, 11, 12);
    elapsed = 0;
  });

  Future<
    ({
      PlacementCheckViewModel vm,
      KanaProgressRepository kana,
      PlacementCheckRepository checks,
      ProgressPersistenceController persistence,
      InMemoryAnalyticsLog log,
      FakePreferencesService fake,
      Lesson row,
    })
  >
  makeVm({
    PlacementDraft Function(PlacementDraft draft)? adjust,
    bool needsRecovery = false,
  }) async {
    final fake = FakePreferencesService();
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final checks = await PlacementCheckRepository.load(fake);
    final row = Lessons.fromKana(kana.allKana).first;
    var draft = PlacementCheck.start([row])!;
    if (adjust != null) draft = adjust(draft);
    await checks.save(draft);
    final persistence = ProgressPersistenceController(
      kanaFlush: kana.flushPending,
      kanjiFlush: kanji.flushPending,
      wordFlush: words.flushPending,
      placementFlush: checks.flushPending,
    );
    final recovery = recoveryForRepos(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
      needsRecovery: needsRecovery,
    );
    final log = InMemoryAnalyticsLog();
    final vm = PlacementCheckViewModel(
      draft: draft,
      checks: checks,
      kana: kana,
      persistence: persistence,
      recovery: recovery,
      analytics: log,
      sessionId: 'placement-test',
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    return (
      vm: vm,
      kana: kana,
      checks: checks,
      persistence: persistence,
      log: log,
      fake: fake,
      row: row,
    );
  }

  PlacementOutcome outcome({
    required bool correct,
    required bool unprompted,
    required bool hinted,
  }) => PlacementCheck.outcomeFor(
    correct: correct,
    unprompted: unprompted,
    hinted: hinted,
  );

  test('opens on the first pending kana, reading hidden', () async {
    final t = await makeVm();
    expect(t.vm.isEmpty, isFalse);
    expect(t.vm.total, t.row.kana.length);
    expect(t.vm.index, 0);
    expect(t.vm.current.target, t.row.kana.first);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.isUnpromptedCommit, isFalse);
    expect(t.vm.isAnswered, isFalse);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isBlocked, isFalse);
    expect(t.vm.draft.records, isEmpty);
    t.vm.dispose();
  });

  test('a draft with nothing pending is empty', () async {
    final t = await makeVm(
      adjust: (d) {
        var draft = d;
        for (final id in d.pendingKanaIds) {
          draft = PlacementCheck.record(
            draft,
            id,
            PlacementOutcome.independent,
          );
        }
        return draft;
      },
    );
    expect(t.vm.isEmpty, isTrue);
    t.vm.dispose();
  });

  group('reveal', () {
    test(
      'a hint persists exposure and is never an unprompted commit',
      () async {
        final t = await makeVm();
        final id = t.row.kana.first.id;
        var notifications = 0;
        t.vm.addListener(() => notifications++);
        t.vm.revealAsHint();
        expect(t.vm.isRevealed, isTrue);
        expect(t.vm.isUnpromptedCommit, isFalse);
        expect(t.vm.draft.isHinted(id), isTrue);
        expect(t.checks.draft.isHinted(id), isTrue);
        expect(notifications, 1);
        t.vm.revealAsHint(); // already revealed — silent
        expect(notifications, 1);
        await t.checks.flushPending();
        final reloaded = await PlacementCheckRepository.load(
          FakePreferencesService.restarted(t.fake),
        );
        expect(reloaded.draft.isHinted(id), isTrue);
        t.vm.dispose();
      },
    );

    test(
      '讀得出來 commits before the reading and still persists exposure',
      () async {
        final t = await makeVm();
        final id = t.row.kana.first.id;
        t.vm.noteAnswerablePresentation();
        t.vm.revealAfterUnpromptedCommit();
        expect(t.vm.isRevealed, isTrue);
        expect(t.vm.isUnpromptedCommit, isTrue);
        // Leave / reload cannot restart a first unprompted round.
        expect(t.checks.draft.isHinted(id), isTrue);
        t.vm.dispose();
      },
    );

    test('a persisted hint opens revealed and prompted', () async {
      final t = await makeVm(
        adjust: (d) => PlacementCheck.noteHinted(d, d.pendingKanaIds.first),
      );
      expect(t.vm.isRevealed, isTrue);
      expect(t.vm.isUnpromptedCommit, isFalse);
      t.vm.revealAfterUnpromptedCommit(); // the reading is already on screen
      expect(t.vm.isUnpromptedCommit, isFalse);
      t.vm.dispose();
    });
  });

  group('outcome', () {
    test(
      'unprompted correct is independent and graded as a timed recall',
      () async {
        final t = await makeVm();
        final id = t.row.kana.first.id;
        t.vm.noteAnswerablePresentation();
        elapsed = 900;
        now = now.add(const Duration(milliseconds: 900));
        t.vm.revealAfterUnpromptedCommit();
        t.vm.noteOutcome(correct: true);
        expect(t.vm.isAnswered, isTrue);
        final record = t.vm.draft.records.single;
        expect(record.kanaId, id);
        expect(
          record.outcome,
          outcome(correct: true, unprompted: true, hinted: false),
        );
        expect(t.checks.draft.records.single.outcome, record.outcome);
        expect(t.vm.draft.pendingKanaIds, isNot(contains(id)));
        final a = (await t.log.all()).single;
        expect(a.itemId, id);
        expect(a.correct, isTrue);
        expect(a.mode, PracticeMode.placementCheck.name);
        expect(a.meta[AttemptMeta.prompted], isFalse);
        expect(t.kana.statFor(t.row.kana.first).correctCount, 1);
        t.vm.dispose();
      },
    );

    test('a hinted correct is prompted and never a recall', () async {
      final t = await makeVm();
      t.vm.noteAnswerablePresentation();
      t.vm.revealAsHint();
      t.vm.noteOutcome(correct: true);
      expect(
        t.vm.draft.records.single.outcome,
        outcome(correct: true, unprompted: false, hinted: true),
      );
      final a = (await t.log.all()).single;
      expect(a.correct, isTrue);
      expect(a.meta[AttemptMeta.prompted], isTrue);
      expect(t.kana.statFor(t.row.kana.first).correctCount, 0);
      t.vm.dispose();
    });

    test('不知道 shows the reading as a hint and records a miss', () async {
      final t = await makeVm();
      final id = t.row.kana.first.id;
      t.vm.noteAnswerablePresentation();
      t.vm.markUnknown();
      expect(t.vm.isRevealed, isTrue);
      expect(t.vm.isAnswered, isTrue);
      expect(
        t.vm.draft.records.single.outcome,
        outcome(correct: false, unprompted: false, hinted: true),
      );
      // The hint is folded into the recorded outcome once graded.
      expect(t.checks.draft.records.single.kanaId, id);
      expect((await t.log.all()).single.correct, isFalse);
      t.vm.dispose();
    });

    test('an outcome needs a reveal and lands once', () async {
      final t = await makeVm();
      t.vm.noteAnswerablePresentation();
      t.vm.noteOutcome(correct: true); // nothing revealed yet
      expect(t.vm.isAnswered, isFalse);
      expect(t.vm.draft.records, isEmpty);
      t.vm.revealAsHint();
      t.vm.noteOutcome(correct: false);
      t.vm.noteOutcome(correct: true); // already answered
      expect(t.vm.draft.records, hasLength(1));
      expect(await t.log.all(), hasLength(1));
      t.vm.dispose();
    });
  });

  test(
    'advance moves to the next pending kana and closes after the last',
    () async {
      final t = await makeVm();
      final ids = t.row.kana.map((k) => k.id).toList();
      for (var n = 0; n < ids.length; n++) {
        expect(t.vm.index, n);
        expect(t.vm.current.target.id, ids[n]);
        expect(t.vm.isRevealed, isFalse);
        expect(t.vm.isLastQuestion, n == ids.length - 1);
        t.vm.noteAnswerablePresentation();
        t.vm.advance(); // nothing answered yet — ignored
        expect(t.vm.index, n);
        t.vm.revealAsHint();
        t.vm.noteOutcome(correct: true);
        t.vm.advance();
      }
      expect(t.vm.isFinished, isTrue);
      expect(t.vm.draft.isComplete, isTrue);
      expect(t.vm.draft.records, hasLength(ids.length));
      await _settle(() => t.checks.draft.isComplete);
      t.vm.dispose();
    },
  );

  test('a restore that needs recovery refuses every write', () async {
    final t = await makeVm(needsRecovery: true);
    expect(t.vm.isBlocked, isTrue);
    t.vm.noteAnswerablePresentation();
    t.vm.revealAsHint();
    t.vm.revealAfterUnpromptedCommit();
    t.vm.markUnknown();
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.isAnswered, isFalse);
    expect(t.vm.draft.hintedKanaIds, isEmpty);
    expect(t.vm.draft.records, isEmpty);
    expect(await t.log.all(), isEmpty);
    t.vm.dispose();
  });

  test('a failed draft save blocks the next write until retry', () async {
    final t = await makeVm();
    t.fake.failWrites.add(PlacementCheckRepository.storageKey);
    t.vm.noteAnswerablePresentation();
    t.vm.revealAsHint();
    await _settle(() => t.persistence.hasWriteFailure);
    expect(t.vm.isBlocked, isTrue);
    t.vm.noteOutcome(correct: true);
    expect(t.vm.isAnswered, isFalse);
    expect(t.vm.draft.records, isEmpty);

    t.fake.failWrites.clear();
    await t.persistence.retry();
    expect(t.vm.isBlocked, isFalse);
    t.vm.noteOutcome(correct: true);
    expect(t.vm.isAnswered, isTrue);
    expect(t.vm.draft.records, hasLength(1));
    t.vm.dispose();
  });
}
