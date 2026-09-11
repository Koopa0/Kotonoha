// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/ferry_session.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

export 'package:kotonoha/domain/models/travel_scene_id.dart';

/// Travel-purpose rooms the learner can ask for. This ticket owns scene
/// membership; it is not a generic content picker (#48 owns 精讀變化練習).

/// A read-only view of one scene against the learner's kana and 詞と句 stats.
/// Inspecting never writes progress — choosing a scene cannot unlock or
/// raise mastery.
class TravelSceneView {
  const TravelSceneView({
    required this.scene,
    required this.all,
    required this.readable,
    required this.unreadable,
    required this.unreadReadable,
    required this.seenReadable,
    required this.dueReadable,
    required this.missingUnits,
  });

  final TravelSceneId scene;
  final List<ReadingItem> all;
  final List<ReadingItem> readable;
  final List<ReadingItem> unreadable;
  final List<ReadingItem> unreadReadable;
  final List<ReadingItem> seenReadable;
  final List<ReadingItem> dueReadable;
  final List<String> missingUnits;

  bool get canMeet => unreadReadable.isNotEmpty;
  bool get canRecall => seenReadable.isNotEmpty;
  bool get canListen => seenReadable.isNotEmpty;
  bool get needsKanaFirst => readable.isEmpty;
}

