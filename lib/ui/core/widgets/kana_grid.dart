// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/widgets/kana_card.dart';

/// The gojūon grid: 11 consonant rows × 5 vowel columns, with blank cells where
/// the syllabary has gaps (や行, わ行). ん sits on its own final row.
class KanaGrid extends StatelessWidget {
  const KanaGrid({
    required this.kana,
    required this.statusOf,
    required this.onTapKana,
    super.key,
  });

  final List<Kana> kana;
  final KanaStatus Function(Kana) statusOf;
  final void Function(Kana) onTapKana;

  Kana? _at(int row, int column) {
    for (final k in kana) {
      if (k.row == row && k.column == column) return k;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell =
            (constraints.maxWidth - gap * (kGojuonColumnCount - 1)) /
            kGojuonColumnCount;
        return Column(
          children: [
            for (int row = 0; row < kGojuonRowCount; row++) ...[
              if (row > 0) const SizedBox(height: gap),
              Row(
                children: [
                  for (int col = 0; col < kGojuonColumnCount; col++) ...[
                    if (col > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: cell,
                      height: cell,
                      child: _buildCell(_at(row, col)),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCell(Kana? k) {
    if (k == null) return const SizedBox.shrink();
    return KanaCard(kana: k, status: statusOf(k), onTap: () => onTapKana(k));
  }
}
