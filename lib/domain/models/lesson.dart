// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/kana.dart';

/// A sequential learning unit — one gojūon row (e.g. か行) studied as a group,
/// then tested as a group. Designed to generalise: katakana rows, dakuten
/// groups, or kanji sets can become Lessons later without changing the flow.
///
/// Pure data: no `package:flutter/*` imports.
class Lesson {
  const Lesson({required this.id, required this.title, required this.kana});

  /// Stable id used to persist "learned" state, e.g. `hira_row_1`.
  final String id;

  /// Display title, e.g. `か行` (kept in Japanese as it is content, like romaji).
  final String title;

  /// The kana taught/tested in this lesson, in order.
  final List<Kana> kana;

  /// A representative glyph for list display (the row's first kana).
  String get representative => kana.isEmpty ? '' : kana.first.character;

  /// The script this lesson belongs to (derived from its kana).
  KanaScript get script =>
      kana.isEmpty ? KanaScript.hiragana : kana.first.script;
}
