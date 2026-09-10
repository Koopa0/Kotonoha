// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:provider/provider.dart';

/// A speaker button that reads [text] aloud via the [SpeechService]. Two roles,
/// one widget: the default is a small "hear it again" affordance (study cards,
/// detail sheet, quiz prompts); [prominent] renders a filled accent circle for
/// the screens where the audio IS the prompt (渡し舟, 文字起こし).
class SpeakButton extends StatelessWidget {
  const SpeakButton({
    required this.text,
    super.key,
    this.size = 26,
    this.prominent = false,
    this.onPlay,
  });

  final String text;
  final double size;
  final bool prominent;

  /// When set, the button asks the screen to play. Dictation uses this so
  /// replay shares the same generation / item-id gate as autoplay.
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    void speak() {
      if (onPlay != null) {
        onPlay!();
        return;
      }
      context.read<SpeechService>().speak(text);
    }

    if (prominent) {
      return IconButton.filled(
        onPressed: speak,
        iconSize: size,
        tooltip: AppStrings.playSound,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.accentSoft,
          foregroundColor: AppColors.accent,
          padding: EdgeInsets.all(size * 0.4),
        ),
        icon: const Icon(Icons.volume_up_rounded),
      );
    }
    return IconButton(
      icon: Icon(Icons.volume_up_rounded, size: size),
      color: AppColors.accent,
      tooltip: AppStrings.playSound,
      onPressed: speak,
    );
  }
}
