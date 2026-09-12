// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_restore_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_opener.dart';
import 'package:kotonoha/data/services/file_picker_snapshot_port.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/progress_snapshot_restorer.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await bootstrap());
}

/// Builds the fully-wired app widget: load persisted progress, init TTS, and
/// open the analytics log. Shared by [main] and the integration test so the
/// end-to-end test exercises the real bootstrap (catching launch/init crashes).
///
/// [prefs], [speech], and [analytics] are test seams only — production [main]
/// leaves them null.
Future<Widget> bootstrap({
  PreferencesService? prefs,
  SpeechService? speech,
  AnalyticsLog? analytics,
}) async {
  final resolvedPrefs = prefs ?? await PreferencesService.create();
  final journalRecovery = await ProgressRestoreJournal.recoverIfNeeded(
    resolvedPrefs,
  );
  final store = await KanaProgressRepository.load(resolvedPrefs);
  final kanji = await KanjiReadingRepository.load(resolvedPrefs);
  final words = await WordProgressRepository.load(resolvedPrefs);
  final restoreRecovery = ProgressRestoreRecoveryController(
    prefs: resolvedPrefs,
    kana: store,
    kanji: kanji,
    words: words,
    needsRecovery: journalRecovery.needsRecovery,
  );
  final checks = await PlacementCheckRepository.load(resolvedPrefs);
  final travel = await TravelFocusRepository.load(resolvedPrefs);
  final resolvedSpeech = speech ?? await FlutterTtsSpeechService.create();
  final resolvedAnalytics = analytics ?? await openAnalyticsLog();
  // The app-scoped owner of every progress-persistence future: it takes the
  // startup health of each store (to surface an honest recovery notice) and
  // flushes any repository on retry / lifecycle drain.
  final persistence = ProgressPersistenceController(
    kanaFlush: store.flushPending,
    kanjiFlush: kanji.flushPending,
    wordFlush: words.flushPending,
    placementFlush: checks.flushPending,
    analyticsFlush: resolvedAnalytics.flushPending,
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
  // Every production [recordObserved] write shares this owner. Shift
  // still tracks [AnalyticsLog.record] itself and must not also use
  // [recordObserved], or the same future would be notified twice.
  bindObservedWriteNotify(analytics, persistence.trackAnalytics);
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
      ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
        value: restoreRecovery,
      ),
      Provider<SpeechService>.value(value: resolvedSpeech),
      Provider<AnalyticsLog>.value(value: resolvedAnalytics),
      Provider<ProgressSnapshotExporter>.value(
        value: ProgressSnapshotExporter(
          snapshots: ProgressSnapshotRepository(
            kana: store,
            kanji: kanji,
            words: words,
            prefs: resolvedPrefs,
          ),
          files: FilePickerSnapshotPort(),
        ),
      ),
      Provider<ProgressSnapshotRestorer>.value(
        value: ProgressSnapshotRestorer(
          snapshots: ProgressSnapshotRepository(
            kana: store,
            kanji: kanji,
            words: words,
            prefs: resolvedPrefs,
          ),
          restore: ProgressSnapshotRestoreRepository(
            prefs: resolvedPrefs,
            kana: store,
            kanji: kanji,
            words: words,
          ),
          files: FilePickerSnapshotPort(),
          recovery: restoreRecovery,
        ),
      ),
    ],
    child: const KanaLoopApp(),
  );
}
