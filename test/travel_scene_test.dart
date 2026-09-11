// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/listening_session.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';

void main() {
  final allChars = {for (final kana in kAllKana) kana.character};
  final aKa = {'あ', 'い', 'う', 'え', 'お', 'か', 'き', 'く', 'け', 'こ'};
  final now = DateTime(2026, 9, 10, 12);

  WordStat seenAt([int? dueMs]) =>
      WordStat.fromJson({'s': 1, 'c': 0, 'w': 0, 'd': ?dueMs});

  test('every declared id exists once in the shipped corpus', () {
    final corpus = [...kWords, ...kPhrases];
    for (final scene in TravelSceneId.values) {
      final ids = TravelScene.progressIds[scene]!;
      expect(ids.toSet().length, ids.length, reason: scene.name);
      for (final id in ids) {
        expect(
          corpus.where((item) => item.progressId == id),
          hasLength(1),
          reason: id,
        );
      }
      expect(
        TravelScene.items(scene).map((i) => i.progressId),
        ids,
        reason: scene.name,
      );
    }
  });

  test('walkable scenes stay disjoint and do not invent phrases', () {
    expect(TravelScene.walkable, {
      TravelSceneId.transport,
      TravelSceneId.clothing,
    });
    final transport = TravelScene.progressIds[TravelSceneId.transport]!.toSet();
    final clothing = TravelScene.progressIds[TravelSceneId.clothing]!.toSet();
    expect(transport.intersection(clothing), isEmpty);
    expect(transport, contains('phrase:にもつは だいじょうぶ'));
    expect(clothing, contains('phrase:この ふくは ちいさい'));
    expect(clothing, contains('phrase:あかい ふくを かう'));
    expect(kPhrases.where((p) => p.kana == 'じんじゃは どこ'), hasLength(1));
  });

  test('inspect writes nothing and a newbie has only a learn-first path', () {
    final before = Map<String, WordStat>.from({});
    final view = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: const {},
      stats: before,
    );
    expect(view.needsKanaFirst, isTrue);
    expect(view.canMeet, isFalse);
    expect(view.canRecall, isFalse);
    expect(view.canListen, isFalse);
    expect(view.missingUnits, isNotEmpty);
    expect(before, isEmpty);
  });

  test('partial あ行・か行 opens different unread items per scene', () {
    final transport = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      stats: const {},
    );
    final clothing = TravelScene.inspect(
      scene: TravelSceneId.clothing,
      learnedChars: aKa,
      stats: const {},
    );
    expect(transport.readable.map((i) => i.progressId), contains('word:えき'));
    expect(transport.readable.map((i) => i.progressId), contains('word:ここ'));
    expect(
      transport.readable.map((i) => i.progressId),
      isNot(contains('word:ふく')),
    );
    expect(clothing.readable.map((i) => i.progressId), contains('word:かう'));
    expect(clothing.readable.map((i) => i.progressId), contains('word:おおきい'));
    expect(
      clothing.readable.map((i) => i.progressId),
      isNot(contains('word:えき')),
    );
    expect(transport.canMeet, isTrue);
    expect(clothing.canMeet, isTrue);
    expect(transport.canRecall, isFalse);
    expect(clothing.canRecall, isFalse);
  });

  test('intro stays inside the scene and does not mark items seen', () {
    final stats = <String, WordStat>{};
    final words = TravelScene.composeIntroWords(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      rng: Random(1),
      now: now,
      stats: stats,
    );
    expect(words, isNotEmpty);
    expect(
      words.map((w) => w.progressId).toSet(),
      everyElement(isIn(TravelScene.progressIds[TravelSceneId.transport]!)),
    );
    expect(words.map((w) => w.progressId).toSet(), isNot(contains('word:ふく')));
    expect(stats, isEmpty);
  });

  test('review and listening never introduce or leave the scene', () {
    final seen = {
      'word:えき': seenAt(),
      'word:ここ': seenAt(),
      'word:ふく': seenAt(),
      'phrase:そらが あおい': seenAt(),
    };
    final review = TravelScene.composeReview(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      rng: Random(2),
      now: now,
      stats: seen,
    );
    expect(review, isNotEmpty);
    expect(
      review.map((i) => i.progressId).toSet(),
      everyElement(anyOf('word:えき', 'word:ここ')),
    );
    expect(review.map((i) => i.progressId), isNot(contains('word:ふく')));
    expect(review.map((i) => i.progressId), isNot(contains('phrase:そらが あおい')));

    final empty = TravelScene.composeReview(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      rng: Random(3),
      now: now,
    );
    expect(empty, isEmpty);
  });

  test('もう一回 prefers remaining scene items then wraps', () {
    final seen = {
      'word:えき': seenAt(
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      ),
      'word:ここ': seenAt(
        now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
      ),
    };
    final first = TravelScene.composeReview(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      rng: Random(4),
      now: now,
      stats: seen,
      sessionLength: 1,
    );
    expect(first, hasLength(1));
    final second = TravelScene.composeReview(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      rng: Random(5),
      now: now,
      stats: seen,
      excludeProgressIds: {first.single.progressId},
      sessionLength: 1,
    );
    expect(second, hasLength(1));
    expect(second.single.progressId, isNot(first.single.progressId));
    final wrap = TravelScene.composeReview(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      rng: Random(6),
      now: now,
      stats: seen,
      excludeProgressIds: {'word:えき', 'word:ここ'},
      sessionLength: 1,
    );
    expect(wrap, hasLength(1));
    expect(wrap.single.progressId, anyOf('word:えき', 'word:ここ'));
  });

  test(
    'familiar scene still shuffles; two seeds are not a fixed card face',
    () {
      final seen = {
        for (final id in TravelScene.progressIds[TravelSceneId.transport]!)
          id: seenAt(),
      };
      final a = TravelScene.composeReview(
        scene: TravelSceneId.transport,
        learnedChars: allChars,
        rng: Random(11),
        now: now,
        stats: seen,
      );
      final b = TravelScene.composeReview(
        scene: TravelSceneId.transport,
        learnedChars: allChars,
        rng: Random(29),
        now: now,
        stats: seen,
      );
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(
        a.map((i) => i.progressId).toList(),
        isNot(equals(b.map((i) => i.progressId).toList())),
      );
    },
  );

  test(
    'returning learner can recall one scene without unlocking the other',
    () {
      final stats = {'word:えき': seenAt()};
      final transport = TravelScene.inspect(
        scene: TravelSceneId.transport,
        learnedChars: aKa,
        stats: stats,
      );
      final clothing = TravelScene.inspect(
        scene: TravelSceneId.clothing,
        learnedChars: aKa,
        stats: stats,
      );
      expect(transport.canRecall, isTrue);
      expect(transport.canListen, isTrue);
      expect(transport.canMeet, isTrue);
      expect(clothing.canRecall, isFalse);
      expect(clothing.canMeet, isTrue);
    },
  );

  test('hasMoreIntro is false on a spent あ行・か行 pool, true with leftover', () {
    final spent = {'word:えき': seenAt(), 'word:ここ': seenAt()};
    expect(
      TravelScene.hasMoreIntro(
        scene: TravelSceneId.transport,
        learnedChars: aKa,
        rng: Random(7),
        now: now,
        stats: spent,
      ),
      isFalse,
    );
    expect(
      TravelScene.hasMoreIntro(
        scene: TravelSceneId.transport,
        learnedChars: allChars,
        rng: Random(8),
        now: now,
        sessionLength: 1,
      ),
      isTrue,
    );
    final first = TravelScene.composeIntroWords(
      scene: TravelSceneId.transport,
      learnedChars: allChars,
      rng: Random(9),
      now: now,
      sessionLength: 1,
    );
    expect(first, hasLength(1));
    expect(
      TravelScene.hasMoreIntro(
        scene: TravelSceneId.transport,
        learnedChars: allChars,
        rng: Random(10),
        now: now,
        excludeProgressIds: {first.single.progressId},
        sessionLength: 1,
      ),
      isTrue,
    );
  });

  test('T01 listening pool is unchanged by travel scene membership', () {
    expect(
      ListeningSession.t01ProgressIds,
      containsAll(['phrase:えきは どこ', 'word:えき']),
    );
    expect(
      ListeningSession.t01ProgressIds,
      isNot(contains('phrase:この ふくは ちいさい')),
    );
    expect(
      ListeningSession.t01ProgressIds,
      isNot(contains('phrase:にもつは だいじょうぶ')),
    );
  });
}
