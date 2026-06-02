// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// A practice track that opens once the learner knows enough kana to use it.
///
/// Declaration order is the learning arc, which is also the display precedence
/// (oldest-first). Each value's [id] is its stable token, persisted as a "seen
/// unlock" — so renaming or reordering must keep these strings intact.
enum Unlock {
  words,
  phrases,
  kanjiPhrases;

  String get id => switch (this) {
    Unlock.words => 'words',
    Unlock.phrases => 'phrases',
    Unlock.kanjiPhrases => 'kanjiPhrases',
  };
}

/// Decides whether a track has *just* opened and deserves one quiet line.
///
/// Pure logic: it takes the gate booleans the View already computes plus the
/// set of unlocks the learner has seen — no Flutter, no repository, no clock.
abstract final class Unlocks {
  /// The first unlock, in arc order, whose gate is open and which the learner
  /// has not yet seen — or null when there is nothing new to announce.
  ///
  /// Returns at most one, so the home shows a single calm line and a backlog
  /// drains oldest-first, one acknowledgement at a time.
  static Unlock? pending({
    required bool wordsReadable,
    required bool phrasesReadable,
    required bool kanjiPhrasesReadable,
    required Set<String> seenUnlocks,
  }) {
    for (final unlock in Unlock.values) {
      final isOpen = switch (unlock) {
        Unlock.words => wordsReadable,
        Unlock.phrases => phrasesReadable,
        Unlock.kanjiPhrases => kanjiPhrasesReadable,
      };
      if (isOpen && !seenUnlocks.contains(unlock.id)) return unlock;
    }
    return null;
  }
}
