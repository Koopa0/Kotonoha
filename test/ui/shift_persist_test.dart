// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home→今天只練原句 when analytics writes fail: memory keeps the sitting,
/// the close must not claim a durable hold, and retry only flushes the buffer.
///
/// Widget tests cannot await production [FileAnalyticsLog] disk confirmation
/// inside [testWidgets] (async dart:io stalls the binding). UI behaviour uses
/// [_InjectedWriteFailureLog] with the same memory / [unpersistedCount]
/// contract; the real JSONL path is asserted in the plain [test] below and in
/// [file_analytics_log_test.dart].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Directory dir;
  late File file;
  late FileAnalyticsLog diskLog;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kotonoha-shift-persist-');
    file = File('${dir.path}/log.jsonl');
    await file.create();
    diskLog = FileAnalyticsLog.forFile(file);
    await diskLog.all();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets(
    'Home hold write failure keeps memory, shows retry, and does not claim persist',
    (tester) async {
      final analytics = _InjectedWriteFailureLog();
      final words = await WordProgressRepository.load();
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpHome(
        tester,
        analytics: analytics,
        words: words,
        clock: () => DateTime(2026, 9, 10, 10),
      );

      await tester.tap(find.text(AppStrings.shiftAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftHoldStart));
      await tester.pumpAndSettle();

      await _completeBeat(tester, unprompted: true);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.shiftClose), findsOneWidget);
      expect(find.text(AppStrings.persistFailedLine), findsWidgets);
      expect(find.text(AppStrings.shiftPersistFailed), findsWidgets);
      expect(find.text(AppStrings.persistRetry), findsWidgets);
      expect(find.text(AppStrings.shiftHeldUntilTomorrow), findsNothing);
      expect(analytics.cache.length, 6);
      expect(analytics.unpersistedCount, 6);
      expect(words.stats, isEmpty);

      analytics.allowWrites = true;
      await _tapVisible(tester, find.text(AppStrings.persistRetry));
      await tester.pumpAndSettle();

      expect(analytics.unpersistedCount, 0);
      expect(find.text(AppStrings.persistFailedLine), findsNothing);
      expect(
        find.textContaining(AppStrings.shiftHeldUntilTomorrow),
        findsWidgets,
      );
    },
  );

  test(
    'FileAnalyticsLog append fault keeps memory and flushes on retry',
    () async {
      diskLog.debugAppend = (f, line) async {
        throw const FileSystemException('injected append failure');
      };
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      final now = DateTime(2026, 9, 10, 10);
      const sessionId = 'hold-persist';

      for (final attempt in [
        ShiftSession.reservation(drill: drill, sessionId: sessionId, at: now),
        ShiftSession.sighting(
          drill: drill,
          beat: ShiftBeat.base,
          kind: ShiftSightKind.practice,
          sessionId: sessionId,
          at: now,
          lane: ShiftLane.hold,
        ),
        ShiftSession.attempt(
          drill: drill,
          beat: ShiftBeat.base,
          check: ShiftCheck.read,
          prompted: false,
          correct: true,
          sessionId: sessionId,
          at: now,
          lane: ShiftLane.hold,
        ),
        ShiftSession.attempt(
          drill: drill,
          beat: ShiftBeat.base,
          check: ShiftCheck.sense,
          prompted: false,
          correct: true,
          sessionId: sessionId,
          at: now,
          lane: ShiftLane.hold,
          readSupport: ShiftReadSupport.independent,
        ),
      ]) {
        try {
          await diskLog.record(attempt);
        } on Object {
          // Same contract as shift UI: memory retains, disk is not claimed.
        }
      }

      expect(diskLog.unpersistedCount, 4);
      expect(file.readAsLinesSync().where((l) => l.trim().isNotEmpty), isEmpty);

      diskLog.debugAppend = null;
      await diskLog.flushPending();

      expect(diskLog.unpersistedCount, 0);
      expect(
        file.readAsLinesSync().where((l) => l.trim().isNotEmpty).length,
        4,
      );
      final reopened = FileAnalyticsLog.forFile(file);
      expect(await reopened.count(), 4);
    },
  );
}

/// Mirrors [FileAnalyticsLog] memory retention and honest [unpersistedCount]
/// without post-failure async disk confirmation (which stalls [testWidgets]).
class _InjectedWriteFailureLog implements AnalyticsLog {
  final List<Attempt> cache = [];
  bool allowWrites = false;

  @override
  int get unpersistedCount => _unpersisted.length;

  final List<Attempt> _unpersisted = [];

  @override
  Future<void> record(Attempt attempt) async {
    cache.add(attempt);
    _unpersisted.add(attempt);
    if (!allowWrites) {
      throw const FileSystemException('injected append failure');
    }
    _unpersisted.clear();
  }

  @override
  Future<List<Attempt>> all() async => List.unmodifiable(cache);

  @override
  Future<int> count() async => cache.length;

  @override
  Future<void> flushPending() async {
    if (_unpersisted.isEmpty) return;
    if (!allowWrites) {
      throw const FileSystemException('injected append failure');
    }
    _unpersisted.clear();
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required AnalyticsLog analytics,
  required WordProgressRepository words,
  required DateTime Function() clock,
}) async {
  final kana = await KanaProgressRepository.load();
  final kanji = await KanjiReadingRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            kanjiFlush: kanji.flushPending,
            wordFlush: words.flushPending,
            analyticsFlush: analytics.flushPending,
          ),
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: analytics),
      ],
      child: MaterialApp(home: HomeScreen(clock: clock)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeBeat(
  WidgetTester tester, {
  required bool unprompted,
}) async {
  await _tapVisible(
    tester,
    find.text(unprompted ? AppStrings.iReadUnprompted : AppStrings.recallHint),
  );
  await _tapVisible(
    tester,
    find.text(unprompted ? AppStrings.iReadIt : AppStrings.iReadAfterHint),
  );
  await tester.enterText(find.byType(TextField), '自評用筆記');
  await tester.pumpAndSettle();
  await _tapVisible(
    tester,
    find.text(
      unprompted ? AppStrings.shiftSenseReady : AppStrings.shiftSenseHint,
    ),
  );
  await _tapVisible(
    tester,
    find.text(
      unprompted ? AppStrings.shiftSenseOk : AppStrings.shiftSenseOkAfterHint,
    ),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      280,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
