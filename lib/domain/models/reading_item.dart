// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/season.dart';

/// Something the learner reads in the reading practice — a single [Word] or a
/// short [Phrase]. The reading screen needs only these surfaces, so words and
/// phrases share one screen without the screen knowing which it has.
///
/// Pure data: no `package:flutter/*` imports.
abstract interface class ReadingItem {
  /// The kana as displayed (phrases keep their layout spaces).
  String get displayText;

  /// Stable, namespaced progress identity (`word:いぬ` / `phrase:そらが あおい`)
  /// — the key `WordProgressRepository` schedules by. Namespacing keeps a word
  /// and a same-written phrase from ever sharing a stat; within a type the
  /// kana is unique (dataset-test-guarded).
  String get progressId;

  /// Canonical reading (romaji for a word; a spaced reading for a phrase).
  String get romaji;

  /// Meaning, in Traditional Chinese.
  String get meaning;

  /// The season this reading evokes, or null for a season-neutral one (always
  /// "in season"). Drives the silent seasonal-lift in sampling, never displayed.
  Season? get season;
}

/// Interest flavour for content, so practice can lean into what the learner
/// loves (ヨルシカ, anime, games, travel) without changing the mechanics.
enum ContentTheme { yorushika, anime, game, travel, daily, season }
