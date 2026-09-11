// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

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
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/shift/shift_focus_screen.dart';
import 'package:kotonoha/ui/shift/shift_practice_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

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
      expect(_grades(await analytics.all()), isEmpty);

      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      var logged = _grades(await analytics.all());
      expect(logged, hasLength(1));
      expect(logged.single.meta[AttemptMeta.evidence], ShiftCheck.read.name);
      expect(logged.single.meta[AttemptMeta.beat], ShiftBeat.base.name);
      expect(logged.single.meta[AttemptMeta.prompted], isFalse);

      await tester.enterText(find.byType(TextField), drill.base.meaning);
      await tester.pumpAndSettle();
      expect(_grades(await analytics.all()), hasLength(1));
      expect(find.text(drill.base.relation), findsNothing);

      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      expect(_grades(await analytics.all()), hasLength(1));
      expect(find.text('藍色的天空'), findsOneWidget);
      expect(find.text(drill.base.relation), findsOneWidget);

      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();
      logged = _grades(await analytics.all());
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

      logged = _grades(await analytics.all());
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

  testWidgets(
    'read self-grade failure after unprompted commit does not claim independent read support',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          child: ShiftPracticeScreen(
            drill: drill,
            clock: () => DateTime(2026, 9, 10, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iCouldnt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();

      final logged = _grades(await analytics.all());
      expect(logged, hasLength(2));
      expect(logged.first.correct, isFalse);
      expect(logged.first.meta[AttemptMeta.evidence], ShiftCheck.read.name);
      expect(logged.last.correct, isTrue);
      expect(
        logged.last.meta[AttemptMeta.readSupport],
        ShiftReadSupport.prompted,
      );

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();

      expect(
        find.text(
          AppStrings.shiftSenseSelfGrade(
            prompted: false,
            correct: true,
            readSupport: ShiftReadSupport.prompted,
          ),
        ),
        findsWidgets,
      );
      expect(find.textContaining('讀音自行讀出'), findsNothing);
    },
  );

  testWidgets(
    'verified unprompted read keeps independent read support on sense grade',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          child: ShiftPracticeScreen(
            drill: drill,
            clock: () => DateTime(2026, 9, 10, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();

      final logged = _grades(await analytics.all());
      expect(logged, hasLength(2));
      expect(logged.first.correct, isTrue);
      expect(logged.last.correct, isTrue);
      expect(
        logged.last.meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
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

  testWidgets(
    'replay then Home return stops the owned play via FlutterTtsSpeechService',
    (tester) async {
      final client = FakeTtsClient(holdSpeak: Completer<Object?>());
      final speech = FlutterTtsSpeechService(client: client, ready: true);
      _configureView(tester, size: const Size(420, 2000));
      await _pumpOfficialHome(tester, speech: speech);
      await _openShizukaFromHome(tester);

      await _tapVisible(tester, find.text(AppStrings.iReadUnprompted));
      await tester.pump();
      expect(client.spoken, ['しずかなへや']);
      expect(client.stopCount, 1);

      await _tapVisible(tester, find.byTooltip(AppStrings.playSound));
      await tester.pump();
      expect(client.spoken, ['しずかなへや', 'しずかなへや']);
      expect(client.stopCount, 2);

      final stopsBeforeLeave = client.stopCount;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(client.stopCount, greaterThan(stopsBeforeLeave));
    },
  );

  testWidgets(
    'replay then inactive/paused stops the owned play via FlutterTtsSpeechService',
    (tester) async {
      final client = FakeTtsClient(holdSpeak: Completer<Object?>());
      final speech = FlutterTtsSpeechService(client: client, ready: true);
      _configureView(tester, size: const Size(420, 2000));
      await _pumpOfficialHome(tester, speech: speech);
      await _openShizukaFromHome(tester);

      await _tapVisible(tester, find.text(AppStrings.recallHint));
      await tester.pump();
      await _tapVisible(tester, find.byTooltip(AppStrings.playSound));
      await tester.pump();
      expect(client.stopCount, 2);

      final stopsBeforeBackground = client.stopCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(client.stopCount, greaterThan(stopsBeforeBackground));
    },
  );

  testWidgets('old shift cleanup must not stop a newer play', (tester) async {
    final client = FakeTtsClient(holdSpeak: Completer<Object?>());
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    final first = ShiftSession.drillById('i-adj-aoi-noun')!;
    final second = ShiftSession.drillById('na-adj-shizuka-noun')!;
    await tester.pumpWidget(
      _harness(
        analytics: InMemoryAnalyticsLog(),
        speech: speech,
        child: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(ShiftPracticeScreen.route(first)),
                  child: const Text('open-a'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pump();
    await tester.tap(find.byTooltip(AppStrings.playSound));
    await tester.pump();
    final stale = speech.generation;
    expect(stale, isNonZero);

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(ShiftPracticeScreen.route(second));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pump();
    expect(speech.generation, isNot(stale));
    final stopsBeforeStale = client.stopCount;

    await speech.stop(generation: stale);
    expect(client.stopCount, stopsBeforeStale);
  });

  testWidgets(
    '320x640 2x + keyboard keeps source, sense pad, and submit reachable',
    (tester) async {
      _configureView(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        keyboardInset: 300,
      );
      await _pumpOfficialHome(tester, speech: const SilentSpeechService());
      await _openShizukaFromHome(
        tester,
        sourceUrl: 'https://www.satorireader.com/articles/haru-episode-1',
      );
      expect(tester.takeException(), isNull);

      await _completeBeat(tester, unprompted: true);
      expect(find.text('しずかな まち'), findsOneWidget);
      await _completeBeat(tester, unprompted: false);
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.shiftClose), findsOneWidget);
    },
  );

  testWidgets('320x640 1x with source keeps the sense pad operable', (
    tester,
  ) async {
    _configureView(tester, size: const Size(320, 640));
    await _pumpOfficialHome(tester, speech: const SilentSpeechService());
    await _openShizukaFromHome(
      tester,
      sourceUrl: 'https://www.satorireader.com/articles/haru-episode-1',
    );
    await _tapVisible(tester, find.text(AppStrings.iReadUnprompted));
    await _tapVisible(tester, find.text(AppStrings.iReadIt));
    expect(find.byType(TextField), findsOneWidget);
    await _tapVisible(tester, find.text(AppStrings.shiftSenseReady));
    await _tapVisible(tester, find.text(AppStrings.shiftSenseOk));
    expect(tester.takeException(), isNull);
    expect(find.text('しずかな まち'), findsOneWidget);
  });

  testWidgets('320x640 2x without source keeps the sense pad operable', (
    tester,
  ) async {
    _configureView(tester, size: const Size(320, 640), textScale: 2);
    await _pumpOfficialHome(tester, speech: const SilentSpeechService());
    await _openShizukaFromHome(tester);
    await _completeBeat(tester, unprompted: true);
    expect(tester.takeException(), isNull);
    expect(find.text('しずかな まち'), findsOneWidget);
  });
}

List<Attempt> _grades(List<Attempt> all) => [
  for (final attempt in all)
    if (attempt.meta[AttemptMeta.scored] != false &&
        (attempt.meta[AttemptMeta.evidence] == ShiftCheck.read.name ||
            attempt.meta[AttemptMeta.evidence] == ShiftCheck.sense.name))
      attempt,
];

Widget _harness({
  required AnalyticsLog analytics,
  required Widget child,
  WordProgressRepository? words,
  SpeechService speech = const SilentSpeechService(),
}) {
  return MultiProvider(
    providers: [
      if (words != null)
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
      Provider<SpeechService>.value(value: speech),
      Provider<AnalyticsLog>.value(value: analytics),
    ],
    child: MaterialApp(home: child),
  );
}

void _configureView(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  double keyboardInset = 0,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (keyboardInset > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  }
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _pumpOfficialHome(
  WidgetTester tester, {
  required SpeechService speech,
}) async {
  SharedPreferences.setMockInitialValues({});
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
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: const KanaLoopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openShizukaFromHome(
  WidgetTester tester, {
  String? sourceUrl,
}) async {
  await _tapVisible(tester, find.text(AppStrings.shiftAction));
  await _tapVisible(tester, find.text('しずかな + 名詞'));
  if (sourceUrl != null) {
    await _show(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), sourceUrl);
    await tester.pumpAndSettle();
  }
  await _tapVisible(tester, find.text(AppStrings.shiftStart));
  expect(find.text('しずかな へや'), findsOneWidget);
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
  await _show(tester, find.byType(TextField));
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

Future<void> _show(WidgetTester tester, Finder finder) async {
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
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  final scrollException = tester.takeException();
  if (scrollException != null &&
      !scrollException.toString().contains('overflowed')) {
    fail('$scrollException');
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
  final after = tester.takeException();
  if (after != null && !after.toString().contains('overflowed')) {
    fail('$after');
  }
}
