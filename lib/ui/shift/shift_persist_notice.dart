// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// Honest unsaved state for shift hold / exposure / history. Retry only
/// flushes the existing analytics buffer — it does not replay a sitting.
class ShiftPersistNotice extends StatelessWidget {
  const ShiftPersistNotice({
    required this.onRetry,
    this.retrying = false,
    super.key,
  });

  final VoidCallback? onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.persistFailedLine,
                  style: TextStyle(color: AppColors.ink, height: 1.4),
                ),
                const SizedBox(height: 4),
                const Text(
                  AppStrings.shiftPersistFailed,
                  style: TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: retrying ? null : onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      disabledForegroundColor: AppColors.inkMuted,
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(
                      retrying
                          ? AppStrings.persistRetrying
                          : AppStrings.persistRetry,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
