// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// The bridge from a word or phrase's sound to everyday Japanese spelling.
/// Callers mount this only in the revealed answer, never in an audio prompt.
class JapaneseWrittenForm extends StatelessWidget {
  const JapaneseWrittenForm({required this.text, super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final writtenForm = text;
    if (writtenForm == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            AppStrings.wordWrittenForm,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            writtenForm,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 30,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
