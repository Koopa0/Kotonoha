// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// 凪 — the calm close of a practice session. Not a results table: a komorebi
/// glow that gently settles in, one quiet [note] (a fact about today, never a
/// count), and only then — quietly — the score. Light as the only "reward".
/// Shared by every self-graded screen.
class SessionSummary extends StatelessWidget {
  const SessionSummary({
    required this.headline,
    required this.onDone,
    this.note,
    super.key,
  });

  /// e.g. 「讀對 8 / 10」.
  final String headline;

  /// A quiet fact about today (「今天,和『あき』更熟了一點。」). When present it
  /// leads, and the score recedes to a muted footnote — the breath-out.
  final String? note;

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final hasNote = note != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The light settles in — a slow breath out.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOut,
              builder: (context, v, child) => Opacity(opacity: v, child: child),
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.komorebi.withValues(alpha: 0.30),
                      AppColors.komorebi.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (hasNote)
              Text(
                note!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  color: AppColors.ink,
                ),
              ),
            const SizedBox(height: 12),
            // The score: prominent on its own, a quiet footnote under a note.
            Text(
              headline,
              style: TextStyle(
                fontSize: hasNote ? 14 : 22,
                fontWeight: hasNote ? FontWeight.w500 : FontWeight.w700,
                color: hasNote ? AppColors.inkMuted : AppColors.ink,
              ),
            ),
            if (!hasNote) ...[
              const SizedBox(height: 8),
              const Text(
                AppStrings.sessionCloseLine,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onDone,
                child: const Text(AppStrings.done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
