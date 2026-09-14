// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/reply_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/ui/reply/reply_viewmodel.dart';

/// Reads the 短く返す ViewModel's contract without pumping a widget or any
/// speech service: what a reported play means, how each pick is classified
/// (independent / peeked / hinted / miss / unheard), the beats, the hear
/// clock, and the close.
void main() {
  var now = DateTime(2026, 9, 10, 12);
  setUp(() => now = DateTime(2026, 9, 10, 12));

  final ask = kReplyDrills.firstWhere((d) => d.id == 'reply:eki-wa-doko');
  final here = kReplyDrills.firstWhere((d) => d.id == 'reply:eki-wa-koko');

  ({ReplyViewModel vm, InMemoryAnalyticsLog log}) makeVm(
    List<ReplyDrill> drills,
  ) {
    final log = InMemoryAnalyticsLog();
    final vm = ReplyViewModel(
      drills: drills,
      analytics: log,
      sessionId: 's1',
      clock: () => now,
      rng: Random(0),
    );
    return (vm: vm, log: log);
  }

  void hear(ReplyViewModel vm, {int itemIndex = 0}) => vm.notePlayback(
    itemIndex: itemIndex,
    result: SpeechPlaybackResult.played,
  );

  String wrongIntent(ReplyDrill d) => d.intentWrong.first;
  String wrongReply(ReplyDrill d) => d.replyWrongKana.first;

  test('opens on the intent beat, unheard, with every choice offered', () {
    final t = makeVm([ask, here]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, ask);
    expect(t.vm.beat, ReplyBeat.intent);
    expect(t.vm.isHeard, isFalse);
    expect(t.vm.sawText, isFalse);
    expect(t.vm.hinted, isFalse);
    expect(t.vm.intentPick, isNull);
    expect(t.vm.replyPick, isNull);
    expect(t.vm.lastPlay, isNull);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.intentOrder.toSet(), ask.intentChoices.toSet());
    expect(t.vm.replyOrder.toSet(), ask.replyChoices.toSet());
    expect(t.vm.isIntentCorrect(ask.intentCorrect), isTrue);
    expect(t.vm.isIntentCorrect(wrongIntent(ask)), isFalse);
    expect(t.vm.isReplyCorrect(ask.replyCorrectKana), isTrue);
    expect(t.vm.isReplyCorrect(wrongReply(ask)), isFalse);
    t.vm.dispose();
  });

  test(
    'heard → intent → reply: both picks are independent and timed',
    () async {
      final t = makeVm([ask, here]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);

      hear(t.vm);
      expect(t.vm.isHeard, isTrue);
      expect(t.vm.lastPlay, SpeechPlaybackResult.played);
      now = now.add(const Duration(milliseconds: 1500));
      t.vm.pickIntent(ask.intentCorrect);
      expect(t.vm.intentPick, ask.intentCorrect);
      t.vm.toReply();
      expect(t.vm.beat, ReplyBeat.reply);
      now = now.add(const Duration(milliseconds: 700));
      t.vm.pickReply(ask.replyCorrectKana);
      expect(t.vm.replyPick, ask.replyCorrectKana);

      final logged = await t.log.all();
      expect(logged, hasLength(2));
      final intent = logged[0];
      expect(intent.mode, PracticeMode.reply.name);
      expect(intent.itemType, ItemType.word);
      expect(intent.itemId, ask.id);
      expect(intent.correct, isTrue);
      expect(intent.rtMs, 1500);
      expect(intent.sessionId, 's1');
      expect(intent.meta[AttemptMeta.beat], ReplyEvidence.intent);
      expect(intent.meta[AttemptMeta.evidence], ReplyEvidence.independent);
      expect(intent.meta[AttemptMeta.heard], isTrue);
      expect(intent.meta[AttemptMeta.prompted], isFalse);
      expect(intent.meta[AttemptMeta.hinted], isFalse);
      expect(intent.meta[AttemptMeta.scored], isTrue);
      expect(
        intent.meta[AttemptMeta.playback],
        SpeechPlaybackResult.played.name,
      );
      expect(intent.meta.containsKey(AttemptMeta.distractor), isFalse);
      final reply = logged[1];
      expect(reply.meta[AttemptMeta.beat], ReplyEvidence.reply);
      expect(reply.meta[AttemptMeta.evidence], ReplyEvidence.independent);
      expect(reply.rtMs, 2200);
      expect(reply.correct, isTrue);

      t.vm.advance();
      expect(t.vm.index, 1);
      expect(t.vm.current, here);
      expect(t.vm.beat, ReplyBeat.intent);
      expect(t.vm.isHeard, isFalse);
      expect(t.vm.intentPick, isNull);
      expect(t.vm.replyPick, isNull);
      expect(t.vm.lastPlay, isNull);
      expect(t.vm.intentOrder.toSet(), here.intentChoices.toSet());
      expect(notifications, 5);
      t.vm.dispose();
    },
  );

  group('evidence classes are never interchangeable', () {
    test('seeing the Japanese makes a correct pick peeked', () async {
      final t = makeVm([ask]);
      hear(t.vm);
      t.vm.showText();
      expect(t.vm.sawText, isTrue);
      t.vm.pickIntent(ask.intentCorrect);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.peeked);
      expect(a.meta[AttemptMeta.prompted], isTrue);
      expect(a.correct, isTrue);
      t.vm.dispose();
    });

    test('a meaning hint makes a correct pick hinted', () async {
      final t = makeVm([ask]);
      hear(t.vm);
      t.vm.showHint();
      expect(t.vm.hinted, isTrue);
      t.vm.pickIntent(ask.intentCorrect);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.hinted);
      expect(a.meta[AttemptMeta.hinted], isTrue);
      t.vm.dispose();
    });

    test('a reply after a peeked intent is at most hinted', () async {
      final t = makeVm([ask]);
      hear(t.vm);
      t.vm.showText();
      t.vm.pickIntent(ask.intentCorrect);
      t.vm.toReply();
      t.vm.pickReply(ask.replyCorrectKana);
      final logged = await t.log.all();
      expect(logged[1].meta[AttemptMeta.evidence], ReplyEvidence.peeked);
      t.vm.dispose();
    });

    test(
      'a reply after a missed intent is hinted, never independent',
      () async {
        final t = makeVm([ask]);
        hear(t.vm);
        t.vm.pickIntent(wrongIntent(ask));
        t.vm.toReply();
        t.vm.pickReply(ask.replyCorrectKana);
        final logged = await t.log.all();
        expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.miss);
        expect(logged[0].correct, isFalse);
        expect(logged[0].meta[AttemptMeta.distractor], wrongIntent(ask));
        expect(logged[1].meta[AttemptMeta.evidence], ReplyEvidence.hinted);
        expect(logged[1].correct, isTrue);
        t.vm.dispose();
      },
    );

    test('a wrong reply is a miss with its distractor', () async {
      final t = makeVm([ask]);
      hear(t.vm);
      t.vm.pickIntent(ask.intentCorrect);
      t.vm.toReply();
      t.vm.pickReply(wrongReply(ask));
      final reply = (await t.log.all())[1];
      expect(reply.meta[AttemptMeta.evidence], ReplyEvidence.miss);
      expect(reply.correct, isFalse);
      expect(reply.meta[AttemptMeta.distractor], wrongReply(ask));
      t.vm.dispose();
    });

    test('an unheard pick is never scored, whatever it was', () async {
      final t = makeVm([ask]);
      t.vm.notePlayback(itemIndex: 0, result: SpeechPlaybackResult.failed);
      expect(t.vm.isHeard, isFalse);
      expect(t.vm.lastPlay, SpeechPlaybackResult.failed);
      now = now.add(const Duration(seconds: 2));
      t.vm.pickIntent(ask.intentCorrect);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.unheard);
      expect(a.meta[AttemptMeta.scored], isFalse);
      expect(a.meta[AttemptMeta.heard], isFalse);
      expect(a.correct, isFalse);
      expect(a.rtMs, 0);
      expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.failed.name);
      t.vm.dispose();
    });
  });

  group('playback reports', () {
    test('a completion for another drill is stale and ignored', () {
      final t = makeVm([ask, here]);
      hear(t.vm, itemIndex: 1);
      expect(t.vm.isHeard, isFalse);
      expect(t.vm.lastPlay, isNull);
      t.vm.dispose();
    });

    test('an interrupt is remembered until the next drill', () async {
      final t = makeVm([ask, here]);
      t.vm.noteInterrupted();
      expect(t.vm.lastPlay, SpeechPlaybackResult.interrupted);
      t.vm.skipUnheard();
      expect(t.vm.lastPlay, isNull);
      final a = (await t.log.all()).single;
      expect(
        a.meta[AttemptMeta.playback],
        SpeechPlaybackResult.interrupted.name,
      );
      t.vm.dispose();
    });

    test('the hear clock starts on the first completed play only', () async {
      final t = makeVm([ask]);
      hear(t.vm);
      now = now.add(const Duration(seconds: 3));
      hear(t.vm); // a replay does not move the start
      now = now.add(const Duration(seconds: 1));
      t.vm.pickIntent(ask.intentCorrect);
      expect((await t.log.all()).single.rtMs, 4000);
      t.vm.dispose();
    });
  });

  test(
    'skip logs an unheard intent without a distractor and moves on',
    () async {
      final t = makeVm([ask, here]);
      t.vm.skipUnheard();
      final a = (await t.log.all()).single;
      expect(a.itemId, ask.id);
      expect(a.meta[AttemptMeta.beat], ReplyEvidence.intent);
      expect(a.meta[AttemptMeta.evidence], ReplyEvidence.unheard);
      expect(a.meta.containsKey(AttemptMeta.distractor), isFalse);
      expect(t.vm.index, 1);

      hear(t.vm, itemIndex: 1);
      t.vm.skipUnheard(); // heard — not a skip
      expect(t.vm.index, 1);
      expect(await t.log.all(), hasLength(1));
      t.vm.dispose();
    },
  );

  test('commands off their beat are ignored', () async {
    final t = makeVm([ask]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    hear(t.vm);
    t.vm.pickReply(ask.replyCorrectKana); // still the intent beat
    t.vm.toReply(); // no intent named yet
    t.vm.advance();
    expect(t.vm.beat, ReplyBeat.intent);
    expect(notifications, 1);

    t.vm.pickIntent(ask.intentCorrect);
    t.vm.pickIntent(wrongIntent(ask)); // already picked
    expect(t.vm.intentPick, ask.intentCorrect);
    t.vm.advance(); // no reply yet
    expect(t.vm.isFinished, isFalse);
    t.vm.toReply();
    t.vm.pickReply(ask.replyCorrectKana);
    t.vm.pickReply(wrongReply(ask)); // already picked
    expect(t.vm.replyPick, ask.replyCorrectKana);
    expect(await t.log.all(), hasLength(2));
    t.vm.showHint();
    t.vm.showHint(); // already shown — silent
    expect(notifications, 5);
    t.vm.dispose();
  });

  test('finishes after the last drill and ignores anything after', () async {
    final t = makeVm([ask]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    hear(t.vm);
    t.vm.pickIntent(ask.intentCorrect);
    t.vm.toReply();
    t.vm.pickReply(ask.replyCorrectKana);
    t.vm.advance();
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.index, 0);
    expect(notifications, 5);

    hear(t.vm);
    t.vm.showText();
    t.vm.pickIntent(ask.intentCorrect);
    t.vm.skipUnheard();
    t.vm.advance();
    expect(notifications, 5);
    expect(await t.log.all(), hasLength(2));
    t.vm.dispose();
  });
}
