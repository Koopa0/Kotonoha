// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/washi_background.dart';

/// Builds the calm, Material 3 light theme for Kotonoha.
abstract final class AppTheme {
  /// The system bars always sit on light washi paper, so their icons are
  /// dark. Stated once and applied in two places, because neither alone is
  /// enough: every AppBar is transparent, and Flutter guesses a *dark*
  /// background from a transparent colour and asks for light icons; and the
  /// home has no AppBar at all, so without a root annotation it would simply
  /// keep whatever the last route asked for.
  ///
  /// Status-bar fields only. The navigation bar and the edge-to-edge layout
  /// keep whatever the platform and the embedder already set.
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android reads the icon brightness; iOS reads the background brightness.
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent).copyWith(
      primary: AppColors.buttonFill,
      onPrimary: AppColors.onButton,
      primaryContainer: AppColors.accentSoft,
      onPrimaryContainer: AppColors.accent,
      surface: AppColors.card,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      error: AppColors.error,
      outlineVariant: AppColors.hairline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Transparent so the single washi backdrop (app.dart) shows under every
      // scaffold rather than being painted over with a flat colour.
      scaffoldBackgroundColor: Colors.transparent,
      // Klee One: a calm textbook-handwriting face — the kana look written, not set.
      fontFamily: 'KleeOne',
      // A soft ripple rather than the M3 sparkle — quieter, like ink spreading.
      splashFactory: InkRipple.splashFactory,
      // Android/macOS keep the ink fade-and-rise. iOS delegates to the official
      // Cupertino builder (edge-swipe back recognizer) while each route paints
      // its own opaque washi so transparent scaffolds do not ghost the page
      // beneath during the slide.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _InkPageTransitionsBuilder(),
          TargetPlatform.iOS: _CupertinoWashiPageTransitionsBuilder(),
          TargetPlatform.macOS: _InkPageTransitionsBuilder(),
        },
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: systemOverlay,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        // A soft, diffuse shadow for gentle depth — no M3 tonal tint.
        elevation: 3,
        shadowColor: AppColors.ink.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.buttonFill,
          foregroundColor: AppColors.onButton,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontFamily: 'KleeOne',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// Official Cupertino push/pop, including the iOS edge-swipe back gesture.
///
/// Delegates the transition and recognizer to [CupertinoPageTransitionsBuilder]
/// rather than reimplementing them. [WashiBackground] stays on the page so
/// transparent scaffolds do not ghost the route beneath during the slide.
class _CupertinoWashiPageTransitionsBuilder extends PageTransitionsBuilder {
  const _CupertinoWashiPageTransitionsBuilder();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _cupertino.transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _cupertino.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _cupertino.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      WashiBackground(child: child),
    );
  }
}

/// A calm page transition: the new page fades in while rising a touch, like ink
/// settling onto paper, while the page beneath eases gently upward as it
/// recedes — a soft parallax (no opacity flicker) that makes the change feel
/// layered rather than a flat platform slide. The reverse (pop) eases too.
class _InkPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InkPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Incoming page: fade + a small rise, smoothed in both directions so the
    // pop back out feels as calm as the push in.
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // The page below: drifts up a touch as it is covered (and back as it
    // returns) — depth without a cross-fade dip through the washi backdrop.
    final recede = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInOutCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(0, -0.02),
      ).animate(recede),
      // The page paints its OWN opaque washi, so the screen beneath is fully
      // occluded while pushing in: the incoming content settles onto paper
      // rather than ghosting over the previous screen (scaffolds are
      // transparent, so without this the fade would show the page below).
      child: WashiBackground(
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(enter),
            child: child,
          ),
        ),
      ),
    );
  }
}
