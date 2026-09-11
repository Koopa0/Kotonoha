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
    expect(TravelScene.walkable, TravelSceneId.values.toSet());
    final pools = {
      for (final scene in TravelSceneId.values)
        scene: TravelScene.progressIds[scene]!.toSet(),
    };
    for (final a in TravelSceneId.values) {
      for (final b in TravelSceneId.values) {
        if (a == b) continue;
        expect(pools[a]!.intersection(pools[b]!), isEmpty, reason: '$a ∩ $b');
      }
    }
    expect(pools[TravelSceneId.transport], contains('phrase:にもつは だいじょうぶ'));
    expect(pools[TravelSceneId.clothing], contains('phrase:この ふくは ちいさい'));
    expect(pools[TravelSceneId.clothing], contains('phrase:あかい ふくを かう'));
    expect(pools[TravelSceneId.clothing], contains('phrase:しちゃくして いいですか'));
    expect(pools[TravelSceneId.clothing], contains('phrase:しちゃくしつは どこ'));
    expect(pools[TravelSceneId.clothing], contains('phrase:げんきんは いいですか'));
    expect(pools[TravelSceneId.clothing], contains('phrase:カードは つかえます'));
    expect(pools[TravelSceneId.clothing], contains('phrase:カードは つかえません'));
    expect(pools[TravelSceneId.clothing], contains('word:サイズ'));
    expect(pools[TravelSceneId.clothing], contains('word:カード'));
    expect(pools[TravelSceneId.clothing], contains('word:デパート'));
    expect(pools[TravelSceneId.shrine], contains('phrase:じんじゃは どこ'));
    expect(pools[TravelSceneId.shrine], contains('phrase:ふるい おしろが みえる'));
    expect(pools[TravelSceneId.parkQueue], contains('phrase:いりぐちで ならぶ'));
    expect(pools[TravelSceneId.parkQueue], contains('phrase:たすけて ください'));
    expect(pools[TravelSceneId.restaurant], contains('phrase:なんにん ですか'));
    expect(pools[TravelSceneId.restaurant], contains('phrase:かいけいを おねがい'));
    expect(pools[TravelSceneId.convenience], contains('phrase:ふくろは いりますか'));
    expect(pools[TravelSceneId.convenience], contains('phrase:あたためますか'));
    expect(pools[TravelSceneId.hotel], contains('phrase:よやくが あります'));
    expect(pools[TravelSceneId.hotel], contains('phrase:あした でます'));
    expect(pools[TravelSceneId.hotel], isNot(contains('word:よやく')));
    expect(pools[TravelSceneId.hotel], isNot(contains('word:うけつけ')));
    for (final kana in const [
      'じんじゃは どこ',
      'しずかな てらに はいる',
      'ふるい おしろが みえる',
      'この ふくは ちいさい',
      'あかい ふくを かう',
      'しちゃくして いいですか',
      'しちゃくしつは どこ',
      'げんきんは いいですか',
      'げんきんで かいけい',
      'カードは つかえます',
      'カードは つかえません',
      'いりぐちで ならぶ',
      'にもつは だいじょうぶ',
      'たすけて ください',
      'なんにん ですか',
      'ごはんを ください',
      'かいけいを おねがい',
      'ふくろは いりますか',
      'あたためますか',
      'あたためて ください',
      'よやくが あります',
      'チェックインを おねがい',
      'あさごはんは ありますか',
      'あした でます',
    ]) {
      expect(kPhrases.where((p) => p.kana == kana), hasLength(1), reason: kana);
    }
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

  test('inspect lists due already-seen items without writing stats', () {
    final overdue = now.subtract(const Duration(days: 2));
    final stats = {'word:えき': seenAt(overdue.millisecondsSinceEpoch)};
    final view = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      stats: stats,
      now: now,
    );
    expect(view.dueReadable.map((i) => i.progressId), contains('word:えき'));
    expect(
      view.unreadReadable.map((i) => i.progressId),
      isNot(contains('word:えき')),
    );
    expect(stats['word:えき']!.seenCount, 1);
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
      isNot(contains('phrase:しちゃくして いいですか')),
    );
    expect(
      ListeningSession.t01ProgressIds,
      isNot(contains('phrase:げんきんで かいけい')),
    );
    expect(
      ListeningSession.t01ProgressIds,
      isNot(contains('phrase:にもつは だいじょうぶ')),
    );
    expect(ListeningSession.t01ProgressIds, isNot(contains('phrase:じんじゃは どこ')));
    expect(
      ListeningSession.t01ProgressIds,
      isNot(contains('phrase:たすけて ください')),
    );
    expect(ListeningSession.t01ProgressIds, isNot(contains('phrase:なんにん ですか')));
    expect(
      ListeningSession.t01ProgressIds,
      isNot(contains('phrase:ふくろは いりますか')),
    );
  });

  test('partial あ行・さ行 opens shrine いし, not park まつ', () {
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    final shrine = TravelScene.inspect(
      scene: TravelSceneId.shrine,
      learnedChars: aSa,
      stats: const {},
    );
    final park = TravelScene.inspect(
      scene: TravelSceneId.parkQueue,
      learnedChars: aSa,
      stats: const {},
    );
    expect(shrine.readable.map((i) => i.progressId), ['word:いし']);
    expect(shrine.canMeet, isTrue);
    expect(shrine.canRecall, isFalse);
    expect(park.readable, isEmpty);
    expect(park.needsKanaFirst, isTrue);
    expect(park.canMeet, isFalse);
  });

  test('partial た行・ま行 opens park まつ, not shrine いし', () {
    final taMa = {'た', 'ち', 'つ', 'て', 'と', 'ま', 'み', 'む', 'め', 'も'};
    final shrine = TravelScene.inspect(
      scene: TravelSceneId.shrine,
      learnedChars: taMa,
      stats: const {},
    );
    final park = TravelScene.inspect(
      scene: TravelSceneId.parkQueue,
      learnedChars: taMa,
      stats: const {},
    );
    expect(park.readable.map((i) => i.progressId), ['word:まつ']);
    expect(park.canMeet, isTrue);
    expect(shrine.readable, isEmpty);
    expect(shrine.needsKanaFirst, isTrue);
  });

  test('shrine and park intros stay inside the scene and write nothing', () {
    final stats = <String, WordStat>{};
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    final shrineWords = TravelScene.composeIntroWords(
      scene: TravelSceneId.shrine,
      learnedChars: aSa,
      rng: Random(1),
      now: now,
      stats: stats,
    );
    expect(shrineWords.map((w) => w.progressId), ['word:いし']);
    expect(stats, isEmpty);

    final taMa = {'た', 'ち', 'つ', 'て', 'と', 'ま', 'み', 'む', 'め', 'も'};
    final parkWords = TravelScene.composeIntroWords(
      scene: TravelSceneId.parkQueue,
      learnedChars: taMa,
      rng: Random(1),
      now: now,
      stats: stats,
    );
    expect(parkWords.map((w) => w.progressId), ['word:まつ']);
    expect(parkWords.map((w) => w.progressId), isNot(contains('word:いし')));
    expect(stats, isEmpty);
  });

  test('returning shrine learner does not unlock park recall', () {
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    final stats = {'word:いし': seenAt()};
    final shrine = TravelScene.inspect(
      scene: TravelSceneId.shrine,
      learnedChars: aSa,
      stats: stats,
    );
    final park = TravelScene.inspect(
      scene: TravelSceneId.parkQueue,
      learnedChars: aSa,
      stats: stats,
    );
    expect(shrine.canRecall, isTrue);
    expect(shrine.canListen, isTrue);
    expect(shrine.canMeet, isFalse);
    expect(park.canRecall, isFalse);
    expect(park.canMeet, isFalse);
    final review = TravelScene.composeReview(
      scene: TravelSceneId.shrine,
      learnedChars: aSa,
      rng: Random(2),
      now: now,
      stats: stats,
    );
    expect(review.map((i) => i.progressId), ['word:いし']);
    expect(review.map((i) => i.progressId), isNot(contains('word:まつ')));
  });

  test('spent shrine いし pool has no more intro; leftover kana still does', () {
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    expect(
      TravelScene.hasMoreIntro(
        scene: TravelSceneId.shrine,
        learnedChars: aSa,
        rng: Random(7),
        now: now,
        stats: {'word:いし': seenAt()},
      ),
      isFalse,
    );
    expect(
      TravelScene.hasMoreIntro(
        scene: TravelSceneId.shrine,
        learnedChars: allChars,
        rng: Random(8),
        now: now,
        sessionLength: 1,
      ),
      isTrue,
    );
  });

  test('clothing try-on and pay items stay in-scene and write nothing', () {
    final stats = <String, WordStat>{};
    final clothing = TravelScene.inspect(
      scene: TravelSceneId.clothing,
      learnedChars: allChars,
      stats: stats,
    );
    expect(
      clothing.all.map((i) => i.progressId),
      containsAll([
        'phrase:この ふくは ちいさい',
        'phrase:しちゃくして いいですか',
        'phrase:しちゃくしつは どこ',
        'phrase:げんきんは いいですか',
        'phrase:カードは つかえます',
        'phrase:カードは つかえません',
        'word:サイズ',
        'word:エル',
        'word:カード',
        'word:げんきん',
        'word:つかえます',
        'word:つかえません',
        'word:デパート',
      ]),
    );
    expect(clothing.all.map((i) => i.progressId), isNot(contains('word:えき')));
    final intro = TravelScene.composeIntroWords(
      scene: TravelSceneId.clothing,
      learnedChars: allChars,
      rng: Random(1),
      now: now,
      stats: stats,
    );
    expect(intro, isNotEmpty);
    expect(
      intro.map((w) => w.progressId).toSet(),
      everyElement(isIn(TravelScene.progressIds[TravelSceneId.clothing]!)),
    );
    expect(stats, isEmpty);
  });

  test('familiar shrine still shuffles; two seeds are not a fixed face', () {
    final seen = {
      for (final id in TravelScene.progressIds[TravelSceneId.shrine]!)
        id: seenAt(),
    };
    final a = TravelScene.composeReview(
      scene: TravelSceneId.shrine,
      learnedChars: allChars,
      rng: Random(11),
      now: now,
      stats: seen,
    );
    final b = TravelScene.composeReview(
      scene: TravelSceneId.shrine,
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
  });

  test('partial さ行 opens restaurant すし, not convenience ふくろ', () {
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    final restaurant = TravelScene.inspect(
      scene: TravelSceneId.restaurant,
      learnedChars: aSa,
      stats: const {},
    );
    final convenience = TravelScene.inspect(
      scene: TravelSceneId.convenience,
      learnedChars: aSa,
      stats: const {},
    );
    expect(restaurant.readable.map((i) => i.progressId), ['word:すし']);
    expect(restaurant.canMeet, isTrue);
    expect(restaurant.canRecall, isFalse);
    expect(convenience.readable, isEmpty);
    expect(convenience.needsKanaFirst, isTrue);
    expect(convenience.canMeet, isFalse);
  });

  test('partial は行・か行・ら行 opens convenience ふくろ, not restaurant すし', () {
    final haKaRa = {
      'か',
      'き',
      'く',
      'け',
      'こ',
      'は',
      'ひ',
      'ふ',
      'へ',
      'ほ',
      'ら',
      'り',
      'る',
      'れ',
      'ろ',
    };
    final restaurant = TravelScene.inspect(
      scene: TravelSceneId.restaurant,
      learnedChars: haKaRa,
      stats: const {},
    );
    final convenience = TravelScene.inspect(
      scene: TravelSceneId.convenience,
      learnedChars: haKaRa,
      stats: const {},
    );
    expect(convenience.readable.map((i) => i.progressId), ['word:ふくろ']);
    expect(convenience.canMeet, isTrue);
    expect(restaurant.readable, isEmpty);
    expect(restaurant.needsKanaFirst, isTrue);
  });

  test('restaurant and convenience intros stay inside the scene', () {
    final stats = <String, WordStat>{};
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    final restaurantWords = TravelScene.composeIntroWords(
      scene: TravelSceneId.restaurant,
      learnedChars: aSa,
      rng: Random(1),
      now: now,
      stats: stats,
    );
    expect(restaurantWords.map((w) => w.progressId), ['word:すし']);
    expect(stats, isEmpty);

    final haKaRa = {
      'か',
      'き',
      'く',
      'け',
      'こ',
      'は',
      'ひ',
      'ふ',
      'へ',
      'ほ',
      'ら',
      'り',
      'る',
      'れ',
      'ろ',
    };
    final convenienceWords = TravelScene.composeIntroWords(
      scene: TravelSceneId.convenience,
      learnedChars: haKaRa,
      rng: Random(1),
      now: now,
      stats: stats,
    );
    expect(convenienceWords.map((w) => w.progressId), ['word:ふくろ']);
    expect(
      convenienceWords.map((w) => w.progressId),
      isNot(contains('word:すし')),
    );
    expect(stats, isEmpty);
  });

  test('returning restaurant learner does not unlock convenience recall', () {
    final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
    final stats = {'word:すし': seenAt()};
    final restaurant = TravelScene.inspect(
      scene: TravelSceneId.restaurant,
      learnedChars: aSa,
      stats: stats,
    );
    final convenience = TravelScene.inspect(
      scene: TravelSceneId.convenience,
      learnedChars: aSa,
      stats: stats,
    );
    expect(restaurant.canRecall, isTrue);
    expect(restaurant.canListen, isTrue);
    expect(restaurant.canMeet, isFalse);
    expect(convenience.canRecall, isFalse);
    expect(convenience.canMeet, isFalse);
    final review = TravelScene.composeReview(
      scene: TravelSceneId.restaurant,
      learnedChars: aSa,
      rng: Random(2),
      now: now,
      stats: stats,
    );
    expect(review.map((i) => i.progressId), ['word:すし']);
    expect(review.map((i) => i.progressId), isNot(contains('word:ふくろ')));
  });

  test(
    'spent restaurant すし pool has no more intro; leftover kana still does',
    () {
      final aSa = {'あ', 'い', 'う', 'え', 'お', 'さ', 'し', 'す', 'せ', 'そ'};
      expect(
        TravelScene.hasMoreIntro(
          scene: TravelSceneId.restaurant,
          learnedChars: aSa,
          rng: Random(7),
          now: now,
          stats: {'word:すし': seenAt()},
        ),
        isFalse,
      );
      expect(
        TravelScene.hasMoreIntro(
          scene: TravelSceneId.restaurant,
          learnedChars: allChars,
          rng: Random(8),
          now: now,
          sessionLength: 1,
        ),
        isTrue,
      );
    },
  );

  test(
    'familiar restaurant still shuffles; two seeds are not a fixed face',
    () {
      final seen = {
        for (final id in TravelScene.progressIds[TravelSceneId.restaurant]!)
          id: seenAt(),
      };
      final a = TravelScene.composeReview(
        scene: TravelSceneId.restaurant,
        learnedChars: allChars,
        rng: Random(11),
        now: now,
        stats: seen,
      );
      final b = TravelScene.composeReview(
        scene: TravelSceneId.restaurant,
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

  test('partial は行・や行 opens hotel へや, not restaurant すし', () {
    const haYa = {'は', 'ひ', 'ふ', 'へ', 'ほ', 'や', 'ゆ', 'よ'};
    final hotel = TravelScene.inspect(
      scene: TravelSceneId.hotel,
      learnedChars: haYa,
      stats: const {},
    );
    final restaurant = TravelScene.inspect(
      scene: TravelSceneId.restaurant,
      learnedChars: haYa,
      stats: const {},
    );
    expect(hotel.readable.map((i) => i.progressId), ['word:へや']);
    expect(hotel.canMeet, isTrue);
    expect(restaurant.readable, isEmpty);
    expect(restaurant.needsKanaFirst, isTrue);
  });
}
