// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';

void main() {
  final allChars = {for (final kana in kAllKana) kana.character};

  WordStat seenAt() => WordStat.fromJson({'s': 1, 'c': 0, 'w': 0});

  test('clothing intro batches fourteen words as eight then six, then eight phrases', () {
    final words = ReplySession.unreadRequiredWords(
      learnedChars: allChars,
      stats: const {},
      scene: ReplySceneId.clothing,
    );
    expect(words, hasLength(14));
    expect(words.map((w) => w.progressId), isNot(contains('word:えき')));

    final first = ReplySession.composeIntroWords(
      learnedChars: allChars,
      stats: const {},
      scene: ReplySceneId.clothing,
    );
    expect(first, hasLength(8));
    expect(first, words.take(8));

    final afterFirst = {for (final word in first) word.progressId: seenAt()};
    final second = ReplySession.composeIntroWords(
      learnedChars: allChars,
      stats: afterFirst,
      scene: ReplySceneId.clothing,
    );
    expect(second, hasLength(6));
    expect(
      second
          .map((w) => w.progressId)
          .toSet()
          .intersection(first.map((w) => w.progressId).toSet()),
      isEmpty,
    );

    final afterWords = {for (final word in words) word.progressId: seenAt()};
    expect(
      ReplySession.composeIntroWords(
        learnedChars: allChars,
        stats: afterWords,
        scene: ReplySceneId.clothing,
      ),
      isEmpty,
    );
    final phrases = ReplySession.unreadRequiredPhrases(
      learnedChars: allChars,
      stats: afterWords,
      scene: ReplySceneId.clothing,
    );
    expect(phrases, hasLength(8));
    expect(
      ReplySession.composeIntroPhrases(
        learnedChars: allChars,
        stats: afterWords,
        scene: ReplySceneId.clothing,
      ),
      phrases,
    );
    expect(phrases.map((p) => p.progressId), isNot(contains('phrase:えきは どこ')));
    final mid = ReplySession.inspect(
      learnedChars: allChars,
      stats: afterWords,
      scene: ReplySceneId.clothing,
    );
    expect(mid.canMeet, isTrue);
  });
}
