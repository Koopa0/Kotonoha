// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/kana_card.dart';
import 'package:kotonoha/ui/core/widgets/kana_detail_sheet.dart';
import 'package:kotonoha/ui/core/widgets/kana_grid.dart';
import 'package:provider/provider.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  KanaScript _script = KanaScript.hiragana;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.learnHiragana)),
      body: SafeArea(
        child: Consumer<KanaProgressRepository>(
          builder: (context, store, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Center(
                  child: SegmentedButton<KanaScript>(
                    segments: const [
                      ButtonSegment(
                        value: KanaScript.hiragana,
                        label: Text(AppStrings.hiraganaSection),
                      ),
                      ButtonSegment(
                        value: KanaScript.katakana,
                        label: Text(AppStrings.katakanaSection),
                      ),
                    ],
                    selected: {_script},
                    onSelectionChanged: (s) =>
                        setState(() => _script = s.first),
                  ),
                ),
                const SizedBox(height: 16),
                const _StatusLegend(),
                const SizedBox(height: 16),
                KanaGrid(
                  kana: store.gojuonForScript(_script),
                  statusOf: (k) => store.statFor(k).status,
                  onTapKana: (k) =>
                      KanaDetailSheet.show(context, k, store.statFor(k)),
                ),
                ..._extendedSection(context, store),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _extendedSection(
    BuildContext context,
    KanaProgressRepository store,
  ) {
    final ext = store.extendedForScript(_script);
    if (ext.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          AppStrings.extendedSection,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in ext)
            SizedBox(
              width: 72,
              height: 64,
              child: KanaCard(
                kana: k,
                status: store.statFor(k).status,
                onTap: () => KanaDetailSheet.show(context, k, store.statFor(k)),
              ),
            ),
        ],
      ),
    ];
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _LegendItem(status: KanaStatus.unseen, label: AppStrings.statusNew),
        _LegendItem(
          status: KanaStatus.learning,
          label: AppStrings.statusLearning,
        ),
        _LegendItem(status: KanaStatus.weak, label: AppStrings.statusWeak),
        _LegendItem(status: KanaStatus.strong, label: AppStrings.statusStrong),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.status, required this.label});

  final KanaStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: AppColors.forStatus(status),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}
