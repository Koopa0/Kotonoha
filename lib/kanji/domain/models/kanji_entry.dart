// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// 音読み (on — Sino-Japanese, partially pre-installed for a Chinese L1) vs
/// 訓読み (kun — native Japanese). The on/kun split is itself a teaching cue.
enum ReadingKind { on, kun }

/// One readable pronunciation of a kanji. [text] is the kana surface that's
/// recalled and graded ('ジン' / 'ひと'); [exampleWord]/[exampleMeaning] are
/// display-only context shown on reveal.
///
/// Pure data: no `package:flutter/*` imports.
class Reading {
  const Reading({
    required this.text,
    required this.kind,
    this.exampleWord,
    this.exampleMeaning,
  });

  factory Reading.fromJson(Map<String, Object?> m) => Reading(
    text: m['t']! as String,
    kind: ReadingKind.values.byName(m['k'] as String? ?? 'on'),
    exampleWord: m['w'] as String?,
    exampleMeaning: m['m'] as String?,
  );

  final String text;
  final ReadingKind kind;
  final String? exampleWord; // illustrative kana word, never graded
  final String? exampleMeaning; // L1 gloss, display only

  Map<String, Object?> toJson() => <String, Object?>{
    't': text,
    'k': kind.name,
    if (exampleWord != null) 'w': exampleWord,
    if (exampleMeaning != null) 'm': exampleMeaning,
  };
}

/// A kanji whose MEANING the learner already knows (via Chinese); the learnable
/// gap is the Japanese reading(s). Identity is [char].
///
/// Pure data: no `package:flutter/*` imports.
class KanjiEntry {
  const KanjiEntry({
    required this.char,
    required this.meaningZh,
    required this.readings,
  });

  final String char;
  final String meaningZh; // display only, never graded
  final List<Reading> readings;

  String get id => char;

  /// Per-reading stable id — the unit of scheduling AND analytics, because the
  /// learner can know one reading of a kanji cold and miss another.
  static String readingId(String char, String readingText) =>
      'reading:$char#$readingText';

  Iterable<String> get readingIds =>
      readings.map((r) => readingId(char, r.text));
}
