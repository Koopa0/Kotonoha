// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

void main() {
  group('Reading / KanjiEntry', () {
    test('Reading JSON round-trips and omits null example fields', () {
      const full = Reading(
        text: 'ジン',
        kind: ReadingKind.on,
        exampleWord: 'がいこくじん',
        exampleMeaning: '外國人',
      );
      final back = Reading.fromJson(full.toJson());
      expect(back.text, 'ジン');
      expect(back.kind, ReadingKind.on);
      expect(back.exampleWord, 'がいこくじん');

      const bare = Reading(text: 'ひと', kind: ReadingKind.kun);
      final json = bare.toJson();
      expect(json.containsKey('w'), isFalse);
      expect(json.containsKey('m'), isFalse);
      expect(Reading.fromJson(json).kind, ReadingKind.kun);
    });

    test('readingId is the stable per-reading key', () {
      expect(KanjiEntry.readingId('人', 'ジン'), 'reading:人#ジン');
      const e = KanjiEntry(
        char: '人',
        meaningZh: '人',
        readings: [
          Reading(text: 'ひと', kind: ReadingKind.kun),
          Reading(text: 'ジン', kind: ReadingKind.on),
        ],
      );
      expect(e.readingIds, ['reading:人#ひと', 'reading:人#ジン']);
    });
  });

  group('ReadingStat (RT-gated Leitner copy)', () {
    final at = DateTime(2026, 6);

    test('JSON round-trips with default omission', () {
      const s = ReadingStat(seenCount: 2, correctCount: 1, wrongCount: 1);
      final back = ReadingStat.fromJson(s.toJson());
      expect(back.seenCount, 2);
      expect(back.accuracy, closeTo(0.5, 1e-9));
      expect(s.toJson().containsKey('sl'), isFalse); // level 0 omitted
    });

    test('untimed correct climbs to the cap then holds; wrong resets', () {
      var s = const ReadingStat();
      for (var i = 0; i < 10; i++) {
        s = s.recordAnswer(correct: true, at: at.add(Duration(days: i)));
      }
      expect(s.srsLevel, ReadingStat.kUntimedCapLevel);
      s = s.recordAnswer(correct: false, at: at);
      expect(s.srsLevel, 0);
      expect(s.dueAt!.isAfter(at), isTrue);
    });
  });
}
