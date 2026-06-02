// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:provider/provider.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ProgressScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.progress)),
      body: SafeArea(
        child: Consumer<KanaProgressRepository>(
          builder: (context, store, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: ProgressRing(
                    value: store.overallAccuracy,
                    centerLabel: '${(store.overallAccuracy * 100).round()}%',
                    caption: AppStrings.accuracy,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    AppStrings.practicedOfTotal(
                      store.seenCount,
                      store.totalCount,
                    ),
                    style: const TextStyle(color: AppColors.inkMuted),
                  ),
                ),
                const SizedBox(height: 28),
                _StatusBreakdown(store: store),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.store});

  final KanaProgressRepository store;

  @override
  Widget build(BuildContext context) {
    const items = [
      (KanaStatus.strong, AppStrings.statusStrong),
      (KanaStatus.learning, AppStrings.statusLearning),
      (KanaStatus.weak, AppStrings.statusWeak),
      (KanaStatus.unseen, AppStrings.statusNew),
    ];
    return Column(
      children: [
        for (final (status, label) in items) ...[
          _StatusRow(
            label: label,
            count: store.countWithStatus(status),
            total: store.totalCount,
            color: AppColors.forStatus(status),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