/// Scene-scoped選材 and learn-then-practice composition.
///
/// Pools are existing corpus ids only. All four travel purposes walk the
/// same learn-then-practice gates; membership stays disjoint so one scene
/// never pads with another.
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class TravelScene {
  static const int length = 8;

  static const Set<TravelSceneId> walkable = {
    TravelSceneId.transport,
    TravelSceneId.clothing,
    TravelSceneId.shrine,
    TravelSceneId.parkQueue,
  };

  static const Map<TravelSceneId, List<String>> progressIds = {
    TravelSceneId.transport: [
      'phrase:えきは どこ',
      'phrase:でんしゃで かえる',
      'phrase:どこへ いく',
      'phrase:にもつは だいじょうぶ',
      'word:えき',
      'word:でんしゃ',
      'word:きっぷ',
      'word:かいさつ',
      'word:のりかえ',
      'word:にもつ',
      'word:でぐち',
      'word:みち',
      'word:ちず',
      'word:みぎ',
      'word:ひだり',
      'word:ここ',
      'word:ちかてつ',
      'word:バス',
      'word:タクシー',
      'word:しゅっぱつ',
      'word:とうちゃく',
    ],
    TravelSceneId.clothing: [
      'phrase:この ふくは ちいさい',
      'phrase:あかい ふくを かう',
      'phrase:しちゃくして いいですか',
      'phrase:しちゃくしつは どこ',
      'phrase:げんきんは いいですか',
      'phrase:げんきんで かいけい',
      'phrase:カードは つかえます',
      'phrase:カードは つかえません',
      'word:ふく',
      'word:かう',
      'word:おおきい',
      'word:おねがい',
      'word:ちいさい',
      'word:たかい',
      'word:やすい',
      'word:デパート',
      'word:しちゃく',
      'word:しちゃくしつ',
      'word:サイズ',
      'word:エス',
      'word:エム',
      'word:エル',
      'word:カード',
      'word:げんきん',
      'word:つかう',
      'word:つかえます',
      'word:つかえません',
      'word:かいけい',
      'word:いい',
    ],
    TravelSceneId.shrine: [
      'phrase:じんじゃは どこ',
      'phrase:しずかな てらに はいる',
      'phrase:ふるい おしろが みえる',
      'phrase:しゃしんを とる',
      'phrase:きれいな はなを みつけた',
      'phrase:こころが しずか',
      'word:じんじゃ',
      'word:てら',
      'word:ふるい',
      'word:しずか',
      'word:はいる',
      'word:みる',
      'word:れきし',
      'word:けしき',
      'word:おみやげ',
      'word:しゃしん',
      'word:きれい',
      'word:いし',
      'word:さくら',
      'word:はな',
      'word:やま',
      'word:もり',
      'word:にわ',
      'word:そっと',
      'word:まもる',
      'word:たいせつ',
      'word:さがす',
      'word:みつける',
    ],
    TravelSceneId.parkQueue: [
      'phrase:いりぐちで ならぶ',
      'phrase:たすけて ください',
      'phrase:みずを ください',
      'phrase:ちょっと まってください',
      'phrase:もういちど いってください',
      'phrase:ゆっくり はなしてください',
      'phrase:すこし つかれた',
      'phrase:きょうは たのしかった',
      'phrase:これは なに',
      'phrase:いま なんじ',
      'word:いりぐち',
      'word:ならぶ',
      'word:たすける',
      'word:まつ',
      'word:ちょっと',
      'word:トイレ',
      'word:よやく',
      'word:うけつけ',
      'word:だいじょうぶ',
      'word:わかる',
      'word:ひと',
      'word:こども',
      'word:おとな',
      'word:いそぐ',
      'word:つかれる',
      'word:にぎやか',
      'word:たのしい',
      'word:あそぶ',
      'word:けが',
      'word:くすり',
      'word:まだ',
      'word:やっと',
      'word:たくさん',
      'word:すぐ',
      'word:もんだい',
      'word:しつもん',
    ],
  };

  static bool isWalkable(TravelSceneId scene) => walkable.contains(scene);

  /// Corpus items for [scene], in the declared id order.
  static List<ReadingItem> items(
    TravelSceneId scene, {
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    final byId = <String, ReadingItem>{
      for (final item in words ?? kWords) item.progressId: item,
      for (final item in phrases ?? kPhrases) item.progressId: item,
    };
    return [
      for (final id in progressIds[scene]!)
        if (byId[id] != null) byId[id]!,
    ];
  }

  static TravelSceneView inspect({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    DateTime? now,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    final all = items(scene, words: words, phrases: phrases);
    final readable = ReadingSet.readable(all, learnedChars);
    final readableIds = {for (final item in readable) item.progressId};
    final unreadable = [
      for (final item in all)
        if (!readableIds.contains(item.progressId)) item,
    ];
    final unread = [
      for (final item in readable)
        if (!(stats[item.progressId]?.isSeen ?? false)) item,
    ];
    final seen = [
      for (final item in readable)
        if (stats[item.progressId]?.isSeen ?? false) item,
    ];
    final due = now == null
        ? const <ReadingItem>[]
        : [
            for (final item in seen)
              if (_isDue(stats[item.progressId], now)) item,
          ];
    return TravelSceneView(
      scene: scene,
      all: all,
      readable: readable,
      unreadable: unreadable,
      unreadReadable: unread,
      seenReadable: seen,
      dueReadable: due,
      missingUnits: missingUnits(unreadable, learnedChars),
    );
  }

  static bool _isDue(WordStat? stat, DateTime now) {
    final dueAt = stat?.dueAt;
    return dueAt != null && !dueAt.isAfter(now);
  }

  /// Units that still gate unreadability — a learn-first hint, not a lesson.
  static List<String> missingUnits(
    Iterable<ReadingItem> unreadable,
    Set<String> learnedChars,
  ) {
    final missing = <String>[];
    for (final item in unreadable) {
      for (final stretch in item.gatingText) {
        for (final token in KanaTokenizer.tokenize(stretch)) {
          if (token == KanaTokenizer.choonpu) continue;
          if (token == KanaTokenizer.sokuonHiragana) {
            if (!learnedChars.contains('つ') && !missing.contains('つ')) {
              missing.add('つ');
            }
            continue;
          }
          if (token == KanaTokenizer.sokuonKatakana) {
            if (!learnedChars.contains('ツ') && !missing.contains('ツ')) {
              missing.add('ツ');
            }
            continue;
          }
          if (KanaTokenizer.isReadable(token, learnedChars)) continue;
          if (!missing.contains(token)) missing.add(token);
        }
      }
    }
    return missing;
  }

  /// Unseen readable words in the scene. Never pads from another scene or
  /// the global ferry pool. Selecting the scene does not mark them seen.
  static List<Word> composeIntroWords({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    Set<String> excludeProgressIds = const {},
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
    int sessionLength = length,
  }) {
    final pool = _unreadWords(
      scene: scene,
      learnedChars: learnedChars,
      stats: stats,
      excludeProgressIds: excludeProgressIds,
      words: words,
      phrases: phrases,
    );
    final fallback = pool.isNotEmpty
        ? pool
        : _unreadWords(
            scene: scene,
            learnedChars: learnedChars,
            stats: stats,
            excludeProgressIds: const {},
            words: words,
            phrases: phrases,
          );
    if (fallback.isEmpty) return const [];
    final cap = min(sessionLength, fallback.length);
    return FerrySession.compose(
      words: fallback,
      learnedChars: learnedChars,
      rng: rng,
      now: now,
      stats: stats,
      length: cap,
      maxNew: cap,
    );
  }

  /// Unseen readable phrases in the scene. Same no-padding rule as words.
  static List<Phrase> composeIntroPhrases({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    Set<String> excludeProgressIds = const {},
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
    int sessionLength = length,
  }) {
    final pool = _unreadPhrases(
      scene: scene,
      learnedChars: learnedChars,
      stats: stats,
      excludeProgressIds: excludeProgressIds,
      words: words,
      phrases: phrases,
    );
    final fallback = pool.isNotEmpty
        ? pool
        : _unreadPhrases(
            scene: scene,
            learnedChars: learnedChars,
            stats: stats,
            excludeProgressIds: const {},
            words: words,
            phrases: phrases,
          );
    if (fallback.isEmpty) return const [];
    final cap = min(sessionLength, fallback.length);
    return ReadingSet.session(
      items: fallback,
      learnedChars: learnedChars,
      rng: rng,
      now: now,
      stats: stats,
      length: cap,
      maxNew: cap,
    );
  }

  /// True when another intro batch still exists in this scene after
  /// [excludeProgressIds]. Used so もう一回 never stays on a finished
  /// summary, and never pads from another scene.
  static bool hasMoreIntro({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    Set<String> excludeProgressIds = const {},
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
    int sessionLength = length,
  }) {
    return composeIntroWords(
          scene: scene,
          learnedChars: learnedChars,
          rng: rng,
          now: now,
          stats: stats,
          excludeProgressIds: excludeProgressIds,
          words: words,
          phrases: phrases,
          sessionLength: sessionLength,
        ).isNotEmpty ||
        composeIntroPhrases(
          scene: scene,
          learnedChars: learnedChars,
          rng: rng,
          now: now,
          stats: stats,
          excludeProgressIds: excludeProgressIds,
          words: words,
          phrases: phrases,
          sessionLength: sessionLength,
        ).isNotEmpty;
  }

  /// Already-met scene items only. Used for cold 回想 and for #9 聞き取り.
  /// Never introduces, never fills from another scene.
  static List<ReadingItem> composeReview({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    Set<String> excludeProgressIds = const {},
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
    int sessionLength = length,
  }) {
    final pool = items(scene, words: words, phrases: phrases);
    final seenPool = [
      for (final item in pool)
        if (stats[item.progressId]?.isSeen ?? false) item,
    ];
    final remaining = [
      for (final item in seenPool)
        if (!excludeProgressIds.contains(item.progressId)) item,
    ];
    final source = remaining.isNotEmpty ? remaining : seenPool;
    if (source.isEmpty) return const [];
    return ReadingSet.session(
      items: source,
      learnedChars: learnedChars,
      rng: rng,
      now: now,
      stats: stats,
      length: sessionLength,
      maxNew: 0,
    );
  }

  static List<Word> _unreadWords({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    required Set<String> excludeProgressIds,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    return [
      for (final item in items(scene, words: words, phrases: phrases))
        if (item is Word &&
            KanaTokenizer.isReadable(item.kana, learnedChars) &&
            !(stats[item.progressId]?.isSeen ?? false) &&
            !excludeProgressIds.contains(item.progressId))
          item,
    ];
  }

  static List<Phrase> _unreadPhrases({
    required TravelSceneId scene,
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    required Set<String> excludeProgressIds,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    return [
      for (final item in items(scene, words: words, phrases: phrases))
        if (item is Phrase &&
            item.gatingText.every(
              (t) => KanaTokenizer.isReadable(t, learnedChars),
            ) &&
            !(stats[item.progressId]?.isSeen ?? false) &&
            !excludeProgressIds.contains(item.progressId))
          item,
    ];
  }
}
