// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_opener.dart';
import 'package:kotonoha/data/services/file_picker_snapshot_port.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
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
  final words = await WordProgressRepository.load();
  final checks = await PlacementCheckRepository.load();
  final travel = await TravelFocusRepository.load();
  final speech = await FlutterTtsSpeechService.create();
  final analytics = await openAnalyticsLog();
  // The app-scoped owner of every progress-persistence future: it takes the
  // startup health of each store (to surface an honest recovery notice) and
  // flushes any repository on retry / lifecycle drain.
  final persistence = ProgressPersistenceController(
    kanaFlush: store.flushPending,
    kanjiFlush: kanji.flushPending,
    wordFlush: words.flushPending,
    placementFlush: checks.flushPending,
    travelFocusFlush: travel.flushPending,
    health: [
      store.statsHealth,
      store.learnedUnitsHealth,
      store.seenUnlocksHealth,
      kanji.statsHealth,
      words.statsHealth,
      checks.health,
      travel.health,
    ],
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
      ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
      ChangeNotifierProvider<WordProgressRepository>.value(value: words),
      ChangeNotifierProvider<PlacementCheckRepository>.value(value: checks),
      ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
      ChangeNotifierProvider<ProgressPersistenceController>.value(
        value: persistence,
      ),
      Provider<SpeechService>.value(value: speech),
      Provider<AnalyticsLog>.value(value: analytics),
      Provider<ProgressSnapshotExporter>.value(
        value: ProgressSnapshotExporter(
          snapshots: ProgressSnapshotRepository(
            kana: store,
            kanji: kanji,
            words: words,
          ),
          files: FilePickerSnapshotPort(),
        ),
      ),
    ],
    child: const KanaLoopApp(),
  );
}
