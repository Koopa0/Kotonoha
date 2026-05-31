// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/models/attempt.dart';

void main() {
  group('Attempt schema v2', () {
    test('kana MC attempt round-trips with meta', () {
      const a = Attempt(
        ts: 1000,
        itemId: 'か',
        mode: 'quickReview',
        correct: false,
        rtMs: 1500,
        sessionId: 's1',
        meta: {
          AttemptMeta.direction: 'kanaToRomaji',
          AttemptMeta.distractor: 'yy',
        },
      );
      final back = Attempt.fromJson(a.toJson());
      expect(back.itemId, 'か');
      expect(back.itemType, ItemType.kana);
      expect(back.rtMs, 1500);
      expect(back.direction, 'kanaToRomaji');
      expect(back.distractor, 'yy');
    });

    test('defaults are omitted from json', () {
      const a = Attempt(
        ts: 1,
        itemId: 'あ',
        mode: 'writing',
        correct: true,
        sessionId: 's',
        meta: {AttemptMeta.direction: 'write'},
      );
      final json = a.toJson();
      expect(json.containsKey('rt'), isFalse); // rtMs 0 omitted
      expect(json.containsKey('type'), isFalse); // kana omitted
      expect((json['meta']! as Map).length, 1);
    });

    test('future kanji shape round-trips with open meta', () {
      const a = Attempt(
        ts: 7,
        itemId: '人',
        itemType: ItemType.kanji,
        mode: 'reading',
        correct: true,
        sessionId: 's',
        meta: {'reading': 'ジン'},
      );
      final back = Attempt.fromJson(a.toJson());
      expect(back.itemType, ItemType.kanji);
      expect(back.meta['reading'], 'ジン');
    });

    test('yōon 2-codepoint itemId survives', () {
      const a = Attempt(
        ts: 8,
        itemId: 'きゃ',
        mode: 'quickReview',
        correct: true,
        sessionId: 's',
      );
      expect(Attempt.fromJson(a.toJson()).itemId, 'きゃ');
    });
  });
}
