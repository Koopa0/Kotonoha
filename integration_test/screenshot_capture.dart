// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_restore_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/file_picker_snapshot_port.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/progress_snapshot_restorer.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/listening_session.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real app (with seeded sample progress) to the four screens the
/// README cites. Not a test of behaviour — a capture run.
/// Writes `screenshots/01-home.png`, `02-listening.png`, `03-kanji.png`,
/// `04-progress.png`.
///
/// ```sh
/// flutter drive --driver=test_driver/screenshot.dart \
///   --target=integration_test/screenshot_capture.dart -d emulator-5554
/// ```
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture product screenshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    SharedPreferences.setMockInitialValues({});
    final prefs = await PreferencesService.create();
    final store = await KanaProgressRepository.load(prefs);
    // Sample progress only — enough hiragana that rooms open, not mastery.
    for (final l in Lessons.fromKana(store.allKana)) {
      if (l.script == KanaScript.hiragana) await store.markUnitLearned(l.id);
    }
    final learned = StudySet.learned(store);
    for (var i = 0; i < learned.length; i++) {
      await store.recordAnswer(
        learned[i],
        correct: i % 5 != 0,
        at: DateTime(2026, 6),
        latencyMs: 250 + i * 20,
      );
    }
    for (final unlock in ['words', 'phrases', 'kanjiPhrases']) {
      await store.markUnlockSeen(unlock);
    }

    final kanji = await KanjiReadingRepository.load(prefs);
    final words = await WordProgressRepository.load(prefs);
    // 聞き取り only opens after a T01 item has been met.
    for (final id in ListeningSession.t01ProgressIds) {
      await words.introduce(id, at: DateTime(2026, 6));
    }
    final checks = await PlacementCheckRepository.load();
    final travel = await TravelFocusRepository.load();
    final journalRecovery = await ProgressRestoreJournal.recoverIfNeeded(prefs);
    final restoreRecovery = ProgressRestoreRecoveryController(
      prefs: prefs,
      kana: store,
      kanji: kanji,
      words: words,
      needsRecovery: journalRecovery.needsRecovery,
    );
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
    await tester.pumpWidget(
      MultiProvider(
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
          // Capture the listen-first room, not the no-voice banner.
          Provider<SpeechService>.value(value: const _HeardSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<ProgressSnapshotExporter>.value(
            value: ProgressSnapshotExporter(
              snapshots: ProgressSnapshotRepository(
                kana: store,
                kanji: kanji,
                words: words,
                prefs: prefs,
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
                prefs: prefs,
              ),
              restore: ProgressSnapshotRestoreRepository(
                prefs: prefs,
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
      ),
    );
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }

    Future<void> openCard(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(find.text(AppStrings.reviewKanaAction), findsOneWidget);
    expect(find.text(AppStrings.learnNewKanaAction), findsOneWidget);
    await shot('01-home');

    await openCard(AppStrings.listenFirstAction);
    expect(find.text(AppStrings.listeningTitle), findsWidgets);
    expect(find.text(AppStrings.listeningPrompt), findsOneWidget);
    expect(find.text(AppStrings.listeningReveal), findsOneWidget);
    expect(find.text(AppStrings.dictationPrompt), findsNothing);
    await shot('02-listening');
    await back();

    await openCard(AppStrings.kanjiEntry);
    expect(find.text(AppStrings.kanjiTitle), findsWidgets);
    expect(find.text(AppStrings.kanjiTeachHint), findsOneWidget);
    expect(find.text(AppStrings.kanjiChooseReading), findsNothing);
    await shot('03-kanji');
    await back();

    await openCard(AppStrings.progress);
    expect(find.text(AppStrings.progress), findsWidgets);
    expect(find.text(AppStrings.practiced), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    await shot('04-progress');
  });
}

/// Completes playback so the capture shows the official listen-first chrome
/// (prompt + 揭曉), not the silent-engine failure line.
class _HeardSpeechService implements SpeechService {
  const _HeardSpeechService();

  @override
  Future<void> speak(String text) async {}

  @override
  Future<SpeechPlaybackResult> play(String text) async =>
      SpeechPlaybackResult.played;

  @override
  int get generation => 0;

  @override
  Future<void> stop({int? generation}) async {}
}
