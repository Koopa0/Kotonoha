// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/ui/info/info_viewmodel.dart';

/// Reads the 聞き取る数 ViewModel's contract without pumping a widget or any
/// speech service: what a reported play means, how the pick is classified
/// (independent / peeked / hinted / miss / unheard), the hear clock, skip,
/// and the close.
void main() {
  var now = DateTime(2026, 9, 10, 12);
  setUp(() => now = DateTime(2026, 9, 10, 12));

  final first = kInfoDrills[0];
  final second = kInfoDrills[1];

  ({InfoViewModel vm, InMemoryAnalyticsLog log}) makeVm(
    List<InfoDrill> drills,
  ) {
    final log = InMemoryAnalyticsLog();
    final vm = InfoViewModel(
      drills: drills,
      analytics: log,
      sessionId: 's1',
      clock: () => now,
      rng: Random(0),
    );
    return (vm: vm, log: log);
  }

  void hear(InfoViewModel vm, {int itemIndex = 0}) => vm.notePlayback(
    itemIndex: itemIndex,
    result: SpeechPlaybackResult.played,
  );

  String wrong(InfoDrill d) => d.wrongAnswers.first;

  test('opens unheard with every choice offered', () {
    final t = makeVm([first, second]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, first);
    expect(t.vm.isHeard, isFalse);
    expect(t.vm.sawText, isFalse);
    expect(t.vm.hinted, isFalse);
    expect(t.vm.isAnswered, isFalse);
    expect(t.vm.answerPick, isNull);
    expect(t.vm.lastPlay, isNull);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.answerOrder.toSet(), first.answerChoices.toSet());
    expect(t.vm.isCorrect(first.correctAnswer), isTrue);
    expect(t.vm.isCorrect(wrong(first)), isFalse);
    t.vm.dispose();
  });

  test('heard → correct pick is independent, timed, keyed by kind', () async {
    final t = makeVm([first, second]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    hear(t.vm);
    now = now.add(const Duration(milliseconds: 1200));
    t.vm.pickAnswer(first.correctAnswer);
    expect(t.vm.isAnswered, isTrue);
    expect(t.vm.answerPick, first.correctAnswer);

    final a = (await t.log.all()).single;
    expect(a.mode, PracticeMode.info.name);
    expect(a.itemType, ItemType.word);
    expect(a.itemId, first.id);
    expect(a.correct, isTrue);
    expect(a.rtMs, 1200);
    expect(a.sessionId, 's1');
    expect(a.meta[AttemptMeta.beat], first.kind.name);
    expect(a.meta[AttemptMeta.evidence], ReplyEvidence.independent);
    expect(a.meta[AttemptMeta.heard], isTrue);
    expect(a.meta[AttemptMeta.prompted], isFalse);
    expect(a.meta[AttemptMeta.hinted], isFalse);
    expect(a.meta[AttemptMeta.scored], isTrue);
    expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.played.name);
    expect(a.meta.containsKey(AttemptMeta.distractor), isFalse);

    t.vm.advance();
    expect(t.vm.index, 1);
    expect(t.vm.current, second);
    expect(t.vm.isHeard, isFalse);
    expect(t.vm.isAnswered, isFalse);
    expect(t.vm.lastPlay, isNull);
    expect(t.vm.answerOrder.toSet(), second.answerChoices.toSet());
    expect(notifications, 3);
    t.vm.dispose();
  });

  group('evidence classes are never interchangeable', () {
    test('seeing the Japanese makes a correct pick peeked', () async {
      final t = makeVm([first]);
      hear(t.vm);
      t.vm.showText();
      t.vm.pickAnswer(first.correctAnswer);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.peeked);
      expect(a.meta[AttemptMeta.prompted], isTrue);
      expect(a.correct, isTrue);
      t.vm.dispose();
    });

    test('a meaning hint makes a correct pick hinted', () async {
      final t = makeVm([first]);
      hear(t.vm);
      t.vm.showHint();
      t.vm.pickAnswer(first.correctAnswer);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.hinted);
      expect(a.meta[AttemptMeta.hinted], isTrue);
      t.vm.dispose();
    });

    test('a wrong pick is a miss with its distractor', () async {
      final t = makeVm([first]);
      hear(t.vm);
      t.vm.pickAnswer(wrong(first));
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.miss);
      expect(a.correct, isFalse);
      expect(a.meta[AttemptMeta.distractor], wrong(first));
      t.vm.dispose();
    });

    test('an unheard pick is never scored', () async {
      final t = makeVm([first]);
      t.vm.notePlayback(itemIndex: 0, result: SpeechPlaybackResult.unavailable);
      now = now.add(const Duration(seconds: 2));
      t.vm.pickAnswer(first.correctAnswer);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.unheard);
      expect(a.meta[AttemptMeta.scored], isFalse);
      expect(a.correct, isFalse);
      expect(a.rtMs, 0);
      expect(
        a.meta[AttemptMeta.playback],
        SpeechPlaybackResult.unavailable.name,
      );
      t.vm.dispose();
    });
  });

  test('a stale completion is ignored; an interrupt is remembered', () async {
    final t = makeVm([first, second]);
    hear(t.vm, itemIndex: 1);
    expect(t.vm.isHeard, isFalse);
    t.vm.noteInterrupted();
    expect(t.vm.lastPlay, SpeechPlaybackResult.interrupted);
    t.vm.skipUnheard();
    final a = (await t.log.all()).single;
    expect(a.meta[AttemptMeta.evidence], ReplyEvidence.unheard);
    expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.interrupted.name);
    expect(a.meta.containsKey(AttemptMeta.distractor), isFalse);
    expect(t.vm.index, 1);
    expect(t.vm.lastPlay, isNull);
    t.vm.dispose();
  });

  test('the hear clock starts on the first completed play only', () async {
    final t = makeVm([first]);
    hear(t.vm);
    now = now.add(const Duration(seconds: 3));
    hear(t.vm);
    now = now.add(const Duration(seconds: 1));
    t.vm.pickAnswer(first.correctAnswer);
    expect((await t.log.all()).single.rtMs, 4000);
    t.vm.dispose();
  });

  test('commands off their step are ignored', () async {
    final t = makeVm([first]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.advance(); // nothing picked
    hear(t.vm);
    t.vm.skipUnheard(); // heard — not a skip
    expect(t.vm.index, 0);
    t.vm.pickAnswer(first.correctAnswer);
    t.vm.pickAnswer(wrong(first)); // already picked
    expect(t.vm.answerPick, first.correctAnswer);
    t.vm.skipUnheard(); // answered — not a skip
    expect(await t.log.all(), hasLength(1));
    t.vm.showText();
    t.vm.showText(); // already shown — silent
    expect(notifications, 3);
    t.vm.dispose();
  });

  test('finishes after the last drill and ignores anything after', () async {
    final t = makeVm([first]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    hear(t.vm);
    t.vm.pickAnswer(first.correctAnswer);
    t.vm.advance();
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.index, 0);
    expect(notifications, 3);

    hear(t.vm);
    t.vm.showHint();
    t.vm.pickAnswer(first.correctAnswer);
    t.vm.skipUnheard();
    t.vm.advance();
    expect(notifications, 3);
    expect(await t.log.all(), hasLength(1));
    t.vm.dispose();
  });
}
