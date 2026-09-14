// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';

/// Owns the 短く返す door for one scene: what the learner can enter
/// (kana first, meet the words, practice), and how each session behind
/// a door is composed from the learned kana and the 詞と句 schedule. The
/// screen renders the doors and navigates.
///
/// Re-notifies on any change to the kana or word owner, so the doors stay
/// live while a session behind them writes. Pure of widgets and navigation.
class ReplyHubViewModel extends ChangeNotifier {
  ReplyHubViewModel({
    required this.scene,
    required this.kana,
    required this.words,
    Random? rng,
  }) : _rng = rng ?? Random() {
    kana.addListener(notifyListeners);
    words.addListener(notifyListeners);
  }

  final ReplySceneId scene;

  /// Owner of the learned kana — the readable scope.
  final KanaProgressRepository kana;

  /// Owner of the 詞と句 schedule — which drills have been met.
  final WordProgressRepository words;

  final Random _rng;

  Set<String> get _learnedChars =>
      StudySet.learned(kana).map((k) => k.character).toSet();

  /// Which doors are open right now.
  ReplySessionView get view => ReplySession.inspect(
    scene: scene,
    learnedChars: _learnedChars,
    stats: words.stats,
  );

  /// The words to meet first (渡し舟), empty when none are left.
  List<Word> composeIntroWords() => ReplySession.composeIntroWords(
    scene: scene,
    learnedChars: _learnedChars,
    stats: words.stats,
  );

  /// The phrases to meet once every word is met (黙読), empty when done.
  List<ReadingItem> composeIntroPhrases() => ReplySession.composeIntroPhrases(
    scene: scene,
    learnedChars: _learnedChars,
    stats: words.stats,
  );

  /// Something required is still unmet — 「もう一回」 keeps meeting.
  bool get hasUnreadRequired => ReplySession.unreadRequired(
    scene: scene,
    learnedChars: _learnedChars,
    stats: words.stats,
  ).isNotEmpty;

  /// A fresh practice session, empty when nothing is ready.
  List<ReplyDrill> composePractice() => ReplySession.compose(
    scene: scene,
    learnedChars: _learnedChars,
    rng: _rng,
    stats: words.stats,
  );

  @override
  void dispose() {
    kana.removeListener(notifyListeners);
    words.removeListener(notifyListeners);
    super.dispose();
  }
}
