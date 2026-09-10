// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// Two-column option tiles that grow with the system text scale.
///
/// A [GridView] plus a fixed [childAspectRatio] sizes each cell from width
/// alone. Kana [Text] follows [TextScaler], so large type is clipped even
/// when the page itself scrolls. This layout keeps the two-column rhythm
/// and sizes every row to the tallest unclipped tile.
class AnswerOptionGrid extends StatelessWidget {
  const AnswerOptionGrid({
    required this.children,
    super.key,
    this.spacing = 12,
    this.crossAxisCount = 2,
  });

  final List<Widget> children;
  final double spacing;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += crossAxisCount) {
      final end = i + crossAxisCount > children.length
          ? children.length
          : i + crossAxisCount;
      final slice = children.sublist(i, end);
      if (rows.isNotEmpty) {
        rows.add(SizedBox(height: spacing));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < crossAxisCount; j++) ...[
                if (j > 0) SizedBox(width: spacing),
                Expanded(
                  child: j < slice.length ? slice[j] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}
