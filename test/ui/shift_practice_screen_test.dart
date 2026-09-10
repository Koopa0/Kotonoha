// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/shift/shift_focus_screen.dart';
import 'package:kotonoha/ui/shift/shift_practice_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home 換句 opens the picker and starts the named drill', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final kana = await KanaProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    final words = await WordProgressRepository.load();
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
            ),
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: const KanaLoopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.shiftAction), findsOneWidget);
    expect(find.text(AppStrings.shiftEntry), findsOneWidget);
    await tester.tap(find.text(AppStrings.shiftAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftPickerLead), findsOneWidget);
    expect(find.text('い／な形容詞修飾'), findsOneWidget);
    expect(find.text('あおい + 名詞'), findsOneWidget);
    expect(find.text('しずかな + 名詞'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://example.test/satori',
    );
    await tester.tap(find.text('しずかな + 名詞'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftStart));
    await tester.pumpAndSettle();

    expect(find.text('しずかな へや'), findsOneWidget);
    expect(
      find.text(AppStrings.shiftSourceChip('https://example.test/satori')),
      findsOneWidget,
    );
    expect(find.text('shizuka na heya'), findsNothing);
    expect(find.text('安靜的房間'), findsNothing);
  });

  testWidgets(
    'read and sense stay hidden, free-text is not a grade, word SRS stays still',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          words: words,
          child: ShiftPracticeScreen(
            drill: drill,
            sourceUrl: 'https://example.test/note',
            clock: () => DateTime(2026, 9, 10, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('あおい そら'), findsOneWidget);
      expect(find.text('aoi sora'), findsNothing);
      expect(find.text('藍色的天空'), findsNothing);
      expect(find.textContaining('修飾'), findsNothing);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      expect(find.text('aoi sora'), findsOneWidget);
      expect(find.text('藍色的天空'), findsNothing);
      expect(await analytics.all(), isEmpty);

      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      var logged = await analytics.all();
      expect(logged, hasLength(1));
      expect(logged.single.meta[AttemptMeta.evidence], ShiftCheck.read.name);
      expect(logged.single.meta[AttemptMeta.beat], ShiftBeat.base.name);
      expect(logged.single.meta[AttemptMeta.prompted], isFalse);

      await tester.enterText(find.byType(TextField), drill.base.meaning);
      await tester.pumpAndSettle();
      expect(await analytics.all(), hasLength(1));
      expect(find.text(drill.base.relation), findsNothing);

      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      expect(await analytics.all(), hasLength(1));
      expect(find.text('藍色的天空'), findsOneWidget);
      expect(find.text(drill.base.relation), findsOneWidget);

      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();
      logged = await analytics.all();
      expect(logged, hasLength(2));
      expect(logged.last.meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(logged.last.meta[AttemptMeta.prompted], isFalse);

      expect(find.text('あおい うみ'), findsOneWidget);
      expect(find.text(AppStrings.shiftBridgeNoun), findsOneWidget);
      expect(find.text('aoi umi'), findsNothing);
      expect(find.text('藍色的海'), findsNothing);

      await tester.tap(find.text(AppStrings.recallHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '藍色的海');
      await tester.tap(find.text(AppStrings.shiftSenseHint));
      await tester.pumpAndSettle();
      expect(find.text('藍色的海'), findsWidgets);
      await tester.tap(find.text(AppStrings.shiftSenseOkAfterHint));
      await tester.pumpAndSettle();

      logged = await analytics.all();
      expect(logged, hasLength(4));
      expect(logged[2].meta[AttemptMeta.prompted], isTrue);
      expect(logged[2].meta[AttemptMeta.evidence], ShiftCheck.read.name);
      expect(logged[3].meta[AttemptMeta.beat], ShiftBeat.shift.name);
      expect(logged[3].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(logged[3].meta[AttemptMeta.prompted], isTrue);
      expect(logged[3].meta[AttemptMeta.source], 'https://example.test/note');
      expect(ShiftSession.isTransferSense(logged[3]), isTrue);
      expect(ShiftSession.marksFocusMastered(logged), isFalse);
      expect(find.text(AppStrings.shiftClose), findsOneWidget);
      expect(find.text(AppStrings.shiftCloseNote), findsOneWidget);

      expect(words.stats, isEmpty);
      expect(words.statForItem('word:そら').isSeen, isFalse);
      expect(words.statForItem('phrase:そらが あおい').isSeen, isFalse);
      expect(words.statForItem('shift:i-adj-aoi-noun:base').isSeen, isFalse);
    },
  );

  testWidgets('picker does not start until the learner chooses a drill', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    ShiftDrill? started;
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(onStarted: (drill) => started = drill),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftSelfGradeNote), findsWidgets);
    await tester.tap(find.text(AppStrings.shiftStart));
    await tester.pumpAndSettle();
    expect(started?.id, 'i-adj-aoi-noun');
    expect(find.text('あおい そら'), findsOneWidget);
  });
}

Widget _harness({
  required AnalyticsLog analytics,
  required Widget child,
  WordProgressRepository? words,
}) {
  return MultiProvider(
    providers: [
      if (words != null)
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
      Provider<SpeechService>.value(value: const SilentSpeechService()),
      Provider<AnalyticsLog>.value(value: analytics),
    ],
    child: MaterialApp(home: child),
  );
}
