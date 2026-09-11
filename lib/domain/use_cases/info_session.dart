// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';

/// Read-only gates for the travel info room. Inspecting writes nothing.
class InfoSessionView {
  const InfoSessionView({
    required this.all,
    required this.readable,
    required this.ready,
    required this.unreadRequired,
    required this.missingUnits,
  });

  final List<InfoDrill> all;
  final List<InfoDrill> readable;
  final List<InfoDrill> ready;
  final List<ReadingItem> unreadRequired;
  final List<String> missingUnits;

  bool get needsKanaFirst => readable.isEmpty;
  bool get canMeet => unreadRequired.isNotEmpty;
  bool get canPractice => ready.isNotEmpty;
}

/// Travel "hear a line → pick amount / time / headcount" composition.
///
/// Reuses shipped corpus ids for teach gates. Does not retune [ListeningSession]
/// or [TravelScene]. Pure logic: no Flutter imports.
abstract final class InfoSession {
  static const int length = 9;

  static List<InfoDrill> catalog({List<InfoDrill>? drills}) =>
      List<InfoDrill>.unmodifiable(drills ?? kInfoDrills);

  static InfoSessionView inspect({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<InfoDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    final all = catalog(drills: drills);
    final readable = [
      for (final drill in all)
        if (_isReadable(drill, learnedChars)) drill,
    ];
    final ready = [
      for (final drill in readable)
        if (_isMet(drill, stats)) drill,
    ];
    return InfoSessionView(
      all: all,
      readable: readable,
      ready: ready,
      unreadRequired: unreadRequired(
        learnedChars: learnedChars,
        stats: stats,
        drills: all,
        words: words,
        phrases: phrases,
      ),
      missingUnits: missingUnits(all, learnedChars),
    );
  }

  static bool _isReadable(InfoDrill drill, Set<String> learnedChars) =>
      drill.gatingText.every((t) => KanaTokenizer.isReadable(t, learnedChars));

  static bool _isMet(InfoDrill drill, Map<String, WordStat> stats) =>
      drill.gateIds.every((id) => stats[id]?.isSeen ?? false);

  static Iterable<String> _gateIdsFor(InfoDrill drill) sync* {
    yield* drill.requiredSeenIds;
    yield* drill.requiredPartIds;
  }

  static List<ReadingItem> unreadRequired({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<InfoDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) {
    final byId = _corpus(words: words, phrases: phrases);
    final seen = <String>{};
    final items = <ReadingItem>[];
    for (final drill in catalog(drills: drills)) {
      if (!_isReadable(drill, learnedChars)) continue;
      for (final id in _gateIdsFor(drill)) {
        if (stats[id]?.isSeen ?? false) continue;
        if (!seen.add(id)) continue;
        final item = byId[id];
        if (item == null) continue;
        if (!ReadingSet.readable([item], learnedChars).contains(item)) {
          continue;
        }
        items.add(item);
      }
    }
    return items;
  }

  static List<Word> unreadRequiredWords({
    required Set<String> learnedChars,
    required Map<String, WordStat> stats,
    List<InfoDrill>? drills,
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) => unreadRequired(
    learnedChars: learnedChars,
    stats: stats,
    drills: drills,
    words: words,
    phrases: phrases,
  ).whereType<Word>().toList();

  static List<String> missingUnits(
    Iterable<InfoDrill> drills,
    Set<String> learnedChars,
  ) {
    final missing = <String>[];
    for (final drill in drills) {
      for (final stretch in drill.gatingText) {
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

  /// Ready drills only. Prefer one base and one migration per [InfoKind].
  static List<InfoDrill> compose({
    required Set<String> learnedChars,
    required Random rng,
    Map<String, WordStat> stats = const {},
    List<InfoDrill>? drills,
    int sessionLength = length,
  }) {
    final ready = [
      for (final drill in catalog(drills: drills))
        if (_isReadable(drill, learnedChars) && _isMet(drill, stats)) drill,
    ];
    if (ready.isEmpty) return const [];
    final copy = List<InfoDrill>.of(ready)..shuffle(rng);
    if (copy.length <= sessionLength) return copy;
    final picked = <InfoDrill>[];
    for (final kind in InfoKind.values) {
      if (picked.length >= sessionLength) break;
      final base = copy.firstWhere(
        (d) => d.kind == kind && !d.isMigration,
        orElse: () => copy.firstWhere((d) => d.kind == kind),
      );
      picked.add(base);
    }
    for (final kind in InfoKind.values) {
      if (picked.length >= sessionLength) break;
      final migration = copy.where((d) => d.kind == kind && d.isMigration);
      for (final drill in migration) {
        if (picked.contains(drill)) continue;
        picked.add(drill);
        break;
      }
    }
    for (final drill in copy) {
      if (picked.length >= sessionLength) break;
      if (!picked.contains(drill)) picked.add(drill);
    }
    return picked;
  }

  static Map<String, ReadingItem> _corpus({
    List<ReadingItem>? words,
    List<ReadingItem>? phrases,
  }) => {
    for (final item in words ?? kWords) item.progressId: item,
    for (final item in phrases ?? kPhrases) item.progressId: item,
  };
}
