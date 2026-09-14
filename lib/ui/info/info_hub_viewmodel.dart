// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/info_session.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';

/// Owns the 聞き取る数 door for one drill set: what the learner can enter
/// (kana first, meet the words, practice), and how each session behind
/// a door is composed from the learned kana and the 詞と句 schedule. The
/// screen renders the doors and navigates.
///
/// Re-notifies on any change to the kana or word owner, so the doors stay
/// live while a session behind them writes. Pure of widgets and navigation.
class InfoHubViewModel extends ChangeNotifier {
  InfoHubViewModel({
    required this.kana,
    required this.words,
    List<InfoDrill>? drills,
    Random? rng,
  }) : drills = drills ?? kInfoDrills,
       _rng = rng ?? Random() {
    kana.addListener(notifyListeners);
    words.addListener(notifyListeners);
  }

  /// The drill set behind this door (the shipped corpus by default).
  final List<InfoDrill> drills;

  /// Owner of the learned kana — the readable scope.
  final KanaProgressRepository kana;

  /// Owner of the 詞と句 schedule — which drills have been met.
  final WordProgressRepository words;

  final Random _rng;

  Set<String> get _learnedChars =>
      StudySet.learned(kana).map((k) => k.character).toSet();

  /// Which doors are open right now.
  InfoSessionView get view => InfoSession.inspect(
    learnedChars: _learnedChars,
    stats: words.stats,
    drills: drills,
  );

  /// The words to meet first (渡し舟), empty when none are left.
  List<Word> composeIntroWords() => InfoSession.composeIntroWords(
    learnedChars: _learnedChars,
    stats: words.stats,
    drills: drills,
  );

  /// The phrases to meet once every word is met (黙読), empty when done.
  List<ReadingItem> composeIntroPhrases() => InfoSession.composeIntroPhrases(
    learnedChars: _learnedChars,
    stats: words.stats,
    drills: drills,
  );

  /// Something required is still unmet — 「もう一回」 keeps meeting.
  bool get hasUnreadRequired => InfoSession.unreadRequired(
    learnedChars: _learnedChars,
    stats: words.stats,
    drills: drills,
  ).isNotEmpty;

  /// A fresh practice session, empty when nothing is ready.
  List<InfoDrill> composePractice() => InfoSession.compose(
    learnedChars: _learnedChars,
    rng: _rng,
    stats: words.stats,
    drills: drills,
  );

  @override
  void dispose() {
    kana.removeListener(notifyListeners);
    words.removeListener(notifyListeners);
    super.dispose();
  }
}
