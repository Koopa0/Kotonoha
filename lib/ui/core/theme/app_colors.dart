// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// The single source of truth for color in Kotonoha. Widgets read from here
/// (or from the [ThemeData] built in `app_theme.dart`) — never hardcode hex.
///
/// Mood: calm, Japanese-notebook. Soft sky blue on blue-tinted white.
abstract final class AppColors {
  // Brand
  static const Color skyBlue = Color(0xFF5B8DEF); // primary
  static const Color skyBlueSoft = Color(0xFFD9E6FF); // primary container

  // Neutrals
  static const Color paper = Color(0xFFF4F8FF); // blue-tinted white (bg)
  static const Color card = Color(0xFFFFFFFF); // surface
  static const Color ink = Color(0xFF1F2A44); // deep navy text
  static const Color inkMuted = Color(0xFF5A6786); // blue-gray secondary text
  static const Color hairline = Color(0xFFE3EAF6); // subtle borders/dividers

  // Semantic
  static const Color success = Color(0xFF5FB58A); // soft green
  static const Color successSoft = Color(0xFFE2F2EA);
  static const Color error = Color(0xFFE58A7D); // soft coral
  static const Color errorSoft = Color(0xFFFBE7E3);
  static const Color warning = Color(0xFFE5B45F); // soft amber (weak kana)
  static const Color warningSoft = Color(0xFFFAF0DC);

  /// The accent color for a kana's learning status (the status dot).
  static Color forStatus(KanaStatus status) => switch (status) {
    KanaStatus.unseen => hairline,
    KanaStatus.learning => skyBlue,
    KanaStatus.weak => warning,
    KanaStatus.strong => success,
  };
}
