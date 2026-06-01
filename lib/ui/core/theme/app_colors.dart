// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// The single source of truth for color in Kotonoha. Widgets read from here
/// (or from the [ThemeData] built in `app_theme.dart`) — never hardcode hex.
///
/// Mood: 言の葉 — rain-washed green on cool washi paper. The calm, wet-leaf
/// palette of *The Garden of Words*: celadon green, pine ink, soft mist.
abstract final class AppColors {
  // Brand — celadon / 青磁, like a leaf after rain.
  static const Color accent = Color(0xFF5E9387); // primary
  static const Color accentSoft = Color(0xFFE2EDEA); // soft fills

  /// Warm light through leaves (木漏れ日) — the ONLY "reward" colour. Reserved
  /// for light moments (the wordmark underline, a session's closing glow), never
  /// for status or chrome.
  static const Color komorebi = Color(0xFFD8B36A);

  // Neutrals
  static const Color paper = Color(0xFFF2F5F3); // cool washi (bg)
  static const Color card = Color(0xFFFBFDFC); // near-white surface
  static const Color ink = Color(0xFF2A332E); // deep pine text
  static const Color inkMuted = Color(0xFF66726B); // misty green-gray
  static const Color hairline = Color(0xFFDCE6E0); // subtle borders/dividers

  // Semantic
  static const Color success = Color(0xFF5E9E7E); // soft green
  static const Color successSoft = Color(0xFFE3EFE8);
  static const Color error = Color(0xFFD98A7C); // soft clay (missed)
  static const Color errorSoft = Color(0xFFF6E7E1);
  static const Color warning = Color(0xFFC2923F); // warm amber (weak kana)
  static const Color warningSoft = Color(0xFFF1E7D3);

  /// The accent color for a kana's learning status (the status dot).
  static Color forStatus(KanaStatus status) => switch (status) {
    KanaStatus.unseen => hairline,
    KanaStatus.learning => accent,
    KanaStatus.weak => warning,
    KanaStatus.strong => success,
  };
}
