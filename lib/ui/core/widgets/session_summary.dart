// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// The calm close of a practice session: a soft komorebi glow (light through
/// leaves), the score, and a quiet line — light as the only "reward", never a
/// "Great job!". Shared by the self-graded reading / writing / kanji screens.
class SessionSummary extends StatelessWidget {
  const SessionSummary({
    required this.headline,
    required this.onDone,
    super.key,
  });

  /// e.g. 「讀對 8 / 10」.
  final String headline;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A pool of warm light — komorebi.
            Container(
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
            const SizedBox(height: 4),
            Text(
              headline,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.sessionCloseLine,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
            ),
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
