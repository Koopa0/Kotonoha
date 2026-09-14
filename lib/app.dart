// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_theme.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:kotonoha/ui/core/widgets/washi_background.dart';
import 'package:kotonoha/ui/home/home_screen.dart';

class KanaLoopApp extends StatelessWidget {
  const KanaLoopApp({super.key});

  // Traditional Chinese (Taiwan). The interface is single-language by design.
  static const Locale _locale = Locale('zh', 'TW');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Every screen sits on the washi paper (scaffolds are transparent in the
      // theme, so this single backdrop shows through under all of them). The
      // persistence banner sits above the navigator, so the one calm progress-
      // save notice survives route changes.
      // The root system-bar style, above the navigator: a route with an
      // AppBar annotates its own (the same one), and popping back to a page
      // without one — the home — falls back here instead of keeping the
      // previous route's icons.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemOverlay,
        child: WashiBackground(
          child: PersistenceBanner(child: child ?? const SizedBox.shrink()),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
