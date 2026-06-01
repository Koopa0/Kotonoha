// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_opener.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await bootstrap());
}

/// Builds the fully-wired app widget: load persisted progress, init TTS, and
/// open the analytics log. Shared by [main] and the integration test so the
/// end-to-end test exercises the real bootstrap (catching launch/init crashes).
Future<Widget> bootstrap() async {
  final store = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  final speech = await FlutterTtsSpeechService.create();
  final analytics = await openAnalyticsLog();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
      ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
      Provider<SpeechService>.value(value: speech),
      Provider<AnalyticsLog>.value(value: analytics),
    ],
    child: const KanaLoopApp(),
  );
}
