// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:provider/provider.dart';

/// A small speaker button that reads [text] aloud via the [SpeechService].
/// Used on study cards, the dictionary detail sheet, and quiz prompts.
class SpeakButton extends StatelessWidget {
  const SpeakButton({required this.text, super.key, this.size = 26});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.volume_up_rounded, size: size),
      color: AppColors.skyBlue,
      tooltip: AppStrings.playSound,
      onPressed: () => context.read<SpeechService>().speak(text),
    );
  }
}
