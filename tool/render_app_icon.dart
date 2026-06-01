// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Renders the 言の葉 launcher-icon source art with the app's OWN canvas and
// palette tokens — a single celadon leaf (the "leaf of words"), a soft brush
// midrib, and one caught glint of komorebi light, on cool washi.
//
// Not part of the test gate (it lives under tool/, not test/). Run on demand:
//   flutter test tool/render_app_icon.dart
// then regenerate the platform icons:
//   dart run flutter_launcher_icons
//
// Writes two 1024² sources:
//   assets/icon/app_icon.png            washi ground + leaf (iOS / legacy)
//   assets/icon/app_icon_foreground.png transparent + smaller leaf (adaptive)

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

class _LeafIcon extends CustomPainter {
  const _LeafIcon({required this.withBackground, required this.leafFactor});

  /// Paint the washi ground (full icon) vs. leave it transparent (adaptive fg).
  final bool withBackground;

  /// Leaf half-length as a fraction of the canvas — smaller for the adaptive
  /// foreground so it sits inside the safe zone.
  final double leafFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    if (withBackground) {
      canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.paper);
      // A faint warmth in the upper corner — light falling onto the page.
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(Offset(s * 0.72, s * 0.26), s * 0.62, [
            AppColors.komorebi.withValues(alpha: 0.10),
            AppColors.komorebi.withValues(alpha: 0),
          ]),
      );
    }

    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(-14 * math.pi / 180);

    final h = s * leafFactor; // half-length
    final w = h * 0.46; // half-width — a slender, calm leaf

    // Leaf body — two symmetric cubics, pointed at tip and base.
    final leaf = Path()
      ..moveTo(0, h)
      ..cubicTo(-w * 1.35, h * 0.40, -w * 1.35, -h * 0.42, 0, -h)
      ..cubicTo(w * 1.35, -h * 0.42, w * 1.35, h * 0.40, 0, h)
      ..close();
    canvas.drawPath(
      leaf,
      Paint()
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(Offset(0, -h), Offset(0, h), [
          Color.lerp(AppColors.accent, AppColors.washiFleck, 0.10)!,
          Color.lerp(AppColors.accent, AppColors.ink, 0.24)!,
        ]),
    );

    // Midrib — a soft, slightly leaning brush vein in the paper tone.
    final midrib = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.12, 0, 0, -h * 0.88);
    canvas.drawPath(
      midrib,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.013
        ..color = AppColors.paper.withValues(alpha: 0.88),
    );

    // Two faint pairs of side veins.
    final sideVein = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.0065
      ..color = AppColors.paper.withValues(alpha: 0.5);
    for (final t in [0.34, 0.02]) {
      final y = h * t;
      canvas
        ..drawPath(
          Path()
            ..moveTo(0, y)
            ..quadraticBezierTo(
              -w * 0.45,
              y - h * 0.12,
              -w * 0.80,
              y - h * 0.22,
            ),
          sideVein,
        )
        ..drawPath(
          Path()
            ..moveTo(0, y)
            ..quadraticBezierTo(w * 0.45, y - h * 0.12, w * 0.80, y - h * 0.22),
          sideVein,
        );
    }

    // Komorebi — one caught glint of warm light on the leaf.
    final glint = Offset(w * 0.42, -h * 0.34);
    canvas
      ..drawCircle(
        glint,
        s * 0.050,
        Paint()
          ..color = AppColors.komorebi.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      )
      ..drawCircle(
        glint,
        s * 0.018,
        Paint()
          ..color = Color.lerp(AppColors.komorebi, AppColors.washiFleck, 0.30)!,
      );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> _render(
  WidgetTester tester, {
  required bool background,
  required double leafFactor,
  required String path,
}) async {
  const dim = 1024.0;
  tester.view.physicalSize = const Size(dim, dim);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: CustomPaint(
        size: const Size(dim, dim),
        painter: _LeafIcon(withBackground: background, leafFactor: leafFactor),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('render the full icon (washi ground + leaf)', (tester) async {
    await _render(
      tester,
      background: true,
      leafFactor: 0.32,
      path: 'assets/icon/app_icon.png',
    );
  });

  testWidgets('render the adaptive foreground (transparent + leaf)', (
    tester,
  ) async {
    await _render(
      tester,
      // Larger than the full-icon leaf: the adaptive pipeline adds a 16% inset
      // and the launcher mask crops further, so oversize to land well-filled.
      background: false,
      leafFactor: 0.34,
      path: 'assets/icon/app_icon_foreground.png',
    );
  });
}
