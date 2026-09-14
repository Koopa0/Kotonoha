// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';

/// Owns one travel scene's door: what the learner can enter (kana first,
/// meet, recall, listen) and how each session behind a door is composed
/// from the learned kana, the 詞と句 schedule and the day. The screen
/// renders the doors and navigates; choosing the scene writes nothing.
///
/// Composition is read-only and never pads or re-introduces to climb
/// mastery: the caller passes the ids already covered in this 「もう一回」
/// grind ([excludeProgressIds]) and the composers leave them out.
///
/// Re-notifies on any change to the kana or word owner, so the doors stay
/// live while a session behind them writes. Pure of widgets and navigation.
class TravelSceneHubViewModel extends ChangeNotifier {
  TravelSceneHubViewModel({
    required this.scene,
    required this.kana,
    required this.words,
    DateTime Function()? clock,
    Random? rng,
  }) : _clock = clock ?? DateTime.now,
       _rng = rng ?? Random() {
    kana.addListener(notifyListeners);
    words.addListener(notifyListeners);
  }

  final TravelSceneId scene;

  /// Owner of the learned kana — the readable scope.
  final KanaProgressRepository kana;

  /// Owner of the 詞と句 schedule — what is met and what is due.
  final WordProgressRepository words;

  final DateTime Function() _clock;
  final Random _rng;

  Set<String> get _learnedChars =>
      StudySet.learned(kana).map((k) => k.character).toSet();

  /// Which doors are open right now.
  TravelSceneView get view => TravelScene.inspect(
    scene: scene,
    learnedChars: _learnedChars,
    stats: words.stats,
  );

  /// The words to meet first (渡し舟), empty when none are left.
  List<Word> composeIntroWords({Set<String> excludeProgressIds = const {}}) =>
      TravelScene.composeIntroWords(
        scene: scene,
        learnedChars: _learnedChars,
        rng: _rng,
        now: _clock(),
        stats: words.stats,
        excludeProgressIds: excludeProgressIds,
      );

  /// The phrases to meet once every word is met (黙読), empty when done.
  List<Phrase> composeIntroPhrases({
    Set<String> excludeProgressIds = const {},
  }) => TravelScene.composeIntroPhrases(
    scene: scene,
    learnedChars: _learnedChars,
    rng: _rng,
    now: _clock(),
    stats: words.stats,
    excludeProgressIds: excludeProgressIds,
  );

  /// Leftover unread scene items remain — 「もう一回」 keeps meeting.
  bool hasMoreIntro({Set<String> excludeProgressIds = const {}}) =>
      TravelScene.hasMoreIntro(
        scene: scene,
        learnedChars: _learnedChars,
        rng: _rng,
        now: _clock(),
        stats: words.stats,
        excludeProgressIds: excludeProgressIds,
      );

  /// A review session (黙読 or 聞き取り), empty when nothing is ready.
  List<ReadingItem> composeReview({
    Set<String> excludeProgressIds = const {},
  }) => TravelScene.composeReview(
    scene: scene,
    learnedChars: _learnedChars,
    rng: _rng,
    now: _clock(),
    stats: words.stats,
    excludeProgressIds: excludeProgressIds,
  );

  @override
  void dispose() {
    kana.removeListener(notifyListeners);
    words.removeListener(notifyListeners);
    super.dispose();
  }
}
