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
    const restaurantLeaks = ['問來了幾個人', '問要點什麼', '問還要不要別的', '幾個人', '要點什麼'];
    const convenienceLeaks = ['問要不要袋子', '問要不要加熱', '問可不可以結帳', '需要袋子嗎', '要加熱嗎'];
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
      final leaks = switch (drill.scene) {
        ReplySceneId.station => stationLeaks,
        ReplySceneId.clothing => clothingLeaks,
        ReplySceneId.restaurant => restaurantLeaks,
        ReplySceneId.convenience => convenienceLeaks,
      };
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
    expect(byId['reply:takai-yasui']!.sceneZh, contains('覺得'));
    expect(byId['reply:fuku-chiisai-kau']!.sceneZh, contains('帶走'));
    expect(byId['reply:kau-masu-ka']!.sceneZh, contains('紅色'));
    expect(byId['reply:nannin-hitori']!.sceneZh, contains('只坐你'));
    expect(byId['reply:nannin-futari']!.sceneZh, contains('同行入座'));
    expect(byId['reply:fukuro-hai']!.sceneZh, contains('沒有'));
    expect(byId['reply:atatame-iie']!.sceneZh, contains('以後'));
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

  test('この ふくは ちいさい scenes split おおきいの おねがい and かいます', () {
    final byId = {
      for (final drill in replyDrillsFor(ReplySceneId.clothing))
        drill.id: drill,
    };
    final bigger = byId['reply:fuku-chiisai-ookii']!;
    final buy = byId['reply:fuku-chiisai-kau']!;
    expect(bigger.promptKana, 'この ふくは ちいさい');
    expect(buy.promptKana, 'この ふくは ちいさい');
    expect(bigger.sceneZh, contains('大一號'));
    expect(buy.sceneZh, contains('帶走'));
    expect(bigger.replyCorrectKana, 'おおきいの おねがい');
    expect(buy.replyCorrectKana, 'かいます');
    expect(bigger.replyWrongKana, isNot(contains('かいます')));
    expect(bigger.replyWrongKana, isNot(contains('はい')));
    expect(buy.replyWrongKana, isNot(contains('おおきいの おねがい')));
    expect(buy.replyWrongKana, isNot(contains('はい')));
    expect(buy.replyWrongKana, contains('いいえ'));
  });

  test('takai-yasui scene states cheap judgment and rules out たかいです', () {
    final price = replyDrillsFor(ReplySceneId.clothing)
        .firstWhere((d) => d.id == 'reply:takai-yasui');
    expect(price.sceneZh, '你覺得這個價格很便宜。');
    expect(price.sceneZh, contains('便宜'));
    expect(price.sceneZh, isNot(contains('貴不貴')));
    expect(price.sceneZh, isNot(contains(price.promptMeaning)));
    expect(price.sceneZh, isNot(contains(price.intentCorrect)));
    expect(price.replyCorrectMeaning, '（它）便宜');
    expect(price.replyChoices, isNot(contains('はい')));
    expect(price.replyWrongKana, contains('たかいです'));
    expect(price.requiredSeenIds, containsAll(['word:たかい', 'word:やすい']));
  });

  test('ookii drill waits for おねがい before a scored size reply', () {
    final stats = {'phrase:この ふくは ちいさい': seenAt(), 'word:おおきい': seenAt()};
    final view = ReplySession.inspect(
      learnedChars: allChars,
      stats: stats,
      scene: ReplySceneId.clothing,
    );
    expect(view.ready, isEmpty);
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(view.unreadRequired.map((i) => i.progressId), contains('word:おねがい'));
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

  test('なんにん ですか scenes split ひとりです and ふたりです', () {
    final byId = {
      for (final drill in replyDrillsFor(ReplySceneId.restaurant))
        drill.id: drill,
    };
    final one = byId['reply:nannin-hitori']!;
    final two = byId['reply:nannin-futari']!;
    expect(one.promptKana, 'なんにん ですか');
    expect(two.promptKana, 'なんにん ですか');
    expect(one.replyCorrectKana, 'ひとりです');
    expect(two.replyCorrectKana, 'ふたりです');
    expect(one.replyWrongKana, isNot(contains('ふたりです')));
    expect(two.replyWrongKana, isNot(contains('ひとりです')));
    expect(one.requiredSeenIds, containsAll(['phrase:なんにん ですか', 'word:ひとり']));
    expect(two.requiredSeenIds, containsAll(['phrase:なんにん ですか', 'word:ふたり']));
  });

  test('restaurant compose stays in the restaurant pool', () {
    final stats = {
      for (final drill in replyDrillsFor(ReplySceneId.restaurant))
        for (final id in drill.requiredSeenIds) id: seenAt(),
    };
    final session = ReplySession.compose(
      learnedChars: allChars,
      rng: Random(2),
      stats: stats,
      scene: ReplySceneId.restaurant,
    );
    expect(session, hasLength(3));
    expect(session.map((d) => d.scene).toSet(), {ReplySceneId.restaurant});
    expect(session.map((d) => d.promptKana).toSet(), {
      'なんにん ですか',
      'なにに しますか',
      'ほかに よろしいですか',
    });
    expect(session.map((d) => d.promptKana), isNot(contains('ふくろは いりますか')));
    expect(session.map((d) => d.promptKana), isNot(contains('えきは どこ')));
  });

  test('あたためますか yes-scene accepts はい and あたためて ください', () {
    final byId = {
      for (final drill in replyDrillsFor(ReplySceneId.convenience))
        drill.id: drill,
    };
    final heat = byId['reply:atatame-kudasai']!;
    final skip = byId['reply:atatame-iie']!;
    expect(heat.replyAlsoCorrectKana, ['はい']);
    expect(heat.replyWrongKana, ['いいえ']);
    expect(heat.isReplyCorrect('あたためて ください'), isTrue);
    expect(heat.isReplyCorrect('はい'), isTrue);
    expect(heat.isReplyCorrect('いいえ'), isFalse);
    expect(skip.replyWrongKana, contains('はい'));
    expect(skip.isReplyCorrect('はい'), isFalse);
  });

  test('ほかに よろしいですか rice scene clarifies催飯 and drops いいえ distractor', () {
    final byId = {
      for (final drill in replyDrillsFor(ReplySceneId.restaurant))
        drill.id: drill,
    };
    final rice = byId['reply:hoka-gohan']!;
    final bill = byId['reply:hoka-kaikei']!;
    expect(rice.sceneZh, contains('還沒送上來'));
    expect(rice.replyCorrectKana, 'ごはんを ください');
    expect(rice.replyWrongKana, isNot(contains('いいえ')));
    expect(rice.replyWrongKana, contains('かいけいを おねがい'));
    expect(bill.replyCorrectKana, 'かいけいを おねがい');
  });

  test('ふくろは いりますか scenes split はい and いいえ', () {
    final byId = {
      for (final drill in replyDrillsFor(ReplySceneId.convenience))
        drill.id: drill,
    };
    final yes = byId['reply:fukuro-hai']!;
    final no = byId['reply:fukuro-iie']!;
    expect(yes.promptKana, 'ふくろは いりますか');
    expect(no.promptKana, 'ふくろは いりますか');
    expect(yes.replyCorrectKana, 'はい');
    expect(no.replyCorrectKana, 'いいえ');
    expect(yes.sceneZh, contains('沒有'));
    expect(no.sceneZh, contains('自己帶了'));
    expect(yes.requiredSeenIds, containsAll(['phrase:ふくろは いりますか', 'word:ふくろ']));
  });

  test('convenience compose stays in the convenience pool', () {
    final stats = {
      for (final drill in replyDrillsFor(ReplySceneId.convenience))
        for (final id in drill.requiredSeenIds) id: seenAt(),
    };
    final session = ReplySession.compose(
      learnedChars: allChars,
      rng: Random(2),
      stats: stats,
      scene: ReplySceneId.convenience,
    );
    expect(session, hasLength(3));
    expect(session.map((d) => d.scene).toSet(), {ReplySceneId.convenience});
    expect(session.map((d) => d.promptKana).toSet(), {
      'ふくろは いりますか',
      'あたためますか',
      'これで よろしいですか',
    });
    expect(session.map((d) => d.promptKana), isNot(contains('なんにん ですか')));
  });

  test('restaurant unreadRequired never pulls convenience phrases', () {
    final view = ReplySession.inspect(
      learnedChars: allChars,
      stats: const {},
      scene: ReplySceneId.restaurant,
    );
    expect(view.canMeet, isTrue);
    expect(
      view.unreadRequired.map((i) => i.progressId),
      isNot(contains('phrase:ふくろは いりますか')),
    );
    expect(
      view.unreadRequired.map((i) => i.progressId).toSet(),
      containsAll({
        'phrase:なんにん ですか',
        'phrase:なにに しますか',
        'word:ひとり',
        'word:ごはん',
        'word:かいけい',
      }),
    );
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
        'word:おねがい',
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
