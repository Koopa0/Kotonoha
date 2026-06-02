// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';

void main() {
  test('nothing open → no line', () {
    expect(
      Unlocks.pending(
        wordsReadable: false,
        phrasesReadable: false,
        kanjiPhrasesReadable: false,
        seenUnlocks: const {},
      ),
      isNull,
    );
  });

  test('first content gate opens → words line', () {
    expect(
      Unlocks.pending(
        wordsReadable: true,
        phrasesReadable: false,
        kanjiPhrasesReadable: false,
        seenUnlocks: const {},
      ),
      Unlock.words,
    );
  });

  test('seen suppresses the line', () {
    expect(
      Unlocks.pending(
        wordsReadable: true,
        phrasesReadable: false,
        kanjiPhrasesReadable: false,
        seenUnlocks: const {'words'},
      ),
      isNull,
    );
  });

  test('simultaneous opens resolve oldest-first by arc order', () {
    expect(
      Unlocks.pending(
        wordsReadable: true,
        phrasesReadable: true,
        kanjiPhrasesReadable: false,
        seenUnlocks: const {},
      ),
      Unlock.words,
    );
  });

  test('queue advances: after words is seen, phrases surfaces', () {
    expect(
      Unlocks.pending(
        wordsReadable: true,
        phrasesReadable: true,
        kanjiPhrasesReadable: false,
        seenUnlocks: const {'words'},
      ),
      Unlock.phrases,
    );
  });

  test('drains to the last, then to null', () {
    expect(
      Unlocks.pending(
        wordsReadable: true,
        phrasesReadable: true,
        kanjiPhrasesReadable: true,
        seenUnlocks: const {'words', 'phrases'},
      ),
      Unlock.kanjiPhrases,
    );
    expect(
      Unlocks.pending(
        wordsReadable: true,
        phrasesReadable: true,
        kanjiPhrasesReadable: true,
        seenUnlocks: const {'words', 'phrases', 'kanjiPhrases'},
      ),
      isNull,
    );
  });

  test('a closed gate is never resurrected by a stale seen entry', () {
    expect(
      Unlocks.pending(
        wordsReadable: false,
        phrasesReadable: false,
        kanjiPhrasesReadable: false,
        seenUnlocks: const {'words'},
      ),
      isNull,
    );
  });

  test('ids are the stable persisted tokens', () {
    expect(Unlock.words.id, 'words');
    expect(Unlock.phrases.id, 'phrases');
    expect(Unlock.kanjiPhrases.id, 'kanjiPhrases');
    expect(Unlock.values.map((u) => u.id).toList(), [
      'words',
      'phrases',
      'kanjiPhrases',
    ]);
  });
}
