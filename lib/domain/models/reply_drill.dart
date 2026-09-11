// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// One station exchange: hear the other person, name their intent, pick a
/// short reply. Not a [ReadingItem] and not a 黙読 / travel-scene member.
///
/// Pure data: no `package:flutter/*` imports.
class ReplyDrill {
  const ReplyDrill({
    required this.id,
    required this.sceneZh,
    required this.promptKana,
    required this.promptRomaji,
    required this.promptMeaning,
    required this.intentCorrect,
    required this.intentWrong,
    required this.replyCorrectKana,
    required this.replyCorrectRomaji,
    required this.replyCorrectMeaning,
    required this.replyWrongKana,
    required this.requiredSeenIds,
  });

  /// Stable analytics id (`reply:…`). Never a corpus progress id.
  final String id;

  /// Situation that makes one reply uniquely right. Traditional Chinese
  /// only — never the heard Japanese, romaji, or gloss.
  final String sceneZh;

  /// The other person's utterance, layout-spaced like [Phrase.kana].
  final String promptKana;
  final String promptRomaji;

  /// Traditional Chinese gloss of the heard prompt.
  final String promptMeaning;

  /// Objective intent label in Traditional Chinese.
  final String intentCorrect;
  final List<String> intentWrong;

  final String replyCorrectKana;
  final String replyCorrectRomaji;
  final String replyCorrectMeaning;
  final List<String> replyWrongKana;

  /// Existing corpus progress ids that must already have been met.
  /// Includes the heard ask and any shipped content word whose meaning the
  /// correct short reply depends on — never a fabricated `phrase:みぎです`.
  final List<String> requiredSeenIds;

  String get say => promptKana.replaceAll(' ', '');

  List<String> get gatingText => [
    promptKana,
    replyCorrectKana,
    ...replyWrongKana,
  ];

  List<String> get intentChoices => [intentCorrect, ...intentWrong];

  List<String> get replyChoices => [replyCorrectKana, ...replyWrongKana];
}
