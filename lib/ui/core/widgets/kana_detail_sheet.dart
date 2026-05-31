// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';

/// A calm bottom sheet showing a single kana large, with its romaji and the
/// user's practice record. Opened from the Learn grid.
class KanaDetailSheet extends StatelessWidget {
  const KanaDetailSheet({required this.kana, required this.stat, super.key});

  final Kana kana;
  final KanaStat stat;

  static Future<void> show(BuildContext context, Kana kana, KanaStat stat) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => KanaDetailSheet(kana: kana, stat: stat),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kana.character,
              style: const TextStyle(
                fontSize: 104,
                height: 1.0,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kana.romaji,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.skyBlue,
              ),
            ),
            const SizedBox(height: 8),
            SpeakButton(text: kana.character, size: 32),
            const SizedBox(height: 16),
            if (stat.isSeen)
              _StatsRow(stat: stat)
            else
              const Text(
                AppStrings.notPracticedYet,
                style: TextStyle(color: AppColors.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stat});

  final KanaStat stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Stat(label: AppStrings.statSeen, value: '${stat.seenCount}'),
        _Stat(
          label: AppStrings.statCorrect,
          value: '${stat.correctCount}',
          color: AppColors.success,
        ),
        _Stat(
          label: AppStrings.statMissed,
          value: '${stat.wrongCount}',
          color: stat.wrongCount > 0 ? AppColors.warning : AppColors.inkMuted,
        ),
        _Stat(
          label: AppStrings.statAccuracy,
          value: '${(stat.accuracy * 100).round()}%',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}
