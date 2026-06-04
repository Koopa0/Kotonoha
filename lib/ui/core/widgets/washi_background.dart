// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// A calm washi-paper backdrop: the warm paper tone plus a faint, seeded scatter
/// of short fibres — the single biggest "made by hand" signal, kept barely
/// perceptible. Painted once (deterministic seed, no repaint), so it costs
/// nothing per frame. Place it behind the app so every screen sits on paper.
class WashiBackground extends StatelessWidget {
  const WashiBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // isComplex (with the painter's shouldRepaint == false and willChange at
    // its default false): the grain is static, so the engine caches it as a
    // raster and skips re-drawing the fibres while a page animates over it.
    return CustomPaint(painter: _WashiPainter(), isComplex: true, child: child);
  }
}

class _WashiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.paper);

    // Deterministic so the grain never flickers between frames or routes.
    final rng = Random(7);
    final fibreCount = (size.width * size.height / 2400).round();
    final fibre = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.8;

    for (var i = 0; i < fibreCount; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final len = 5 + rng.nextDouble() * 13;
      final angle = rng.nextDouble() * pi;
      final end = Offset(x + cos(angle) * len, y + sin(angle) * len * 0.55);
      // Mostly pale flecks with a few darker fibres — like pulp in the sheet.
      final dark = rng.nextInt(3) == 0;
      fibre.color = (dark ? AppColors.ink : AppColors.washiFleck).withValues(
        alpha: dark ? 0.022 : 0.05,
      );
      canvas.drawLine(Offset(x, y), end, fibre);
    }
  }

  @override
  bool shouldRepaint(_WashiPainter oldDelegate) => false;
}
