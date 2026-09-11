// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Which travel slice a reply room draws from. Isolated from [TravelSceneId]
/// membership — only scopes [ReplyDrill] pools and hub copy.
enum ReplySceneId { station, clothing, restaurant, convenience }

/// One exchange: hear the other person, name their intent, pick a short reply.
/// Not a [ReadingItem] and not a 黙読 / travel-scene member.
///
/// Pure data: no `package:flutter/*` imports.
class ReplyDrill {
  const ReplyDrill({
    required this.id,
    required this.scene,
    required this.sceneZh,
    required this.promptKana,
    required this.promptRomaji,
    required this.promptMeaning,
    required this.intentCorrect,
    required this.intentWrong,
    required this.replyCorrectKana,
    required this.replyCorrectRomaji,
    required this.replyCorrectMeaning,
    this.replyAlsoCorrectKana = const [],
    required this.replyWrongKana,
    required this.requiredSeenIds,
  });

  /// Stable analytics id (`reply:…`). Never a corpus progress id.
  final String id;

  final ReplySceneId scene;

  /// Background facts that make one reply uniquely right. Traditional
  /// Chinese only — never the heard Japanese, romaji, gloss, or a
  /// translation of the asker's intent.
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

  /// Other short replies that fit the same scene — scored like [replyCorrectKana].
  final List<String> replyAlsoCorrectKana;
  final List<String> replyWrongKana;

  /// Existing corpus progress ids that must already have been met.
  /// Includes the heard ask, any shipped content word the reply depends on,
  /// and a shipped request-function chunk when the correct reply uses
  /// ください／おねがい — reuse an already-taught equivalent, never the
  /// scored answer itself (`phrase:${replyCorrectKana}`).
  final List<String> requiredSeenIds;

  String get say => promptKana.replaceAll(' ', '');

  List<String> get gatingText => [
    promptKana,
    replyCorrectKana,
    ...replyAlsoCorrectKana,
    ...replyWrongKana,
  ];

  List<String> get intentChoices => [intentCorrect, ...intentWrong];

  List<String> get replyChoices => [
    replyCorrectKana,
    ...replyAlsoCorrectKana,
    ...replyWrongKana,
  ];

  bool isReplyCorrect(String choice) =>
      choice == replyCorrectKana || replyAlsoCorrectKana.contains(choice);
}
