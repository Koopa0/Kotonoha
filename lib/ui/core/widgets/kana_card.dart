// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// A compact card showing a kana, its romaji, and a small learning-status dot.
/// Used in the gojūon grid; tapping calls [onTap].
class KanaCard extends StatelessWidget {
  const KanaCard({
    required this.kana,
    required this.status,
    super.key,
    this.onTap,
  });

  final Kana kana;
  final KanaStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Stack(
            children: [
              Positioned(top: 8, right: 8, child: _StatusDot(status: status)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kana.character,
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1.1,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      kana.romaji,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final KanaStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.forStatus(status),
        shape: BoxShape.circle,
      ),
    );
  }
}
