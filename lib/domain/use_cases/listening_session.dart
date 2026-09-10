// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

/// First-slice 聞き取り pool: Kyoto-station asking-directions and asking-to-
/// repeat, taken from already-shipped words/phrases. Does not introduce
/// (maxNew: 0) and does not retune [ReadingSet] / ferry intake.
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class ListeningSession {
  /// A short listen-first pass — about one commute slice, not a daily cap.
  static const int length = 8;

  /// T01 station / request-repeat identities. Dataset order is the
  /// introduction order; missing ids fail [pool] loudly in tests.
  static const List<String> t01ProgressIds = [
    'phrase:えきは どこ',
    'phrase:どこへ いく',
    'phrase:もういちど いってください',
    'phrase:ゆっくり はなしてください',
    'phrase:ちょっと まってください',
    'word:えき',
    'word:ここ',
    'word:みち',
    'word:でぐち',
    'word:きっぷ',
    'word:ゆっくり',
    'word:みぎ',
    'word:ひだり',
    'word:ちず',
    'word:じんじゃ',
    'word:でんしゃ',
    'word:かいさつ',
    'word:のりかえ',
  ];

  /// Existing corpus items for [t01ProgressIds], in that order.
  static List<ReadingItem> pool([
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  ]) {
    final byId = <String, ReadingItem>{
      for (final item in words ?? kWords) item.progressId: item,
      for (final item in phrases ?? kPhrases) item.progressId: item,
    };
    return [
      for (final id in t01ProgressIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// True when at least one T01 item is both readable and already met.
  static bool hasReadyItems({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    return ReadingSet.readable(
      pool(words, phrases),
      learnedChars,
    ).any((item) => stats[item.progressId]?.isSeen ?? false);
  }

  /// Reviews only. Never boards an unseen item — 渡し舟 / 黙読 remain the
  /// meeting rooms.
  static List<ReadingItem> compose({
    required Set<String> learnedChars,
    required Random rng,
    required DateTime now,
    Map<String, WordStat> stats = const {},
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
    int sessionLength = length,
  }) {
    return ReadingSet.session(
      items: pool(words, phrases),
      learnedChars: learnedChars,
      rng: rng,
      now: now,
      stats: stats,
      length: sessionLength,
      maxNew: 0,
    );
  }
}
