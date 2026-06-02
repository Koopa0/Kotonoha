// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// The closed set of grammar particles a 漢字-literate reader skims past, with a
/// one-line role/reading gloss each — exposure, NOT a grammar lesson (deliberately
/// no は/が topic-vs-subject contrast; the role label is the ceiling).
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class Particles {
  /// The post-nominal / genitive particles we gloss.
  static const Set<String> known = {'は', 'が', 'を', 'に', 'の', 'へ'};

  /// The distinct particles in a space-separated [kana] phrase, in reading order.
  ///
  /// A particle is the TRAILING kana of a NON-FINAL word-token — Japanese attaches
  /// particles to the preceding word (そらが = そら+が), and the final token is the
  /// predicate (no particle). A single-token word (no spaces) has no non-final
  /// tokens, so this returns [] — safe to call on any reading item; only
  /// multi-word phrases yield particles. (Verified zero false-positives across the
  /// phrase corpus; new phrases must keep particles as the trailing kana of a
  /// non-final token, which is natural Japanese spacing.)
  static List<String> particlesIn(String kana) {
    final tokens = kana.split(' ').where((t) => t.isNotEmpty).toList();
    final out = <String>[];
    for (var i = 0; i < tokens.length - 1; i++) {
      final last = String.fromCharCode(tokens[i].runes.last);
      if (known.contains(last) && !out.contains(last)) out.add(last);
    }
    return out;
  }
}
