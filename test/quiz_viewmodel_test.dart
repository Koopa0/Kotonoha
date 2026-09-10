// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const all = kHiraganaGojuon;
  final fixedNow = DateTime(2026, 5, 29, 12);

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  QuizQuestion question(String character) {
    final target = all.firstWhere((k) => k.character == character);
    return QuizQuestion(
      target: target,
      direction: QuizDirection.kanaToRomaji,
      options: [target.romaji, 'xx', 'yy', 'zz'],
      correctIndex: 0,
    );
  }

  Future<QuizViewModel> makeVm(
    List<String> chars, {
    AnalyticsLog? analytics,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    return QuizViewModel(
      items: [
        for (final c in chars)
          SessionItem(question: question(c), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      analytics: analytics,
      clock: () => fixedNow,
    );
  }

  test('starts on the first question, unanswered', () async {
    final vm = await makeVm(['あ', 'い']);
    expect(vm.index, 0);
    expect(vm.total, 2);
    expect(vm.isAnswered, isFalse);
    expect(vm.isFinished, isFalse);
    expect(vm.optionState(0), OptionState.idle);
  });

  test(
    'selecting the right answer marks it correct and reveals state',
    () async {
      final vm = await makeVm(['か']);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.selectAnswer(0); // correct
      expect(vm.isAnswered, isTrue);
      expect(vm.lastWasCorrect, isTrue);
      expect(vm.optionState(0), OptionState.correct);
      expect(vm.optionState(1), OptionState.dimmed);
      expect(notifications, 1);
    },
  );

  test('selecting a wrong answer reveals the correct option', () async {
    final vm = await makeVm(['さ']);
    vm.selectAnswer(2); // wrong
    expect(vm.lastWasCorrect, isFalse);
    expect(vm.optionState(2), OptionState.wrong);
    expect(vm.optionState(0), OptionState.revealed); // the correct one
  });

  test('a second selection is ignored before advancing', () async {
    final vm = await makeVm(['た']);
    vm.selectAnswer(1); // wrong first
    vm.selectAnswer(0); // ignored
    expect(vm.optionState(1), OptionState.wrong);
    expect(vm.result.answers.single.selectedIndex, 1);
  });

  test('advance moves through questions then finishes', () async {
    final vm = await makeVm(['あ', 'い']);
    vm.selectAnswer(0);
    vm.advance();
    expect(vm.index, 1);
    expect(vm.isAnswered, isFalse);

    vm.selectAnswer(1); // wrong on last
    expect(vm.isLastQuestion, isTrue);
    vm.advance();
    expect(vm.isFinished, isTrue);
  });

  test('result reflects the whole session', () async {
    final vm = await makeVm(['あ', 'い', 'う']);
    vm.selectAnswer(0); // correct
    vm.advance();
    vm.selectAnswer(3); // wrong
    vm.advance();
    vm.selectAnswer(0); // correct
    vm.advance();

    final result = vm.result;
    expect(result.total, 3);
    expect(result.correctCount, 2);
    expect(result.missedKana.map((k) => k.character).toList(), ['い']);
  });

  test('records each answer to the repository', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('な'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      clock: () => fixedNow,
    );
    vm.selectAnswer(0);
    final stat = repo.statFor(all.firstWhere((k) => k.character == 'な'));
    expect(stat.seenCount, 1);
    expect(stat.correctCount, 1);
    expect(stat.lastReviewedAt, fixedNow);
  });

  test('normal 500ms monotonic elapsed is recorded as timed RT', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    elapsed = 500;
    vm.selectAnswer(0);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    expect(repo.statFor(kana).srsLevel, 4);
    expect((await log.all()).single.rtMs, 500);
    vm.dispose();
  });

  test('10-minute background invalidates RT but keeps correctness', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    vm.noteUnanswerable();
    now = now.add(const Duration(minutes: 10, milliseconds: 500));
    elapsed = 600500;
    vm.selectAnswer(0);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    expect(repo.statFor(kana).srsLevel, 3); // untimed holds at the cap
    expect(repo.statFor(kana).correctCount, 4);
    expect((await log.all()).single.rtMs, 0);
    vm.dispose();
  });

  test('wall-clock jump does not inject huge or negative RT', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    now = now.add(const Duration(minutes: 10, milliseconds: 500));
    elapsed = 500;
    vm.selectAnswer(0);
    expect((await log.all()).single.rtMs, 500);
    expect(repo.statFor(kana).avgLatencyMs, 500);

    now = DateTime(2026, 9, 10, 11); // wall clock jumped backward
    elapsed = 800;
    // already answered — a second select must not record
    vm.selectAnswer(0);
    expect((await log.all()).length, 1);
    vm.dispose();
  });

  test('resume-then-answer after interrupt is untimed, not 0ms-fast', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    vm.noteUnanswerable();
    elapsed = 1; // near-zero after resume must not count as super-fast
    vm.selectAnswer(0);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    expect(repo.statFor(kana).srsLevel, 3);
    vm.dispose();
  });

  test(
    'unshown visual item starts RT on first answerable presentation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await KanaProgressRepository.load();
      final now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      final kana = all.first;
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      final log = InMemoryAnalyticsLog();
      final vm = QuizViewModel(
        items: [
          SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
          SessionItem(question: question('い'), mode: PracticeMode.quickReview),
        ],
        repository: repo,
        persistence: owner(),
        analytics: log,
        clock: () => now,
        monotonicMs: () => elapsed,
      );
      elapsed = 500;
      vm.selectAnswer(0);
      vm.noteUnanswerable();
      vm.advance();
      vm.noteUnanswerable();
      elapsed = 800;
      vm.noteAnswerablePresentation();
      elapsed = 1300;
      vm.selectAnswer(0);
      expect((await log.all()).map((a) => a.rtMs), [500, 500]);
      expect(
        repo.statFor(all.firstWhere((k) => k.character == 'い')).srsLevel,
        1,
      );
      vm.dispose();
    },
  );

  test('resume after a presented interrupt does not restart RT', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    vm.noteAnswerablePresentation();
    vm.noteUnanswerable();
    elapsed = 500;
    vm.noteAnswerablePresentation();
    elapsed = 1000;
    vm.selectAnswer(0);
    expect((await log.all()).single.rtMs, 0);
    expect(repo.statFor(kana).srsLevel, 3);
    vm.dispose();
  });

  test('inactive-still-visible counts as presented', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    vm.noteUnanswerable(stillVisible: true);
    elapsed = 500;
    vm.noteAnswerablePresentation();
    elapsed = 1000;
    vm.selectAnswer(0);
    expect((await log.all()).single.rtMs, 0);
    vm.dispose();
  });

  test(
    'soundToKana unshown presentation still needs a hear for speed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await KanaProgressRepository.load();
      final now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      final kana = all.firstWhere((k) => k.character == 'き');
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      QuizQuestion listen() => QuizQuestion(
        target: kana,
        direction: QuizDirection.soundToKana,
        options: [kana.character, 'い', 'う', 'え'],
        correctIndex: 0,
      );
      final log = InMemoryAnalyticsLog();
      final vm = QuizViewModel(
        items: [SessionItem(question: listen(), mode: PracticeMode.daily)],
        repository: repo,
        persistence: owner(),
        analytics: log,
        clock: () => now,
        monotonicMs: () => elapsed,
      );
      vm.noteUnanswerable();
      elapsed = 800;
      vm.noteAnswerablePresentation();
      elapsed = 1300;
      vm.selectAnswer(0);
      expect((await log.all()).single.rtMs, 0);
      expect(repo.statFor(kana).avgLatencyMs, 500);
      vm.dispose();

      SharedPreferences.setMockInitialValues({});
      final repo2 = await KanaProgressRepository.load();
      for (var i = 0; i < 3; i++) {
        await repo2.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      final log2 = InMemoryAnalyticsLog();
      var elapsed2 = 0;
      final vm2 = QuizViewModel(
        items: [SessionItem(question: listen(), mode: PracticeMode.daily)],
        repository: repo2,
        persistence: owner(),
        analytics: log2,
        clock: () => now,
        monotonicMs: () => elapsed2,
      );
      vm2.noteUnanswerable();
      elapsed2 = 800;
      vm2.noteAnswerablePresentation();
      elapsed2 = 1000;
      vm2.noteListeningHeard();
      elapsed2 = 1500;
      vm2.selectAnswer(0);
      expect((await log2.all()).single.rtMs, 500);
      expect(repo2.statFor(kana).avgLatencyMs, 500);
      vm2.dispose();
    },
  );

  test(
    'soundToKana interrupt after hear stays untimed even after presentation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await KanaProgressRepository.load();
      final now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      final kana = all.firstWhere((k) => k.character == 'き');
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      final log = InMemoryAnalyticsLog();
      final vm = QuizViewModel(
        items: [
          SessionItem(
            question: QuizQuestion(
              target: kana,
              direction: QuizDirection.soundToKana,
              options: [kana.character, 'い', 'う', 'え'],
              correctIndex: 0,
            ),
            mode: PracticeMode.daily,
          ),
        ],
        repository: repo,
        persistence: owner(),
        analytics: log,
        clock: () => now,
        monotonicMs: () => elapsed,
      );
      vm.noteAnswerablePresentation();
      elapsed = 200;
      vm.noteListeningHeard();
      vm.noteUnanswerable();
      elapsed = 800;
      vm.noteAnswerablePresentation();
      vm.noteListeningHeard();
      elapsed = 1300;
      vm.selectAnswer(0);
      expect((await log.all()).single.rtMs, 0);
      expect(repo.statFor(kana).srsLevel, 3);
      vm.dispose();
    },
  );

  test('interrupt after answer does not double-record or auto-wrong', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    const elapsed = 500;
    final kana = all.first;
    final vm = QuizViewModel(
      items: [
        SessionItem(question: question('あ'), mode: PracticeMode.quickReview),
        SessionItem(question: question('い'), mode: PracticeMode.quickReview),
      ],
      repository: repo,
      persistence: owner(),
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    vm.selectAnswer(0);
    expect(repo.statFor(kana).seenCount, 1);
    expect(repo.statFor(kana).correctCount, 1);
    vm.noteUnanswerable();
    vm.selectAnswer(1); // ignored
    expect(repo.statFor(kana).seenCount, 1);
    expect(vm.lastWasCorrect, isTrue);
    vm.dispose();
  });

  test(
    'gradeRecall unprompted correct is timed; hinted correct is not',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await KanaProgressRepository.load();
      final now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      final kana = all.first;
      for (var i = 0; i < 3; i++) {
        await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      QuizQuestion recall() => QuizQuestion(
        target: kana,
        direction: QuizDirection.kanaRecall,
        options: const [],
        correctIndex: 0,
      );
      final log = InMemoryAnalyticsLog();
      final vm = QuizViewModel(
        items: [SessionItem(question: recall(), mode: PracticeMode.daily)],
        repository: repo,
        persistence: owner(),
        analytics: log,
        clock: () => now,
        monotonicMs: () => elapsed,
      );
      elapsed = 600;
      vm.gradeRecall(correct: true, unprompted: true);
      expect(vm.lastWasCorrect, isTrue);
      expect((await log.all()).single.meta[AttemptMeta.prompted], isFalse);
      expect((await log.all()).single.rtMs, 600);
      expect(repo.statFor(kana).avgLatencyMs, isNot(0));
      vm.dispose();

      SharedPreferences.setMockInitialValues({});
      final repo2 = await KanaProgressRepository.load();
      for (var i = 0; i < 3; i++) {
        await repo2.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      final before = repo2.statFor(kana).avgLatencyMs;
      final log2 = InMemoryAnalyticsLog();
      final vm2 = QuizViewModel(
        items: [SessionItem(question: recall(), mode: PracticeMode.daily)],
        repository: repo2,
        persistence: owner(),
        analytics: log2,
        clock: () => now,
        monotonicMs: () => 400,
      );
      final dueBefore = repo2.statFor(kana).dueAt;
      final correctBefore = repo2.statFor(kana).correctCount;
      vm2.gradeRecall(correct: true, unprompted: false);
      expect(repo2.statFor(kana).avgLatencyMs, before);
      expect(repo2.statFor(kana).correctCount, correctBefore);
      expect(repo2.statFor(kana).dueAt, dueBefore);
      expect((await log2.all()).single.meta[AttemptMeta.prompted], isTrue);
      expect((await log2.all()).single.rtMs, 0);
      vm2.dispose();
    },
  );

  test(
    'confirm wait after 讀得出來 does not enter recall RT or avgLatency',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await KanaProgressRepository.load();
      final now = DateTime(2026, 9, 10, 12);
      var elapsed = 0;
      final kana = all.first;
      for (var i = 0; i < 8; i++) {
        await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      expect(repo.statFor(kana).srsLevel, 6);
      expect(repo.statFor(kana).avgLatencyMs, 500);
      QuizQuestion recall() => QuizQuestion(
        target: kana,
        direction: QuizDirection.kanaRecall,
        options: const [],
        correctIndex: 0,
      );
      final log = InMemoryAnalyticsLog();
      final vm = QuizViewModel(
        items: [SessionItem(question: recall(), mode: PracticeMode.daily)],
        repository: repo,
        persistence: owner(),
        analytics: log,
        clock: () => now,
        monotonicMs: () => elapsed,
      );
      elapsed = 500;
      vm.captureUnpromptedRecall();
      elapsed = 10500;
      vm.gradeRecall(correct: true, unprompted: true);
      expect((await log.all()).single.rtMs, 500);
      expect(repo.statFor(kana).avgLatencyMs, 500);
      vm.dispose();

      SharedPreferences.setMockInitialValues({});
      final repo2 = await KanaProgressRepository.load();
      for (var i = 0; i < 8; i++) {
        await repo2.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
      }
      var elapsed2 = 0;
      final log2 = InMemoryAnalyticsLog();
      final vm2 = QuizViewModel(
        items: [SessionItem(question: recall(), mode: PracticeMode.daily)],
        repository: repo2,
        persistence: owner(),
        analytics: log2,
        clock: () => now,
        monotonicMs: () => elapsed2,
      );
      elapsed2 = 500;
      vm2.captureUnpromptedRecall();
      elapsed2 = 20000;
      vm2.gradeRecall(correct: true, unprompted: true);
      expect((await log2.all()).single.rtMs, 500);
      expect(repo2.statFor(kana).avgLatencyMs, 500);
      vm2.dispose();
    },
  );

  test('interrupt before 讀得出來 keeps confirmation untimed', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 8; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(
          question: QuizQuestion(
            target: kana,
            direction: QuizDirection.kanaRecall,
            options: const [],
            correctIndex: 0,
          ),
          mode: PracticeMode.daily,
        ),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    vm.noteUnanswerable();
    elapsed = 500;
    vm.captureUnpromptedRecall();
    elapsed = 10500;
    vm.gradeRecall(correct: true, unprompted: true);
    expect((await log.all()).single.rtMs, 0);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    vm.dispose();
  });

  test('interrupt after 讀得出來 keeps the frozen commit RT', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.first;
    for (var i = 0; i < 8; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(
          question: QuizQuestion(
            target: kana,
            direction: QuizDirection.kanaRecall,
            options: const [],
            correctIndex: 0,
          ),
          mode: PracticeMode.daily,
        ),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    elapsed = 500;
    vm.captureUnpromptedRecall();
    vm.noteUnanswerable();
    elapsed = 10500;
    vm.gradeRecall(correct: true, unprompted: true);
    expect((await log.all()).single.rtMs, 500);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    vm.dispose();
  });

  test('emits one Attempt to the analytics log per answer', () async {
    final log = InMemoryAnalyticsLog();
    final vm = await makeVm(['さ', 'し'], analytics: log);

    vm.selectAnswer(2); // wrong on さ
    vm.advance();
    vm.selectAnswer(0); // correct on し

    final attempts = await log.all();
    expect(attempts.length, 2);
    expect(attempts.first.itemId, 'さ');
    expect(attempts.first.mode, PracticeMode.quickReview.name);
    expect(attempts.first.direction, QuizDirection.kanaToRomaji.name);
    expect(attempts.first.correct, isFalse);
    expect(attempts.first.distractor, 'yy'); // the wrong option chosen
    expect(attempts.last.itemId, 'し');
    expect(attempts.last.correct, isTrue);
    expect(attempts.last.distractor, isNull);
  });

  test('persistProgress false skips SRS but still logs the attempt', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final kana = all.firstWhere((k) => k.character == 'き');
    final vm = QuizViewModel(
      items: [
        SessionItem(
          question: QuizQuestion(
            target: kana,
            direction: QuizDirection.soundToKana,
            options: [kana.character, 'い', 'う', 'え'],
            correctIndex: 0,
          ),
          mode: PracticeMode.daily,
        ),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => fixedNow,
    );
    vm.selectAnswer(
      0,
      persistProgress: false,
      extraMeta: {
        AttemptMeta.heard: false,
        AttemptMeta.scored: false,
        AttemptMeta.playback: 'failed',
      },
    );
    expect(repo.statFor(kana).srsLevel, 0);
    expect(repo.statFor(kana).isSeen, isFalse);
    expect(repo.statFor(kana).correctCount, 0);
    final logged = await log.all();
    expect(logged.single.correct, isTrue);
    expect(logged.single.meta[AttemptMeta.heard], isFalse);
    expect(logged.single.meta[AttemptMeta.scored], isFalse);
    expect(logged.single.meta[AttemptMeta.direction], 'soundToKana');
    vm.dispose();
  });

  test('soundToKana without a hear writes no speed evidence', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.firstWhere((k) => k.character == 'き');
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(
          question: QuizQuestion(
            target: kana,
            direction: QuizDirection.soundToKana,
            options: [kana.character, 'い', 'う', 'え'],
            correctIndex: 0,
          ),
          mode: PracticeMode.daily,
        ),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    elapsed = 10500;
    vm.selectAnswer(0);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    expect((await log.all()).single.rtMs, 0);
    vm.dispose();
  });

  test('soundToKana RT starts at the first foreground hear', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await KanaProgressRepository.load();
    final now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final kana = all.firstWhere((k) => k.character == 'き');
    for (var i = 0; i < 3; i++) {
      await repo.recordAnswer(kana, correct: true, at: now, latencyMs: 500);
    }
    final log = InMemoryAnalyticsLog();
    final vm = QuizViewModel(
      items: [
        SessionItem(
          question: QuizQuestion(
            target: kana,
            direction: QuizDirection.soundToKana,
            options: [kana.character, 'い', 'う', 'え'],
            correctIndex: 0,
          ),
          mode: PracticeMode.daily,
        ),
      ],
      repository: repo,
      persistence: owner(),
      analytics: log,
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    elapsed = 10000;
    vm.noteListeningHeard();
    elapsed = 10500;
    vm.selectAnswer(0);
    expect((await log.all()).single.rtMs, 500);
    expect(repo.statFor(kana).avgLatencyMs, 500);
    expect(repo.statFor(kana).srsLevel, 4);
    vm.dispose();
  });
}
