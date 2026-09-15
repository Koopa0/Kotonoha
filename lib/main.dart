// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_opener.dart';
import 'package:kotonoha/data/services/file_picker_snapshot_port.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_restore_placement_discard.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_recovery.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_exporter.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
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
/// [prefs], [speech], [analytics], [kana], and [words] are test seams only —
/// production [main] leaves them null. A substitute [kana] or [words] must
/// honour the same notify, save / retry, and snapshot-ownership contract as
/// the matching local owner; it does not change the other owners.
Future<Widget> bootstrap({
  PreferencesService? prefs,
  SpeechService? speech,
  AnalyticsLog? analytics,
  KanaProgressRepository? kana,
  WordProgressRepository? words,
}) async {
  final resolvedPrefs = prefs ?? await PreferencesService.create();
  final journalRecovery = await ProgressRestoreJournal.recoverIfNeeded(
    resolvedPrefs,
  );
  await ProgressRestorePlacementDiscard.recoverIfNeeded(resolvedPrefs);
  final store = kana ?? await KanaProgressRepository.load(resolvedPrefs);
  final kanji = await KanjiReadingRepository.load(resolvedPrefs);
  final wordOwner = words ?? await WordProgressRepository.load(resolvedPrefs);
  // Cross-owner recovery is a use case; the controller is what the UI
  // observes and retries through.
  final restoreRecovery = ProgressRestoreRecoveryController(
    recovery: ProgressRestoreRecovery(
      prefs: resolvedPrefs,
      kana: store,
      kanji: kanji,
      words: wordOwner,
    ),
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
    wordFlush: wordOwner.flushPending,
    placementFlush: checks.flushPending,
    analyticsFlush: resolvedAnalytics.flushPending,
    travelFocusFlush: travel.flushPending,
    health: [
      store.statsHealth,
      store.learnedUnitsHealth,
      store.seenUnlocksHealth,
      kanji.statsHealth,
      wordOwner.statsHealth,
      checks.health,
      travel.health,
    ],
  );
  // Every production [recordObserved] write shares this owner. Shift
  // still tracks [AnalyticsLog.record] itself and must not also use
  // [recordObserved], or the same future would be notified twice.
  bindObservedWriteNotify(resolvedAnalytics, persistence.trackAnalytics);
  // The one read across the three progress owners, shared by backup and
  // restore. Stateless: it never caches a snapshot.
  final capture = ProgressSnapshotCapture(
    kana: store,
    kanji: kanji,
    words: wordOwner,
    prefs: resolvedPrefs,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<KanaProgressRepository>.value(value: store),
      ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
      ChangeNotifierProvider<WordProgressRepository>.value(value: wordOwner),
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
          capture: capture,
          files: FilePickerSnapshotPort(),
        ),
      ),
      Provider<ProgressSnapshotRestorer>.value(
        value: ProgressSnapshotRestorer(
          capture: capture,
          transaction: ProgressRestoreTransaction(
            prefs: resolvedPrefs,
            kana: store,
            kanji: kanji,
            words: wordOwner,
            placement: checks,
          ),
          files: FilePickerSnapshotPort(),
        ),
      ),
    ],
    child: const KanaLoopApp(),
  );
}
