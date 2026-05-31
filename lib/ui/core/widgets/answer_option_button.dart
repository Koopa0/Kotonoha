// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// Visual state of an answer option once an answer has been committed.
enum OptionState {
  /// Not yet answered — tappable.
  idle,

  /// The option the user picked, and it was correct.
  correct,

  /// The option the user picked, and it was wrong.
  wrong,

  /// The correct answer, revealed after the user picked wrong.
  revealed,

  /// An untouched, now-disabled option after answering.
  dimmed,
}

/// A large, rounded multiple-choice option with a subtle settle animation on
/// feedback. No bounce, no confetti — just a calm color shift.
class AnswerOptionButton extends StatelessWidget {
  const AnswerOptionButton({
    required this.label,
    required this.state,
    required this.fontSize,
    super.key,
    this.onTap,
  });

  final String label;
  final OptionState state;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (state) {
      OptionState.idle => (AppColors.card, AppColors.hairline, AppColors.ink),
      OptionState.correct => (
        AppColors.successSoft,
        AppColors.success,
        AppColors.ink,
      ),
      OptionState.revealed => (
        AppColors.successSoft,
        AppColors.success,
        AppColors.ink,
      ),
      OptionState.wrong => (
        AppColors.errorSoft,
        AppColors.error,
        AppColors.ink,
      ),
      OptionState.dimmed => (
        AppColors.card,
        AppColors.hairline,
        AppColors.inkMuted,
      ),
    };

    return Semantics(
      button: state == OptionState.idle,
      label: label,
      child: AnimatedOpacity(
        opacity: state == OptionState.dimmed ? 0.5 : 1,
        duration: const Duration(milliseconds: 180),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border, width: 1.5),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
