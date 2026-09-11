// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/reply_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/listening_session.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';

void main() {
  final allChars = {for (final kana in kAllKana) kana.character};

  WordStat seenAt() => WordStat.fromJson({'s': 1, 'c': 0, 'w': 0});

  test(
    'catalog reuses shipped ids and does not invent the eight travel phrases',
    () {
      final corpus = [...kWords, ...kPhrases];
      expect(
        kReplyDrills.map((d) => d.id).toSet(),
        hasLength(kReplyDrills.length),
      );
      for (final drill in kReplyDrills) {
        for (final id in drill.requiredSeenIds) {
          expect(corpus.where((item) => item.progressId == id), hasLength(1));
        }
      }
      expect(kPhrases.where((p) => p.kana == 'きょうとです'), isEmpty);
      expect(kPhrases.where((p) => p.kana == 'ここは えきですか'), isEmpty);
      for (final kana in const [
        'じんじゃは どこ',
        'しずかな てらに はいる',
        'ふるい おしろが みえる',
        'この ふくは ちいさい',
        'あかい ふくを かう',
        'いりぐちで ならぶ',
        'にもつは だいじょうぶ',
        'たすけて ください',
      ]) {
        expect(
          kPhrases.where((p) => p.kana == kana),
          hasLength(1),
          reason: kana,
        );
      }
      expect(
        ListeningSession.t01ProgressIds,
        containsAll(['phrase:どこへ いく', 'phrase:えきは どこ']),
      );
      expect(
        TravelScene.progressIds[TravelSceneId.transport],
        containsAll(['phrase:どこへ いく', 'phrase:えきは どこ', 'word:えき', 'word:ここ']),
      );
    },
  );

  test('inspect writes nothing and a newbie has only a learn-first path', () {
    final stats = <String, WordStat>{};
    final view = ReplySession.inspect(learnedChars: const {}, stats: stats);
    expect(view.needsKanaFirst, isTrue);
    expect(view.canMeet, isFalse);
    expect(view.canPractice, isFalse);
    expect(view.missingUnits, isNotEmpty);
    expect(stats, isEmpty);
  });

  test('unmet readable drills offer meet items, not cold practice', () {
    final stats = <String, WordStat>{};
    final view = ReplySession.inspect(learnedChars: allChars, stats: stats);
    expect(view.needsKanaFirst, isFalse);
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(
      view.unreadRequired.map((i) => i.progressId).toSet(),
      containsAll({'phrase:どこへ いく', 'phrase:えきは どこ', 'word:ここ', 'word:えき'}),
    );
    expect(stats, isEmpty);
  });

  test('meeting えきは どこ only unlocks that station ask', () {
    final stats = {'phrase:えきは どこ': seenAt()};
    final view = ReplySession.inspect(learnedChars: allChars, stats: stats);
    expect(view.ready.map((d) => d.id), ['reply:eki-wa-doko']);
    expect(view.canPractice, isTrue);
    expect(
      view.unreadRequired.map((i) => i.progressId),
      isNot(contains('phrase:えきは どこ')),
    );
    final session = ReplySession.compose(
      learnedChars: allChars,
      rng: Random(1),
      stats: stats,
    );
    expect(session.map((d) => d.id), ['reply:eki-wa-doko']);
    expect(session.map((d) => d.promptKana), isNot(contains('ふく')));
  });

  test('recombination drill waits for ここ and えき, not a new phrase id', () {
    final one = ReplySession.inspect(
      learnedChars: allChars,
      stats: {'word:えき': seenAt()},
    );
    expect(one.ready, isEmpty);
    expect(one.unreadRequired.map((i) => i.progressId), contains('word:ここ'));
    final both = ReplySession.inspect(
      learnedChars: allChars,
      stats: {'word:えき': seenAt(), 'word:ここ': seenAt()},
    );
    expect(both.ready.map((d) => d.id), contains('reply:koko-wa-eki'));
  });

  test('compose never pads with clothing or shrine material', () {
    final stats = {
      for (final drill in kReplyDrills)
        for (final id in drill.requiredSeenIds) id: seenAt(),
    };
    final session = ReplySession.compose(
      learnedChars: allChars,
      rng: Random(4),
      stats: stats,
    );
    expect(session, hasLength(3));
    expect(session.map((d) => d.promptKana).toSet(), {
      'どこへ いく',
      'えきは どこ',
      'ここは えきですか',
    });
    expect(session.map((d) => d.replyCorrectKana), isNot(contains('ふく')));
  });

  test('evidence keeps hear / peek / hint / independent apart', () {
    expect(
      ReplyEvidence.classify(
        heard: false,
        sawText: false,
        usedHint: false,
        correct: true,
      ),
      ReplyEvidence.unheard,
    );
    expect(
      ReplyEvidence.classify(
        heard: true,
        sawText: true,
        usedHint: false,
        correct: true,
      ),
      ReplyEvidence.peeked,
    );
    expect(
      ReplyEvidence.classify(
        heard: true,
        sawText: false,
        usedHint: true,
        correct: true,
      ),
      ReplyEvidence.hinted,
    );
    expect(
      ReplyEvidence.classify(
        heard: true,
        sawText: false,
        usedHint: false,
        correct: true,
      ),
      ReplyEvidence.independent,
    );
    expect(
      ReplyEvidence.classify(
        heard: true,
        sawText: false,
        usedHint: false,
        correct: true,
        priorIndependent: false,
      ),
      ReplyEvidence.hinted,
    );
    expect(
      ReplyEvidence.classify(
        heard: true,
        sawText: false,
        usedHint: false,
        correct: false,
      ),
      ReplyEvidence.miss,
    );
    expect(ReplyEvidence.isIndependent(ReplyEvidence.peeked), isFalse);
  });
}
