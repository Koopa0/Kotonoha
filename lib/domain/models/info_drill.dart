// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Which travel information field a drill asks the learner to extract.
enum InfoKind { amount, time, personCount }

/// One exchange: hear a travel announcement, pick the heard amount, time, or
/// headcount. Not a [ReadingItem] and not a travel-scene member.
///
/// Pure data: no `package:flutter/*` imports.
class InfoDrill {
  const InfoDrill({
    required this.id,
    required this.kind,
    required this.sceneZh,
    required this.promptKana,
    required this.promptRomaji,
    required this.promptMeaning,
    required this.correctAnswer,
    required this.wrongAnswers,
    required this.requiredSeenIds,
    this.assembledFromParts = false,
  });

  /// Stable analytics id (`info:…`). Never a corpus progress id.
  final String id;

  final InfoKind kind;

  /// Background facts for the travel moment. Traditional Chinese only — never
  /// the heard Japanese, romaji, gloss, or the answer label before submit.
  final String sceneZh;

  /// Heard utterance, layout-spaced like [Phrase.kana].
  final String promptKana;
  final String promptRomaji;

  /// Traditional Chinese gloss of the heard line — hint only, never autoplay text.
  final String promptMeaning;

  /// Objective answer label shown after submit. Value and unit together.
  final String correctAnswer;

  /// Same-[kind] distractors only; never another field's unit.
  final List<String> wrongAnswers;

  /// Corpus progress ids that must already have been met before a scored turn.
  final List<String> requiredSeenIds;

  /// Heard value is built from already-met parts or a taught irregular.
  /// The complete number+unit string is not itself a corpus word, so the
  /// meet step never shows that exact answer before the scored turn.
  final bool assembledFromParts;

  String get say => promptKana.replaceAll(' ', '');

  List<String> get gatingText => [promptKana];

  List<String> get answerChoices => [correctAnswer, ...wrongAnswers];
}
