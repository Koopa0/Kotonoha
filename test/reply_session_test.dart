// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/reply_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
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
        expect(
          drill.requiredSeenIds,
          isNot(contains('phrase:${drill.replyCorrectKana}')),
        );
      }
      expect(
        kReplyDrills
            .firstWhere((d) => d.id == 'reply:eki-wa-doko')
            .requiredSeenIds,
        containsAll(['phrase:えきは どこ', 'word:みぎ']),
      );
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
    final view = ReplySession.inspect(
      learnedChars: const {},
      stats: stats,
      scene: ReplySceneId.station,
    );
    expect(view.needsKanaFirst, isTrue);
    expect(view.canMeet, isFalse);
    expect(view.canPractice, isFalse);
    expect(view.missingUnits, isNotEmpty);
    expect(stats, isEmpty);
  });

  test('unmet readable drills offer meet items, not cold practice', () {
    final stats = <String, WordStat>{};
    final view = ReplySession.inspect(
      learnedChars: allChars,
      stats: stats,
      scene: ReplySceneId.station,
    );
    expect(view.needsKanaFirst, isFalse);
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(
      view.unreadRequired.map((i) => i.progressId).toSet(),
      containsAll({
        'phrase:どこへ いく',
        'phrase:えきは どこ',
        'word:ここ',
        'word:えき',
        'word:みぎ',
      }),
    );
    expect(stats, isEmpty);
  });

  test('scene text is background only and does not translate the ask', () {
    const stationLeaks = ['問你', '要去哪', '問路', '車站在哪', '是不是車站', '這裡是車站嗎'];
    const clothingLeaks = ['這件太小', '價格貴', '要不要買', '這個貴嗎', '要買嗎'];
    for (final drill in kReplyDrills) {
      expect(
        drill.sceneZh,
        isNot(contains(drill.intentCorrect)),
        reason: drill.id,
      );
      expect(
        drill.sceneZh,
        isNot(contains(drill.promptMeaning)),
        reason: drill.id,
      );
      final leaks = drill.scene == ReplySceneId.station
          ? stationLeaks
          : clothingLeaks;
      for (final leak in leaks) {
        expect(
          drill.sceneZh,
          isNot(contains(leak)),
          reason: '${drill.id} $leak',
        );
      }
    }
    final byId = {for (final drill in kReplyDrills) drill.id: drill};
    expect(byId['reply:doko-e-iku']!.sceneZh, contains('京都'));
    expect(byId['reply:eki-wa-doko']!.sceneZh, contains('右'));
    expect(byId['reply:eki-wa-koko']!.sceneZh, contains('門口'));
    expect(byId['reply:koko-wa-eki']!.sceneZh, contains('車站'));
    expect(byId['reply:fuku-chiisai-ookii']!.sceneZh, contains('大一號'));
    expect(byId['reply:takai-yasui']!.sceneZh, contains('特價'));
    expect(byId['reply:kau-masu-ka']!.sceneZh, contains('紅色'));
  });

  test('えきは どこ scenes split みぎです and ここです; neither is a wrong answer', () {
    final byId = {for (final drill in kReplyDrills) drill.id: drill};
    final right = byId['reply:eki-wa-doko']!;
    final here = byId['reply:eki-wa-koko']!;
    expect(right.promptKana, 'えきは どこ');
    expect(here.promptKana, 'えきは どこ');
    expect(right.sceneZh, contains('右'));
    expect(here.sceneZh, contains('門口'));
    expect(right.replyCorrectKana, 'みぎです');
    expect(here.replyCorrectKana, 'ここです');
    expect(right.replyWrongKana, isNot(contains('ここです')));
    expect(here.replyWrongKana, isNot(contains('みぎです')));
    for (final drill in kReplyDrills.where((d) => d.promptKana == 'えきは どこ')) {
      expect(drill.replyWrongKana, isNot(contains('ここです')));
    }
  });

  test('meeting えきは どこ still teaches みぎ／ここ before a scored location reply', () {
    final stats = {'phrase:えきは どこ': seenAt()};
    final view = ReplySession.inspect(
      learnedChars: allChars,
      stats: stats,
      scene: ReplySceneId.station,
    );
    expect(view.ready, isEmpty);
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(
      view.unreadRequired.map((i) => i.progressId).toSet(),
      containsAll({'word:みぎ', 'word:ここ'}),
    );
    expect(
      view.unreadRequired.map((i) => i.progressId),
      isNot(contains('phrase:えきは どこ')),
    );
    expect(
      ReplySession.compose(
        learnedChars: allChars,
        rng: Random(1),
        stats: stats,
        scene: ReplySceneId.station,
      ),
      isEmpty,
    );
  });

  test('right-scene waits for みぎ; door-scene waits for ここ', () {
    final right = ReplySession.inspect(
      learnedChars: allChars,
      stats: {'phrase:えきは どこ': seenAt(), 'word:みぎ': seenAt()},
      scene: ReplySceneId.station,
    );
    expect(right.ready.map((d) => d.id), ['reply:eki-wa-doko']);
    expect(right.unreadRequired.map((i) => i.progressId), contains('word:ここ'));

    final door = ReplySession.inspect(
      learnedChars: allChars,
      stats: {'phrase:えきは どこ': seenAt(), 'word:ここ': seenAt()},
      scene: ReplySceneId.station,
    );
    expect(door.ready.map((d) => d.id), ['reply:eki-wa-koko']);
    expect(door.unreadRequired.map((i) => i.progressId), contains('word:みぎ'));
  });

  test('recombination drill waits for ここ and えき, not a new phrase id', () {
    final one = ReplySession.inspect(
      learnedChars: allChars,
      stats: {'word:えき': seenAt()},
      scene: ReplySceneId.station,
    );
    expect(one.ready, isEmpty);
    expect(one.unreadRequired.map((i) => i.progressId), contains('word:ここ'));
    final both = ReplySession.inspect(
      learnedChars: allChars,
      stats: {'word:えき': seenAt(), 'word:ここ': seenAt()},
      scene: ReplySceneId.station,
    );
    expect(both.ready.map((d) => d.id), contains('reply:koko-wa-eki'));
  });

  test('station compose never pads with clothing material', () {
    final stats = {
      for (final drill in replyDrillsFor(ReplySceneId.station))
        for (final id in drill.requiredSeenIds) id: seenAt(),
    };
    final session = ReplySession.compose(
      learnedChars: allChars,
      rng: Random(4),
      stats: stats,
      scene: ReplySceneId.station,
    );
    expect(session, hasLength(3));
    expect(session.map((d) => d.promptKana).toSet(), {
      'どこへ いく',
      'えきは どこ',
      'ここは えきですか',
    });
    expect(session.map((d) => d.replyCorrectKana), isNot(contains('ふく')));
  });

  test('この ふくは ちいさい scenes split おおきい おねがい and かいます', () {
    final byId = {
      for (final drill in replyDrillsFor(ReplySceneId.clothing)) drill.id: drill,
    };
    final bigger = byId['reply:fuku-chiisai-ookii']!;
    final buy = byId['reply:fuku-chiisai-kau']!;
    expect(bigger.promptKana, 'この ふくは ちいさい');
    expect(buy.promptKana, 'この ふくは ちいさい');
    expect(bigger.sceneZh, contains('大一號'));
    expect(buy.sceneZh, contains('紅色'));
    expect(bigger.replyCorrectKana, 'おおきい おねがい');
    expect(buy.replyCorrectKana, 'かいます');
    expect(bigger.replyWrongKana, isNot(contains('かいます')));
    expect(buy.replyWrongKana, isNot(contains('おおきい おねがい')));
  });

  test('clothing compose stays in the clothing pool', () {
    final stats = {
      for (final drill in replyDrillsFor(ReplySceneId.clothing))
        for (final id in drill.requiredSeenIds) id: seenAt(),
    };
    final session = ReplySession.compose(
      learnedChars: allChars,
      rng: Random(2),
      stats: stats,
      scene: ReplySceneId.clothing,
    );
    expect(session, hasLength(3));
    expect(session.map((d) => d.scene).toSet(), {ReplySceneId.clothing});
    expect(session.map((d) => d.promptKana).toSet(), {
      'この ふくは ちいさい',
      'たかい ですか',
      'かい ますか',
    });
    expect(session.map((d) => d.promptKana), isNot(contains('えきは どこ')));
  });

  test('clothing unreadRequired never pulls station phrases', () {
    final view = ReplySession.inspect(
      learnedChars: allChars,
      stats: const {},
      scene: ReplySceneId.clothing,
    );
    expect(view.canMeet, isTrue);
    expect(
      view.unreadRequired.map((i) => i.progressId),
      isNot(contains('phrase:えきは どこ')),
    );
    expect(
      view.unreadRequired.map((i) => i.progressId).toSet(),
      containsAll({
        'phrase:この ふくは ちいさい',
        'phrase:あかい ふくを かう',
        'word:おおきい',
        'word:かう',
        'word:たかい',
        'word:やすい',
      }),
    );
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
