// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// The bridge from a word or phrase's sound to everyday Japanese spelling.
/// Callers mount this only in the revealed answer, never in an audio prompt.
///
/// It shows nothing when there is nothing to bridge: many entries are written
/// exactly as they sound (パン, ください, きれい), and a sentence is already its
/// own spelling. Repeating the kana under a label would teach nothing and only
/// add a line to read.
class JapaneseWrittenForm extends StatelessWidget {
  const JapaneseWrittenForm({required this.item, super.key});

  final ReadingItem item;

  @override
  Widget build(BuildContext context) {
    final writtenForm = item.writtenForm;
    if (writtenForm == null || _bare(writtenForm) == _bare(item.displayText)) {
      return const SizedBox.shrink();
    }
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

  /// Spacing is layout, not spelling: a phrase's kana keeps reading spaces its
  /// written form does not, so the two are compared without any.
  static String _bare(String text) => text.replaceAll(RegExp(r'\s+'), '');
}
