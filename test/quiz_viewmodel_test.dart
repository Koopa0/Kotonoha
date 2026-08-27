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
}
