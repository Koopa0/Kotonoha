// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/data/phrases/travel_readings.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';

void main() {
  final now = DateTime(2026, 9, 22, 12);
  final allKana = {for (final k in kAllKana) k.character};
  const airportPhrase = 'この バスは くうこうに いきますか';

  test('missing travel readings each have at least two sentence contexts', () {
    const readings = {
      '空港': 'くうこう',
      '飛行機': 'ひこうき',
      '荷物': 'にもつ',
      '改札': 'かいさつ',
      '予約': 'よやく',
      '両替': 'りょうがえ',
      '換': 'か', // 乗り換え / 乗り換えます retain their okurigana.
      '土産': 'みやげ',
    };
    for (final entry in readings.entries) {
      final unit = kKanjiUnits.singleWhere(
        (u) => u.written == entry.key && u.reading == entry.value,
      );
      expect(
        KanjiUnits.examplesOf(unit, kKanjiPhrases).length,
        greaterThanOrEqualTo(2),
        reason: unit.id,
      );
    }
    expect(
      kKanjiPhrases.map((p) => p.progressId).toSet().length,
      kKanjiPhrases.length,
      reason: 'new contexts must not duplicate sentences',
    );
  });

  test(
    'linked kana utterances and kanji sentences agree in reading and meaning',
    () {
      for (final kana in [
        airportPhrase,
        'くうこうまで おねがいします',
        'ひこうきに のります',
        'りょうがえは どこで できますか',
        'かいさつは どこですか',
        'のりかえは どこですか',
        'えきは どこ',
        'カードは つかえません',
        'よやくが あります',
      ]) {
        final phrase = kPhrases.singleWhere((p) => p.kana == kana);
        final written = kTravelReadings.singleWhere(
          (p) => p.written == phrase.writtenForm,
        );
        expect(written.reading, phrase.kana.replaceAll(' ', ''));
        expect(written.romaji, phrase.romaji);
        expect(written.meaning, phrase.meaning);
        expect(written.progressId, isNot(phrase.progressId));
      }
    },
  );

  test(
    'airport words are learnable in transport, then reviewable only once met',
    () {
      const ids = {'word:くうこう', 'word:ひこうき', 'word:りょうがえ'};
      final stats = {
        for (final id in TravelScene.progressIds[TravelSceneId.transport]!)
          if (!ids.contains(id)) id: const WordStat(seenCount: 1),
      };
      final intro = TravelScene.composeIntroWords(
        scene: TravelSceneId.transport,
        learnedChars: allKana,
        rng: Random(1),
        now: now,
        stats: stats,
      );
      expect(intro.map((w) => w.progressId).toSet(), ids);
      final before = TravelScene.composeReview(
        scene: TravelSceneId.transport,
        learnedChars: allKana,
        rng: Random(2),
        now: now,
        stats: stats,
      );
      expect(
        before.map((i) => i.progressId).toSet().intersection(ids),
        isEmpty,
      );
      final met = {
        for (final id in ids) id: WordStat(seenCount: 1, dueAt: now),
      };
      final review = TravelScene.composeReview(
        scene: TravelSceneId.transport,
        learnedChars: allKana,
        rng: Random(3),
        now: now,
        stats: met,
      );
      expect(review.map((i) => i.progressId).toSet(), ids);
      expect(stats.keys.toSet().intersection(ids), isEmpty);
    },
  );

  test(
    'airport phrase enters intro and listening-review under its kana id',
    () {
      final item = kPhrases.singleWhere((p) => p.kana == airportPhrase);
      final stats = {
        for (final id in TravelScene.progressIds[TravelSceneId.transport]!)
          if (id != item.progressId) id: const WordStat(seenCount: 1),
      };
      final intro = TravelScene.composeIntroPhrases(
        scene: TravelSceneId.transport,
        learnedChars: allKana,
        rng: Random(4),
        now: now,
        stats: stats,
      );
      expect(intro.single.progressId, item.progressId);
      final review = TravelScene.composeReview(
        scene: TravelSceneId.transport,
        learnedChars: allKana,
        rng: Random(5),
        now: now,
        stats: {item.progressId: WordStat(seenCount: 1, dueAt: now)},
      );
      expect(review.single.progressId, 'phrase:$airportPhrase');
    },
  );

  test('kanji composer can introduce and later schedule the airport unit', () {
    final airport = kKanjiUnits.singleWhere((u) => u.id == 'unit:空港#くうこう');
    final otherSeen = {
      for (final u in kKanjiUnits)
        if (u.id != airport.id)
          u.id: ReadingStat(
            seenCount: 1,
            dueAt: now.add(const Duration(days: 7)),
          ),
    };
    final first = KanjiSession.compose(
      units: kKanjiUnits,
      stats: otherSeen,
      now: now,
      rng: Random(6),
      length: 1,
      maxNew: 1,
    );
    expect(first.single.id, airport.id);
    final learned = const ReadingStat().recordAnswer(correct: true, at: now);
    final review = KanjiSession.compose(
      units: kKanjiUnits,
      stats: {...otherSeen, airport.id: learned},
      now: learned.dueAt!,
      rng: Random(7),
      length: 1,
      maxNew: 0,
    );
    expect(review.single.id, airport.id);
  });
}
