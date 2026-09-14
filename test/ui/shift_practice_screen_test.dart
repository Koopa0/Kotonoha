// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/app.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/shift_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/shift/shift_focus_screen.dart';
import 'package:kotonoha/ui/shift/shift_practice_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';
import '../support/restore_recovery_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home 換句 opens the picker and starts the named drill', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await PreferencesService.create();
    final kana = await KanaProgressRepository.load(prefs);
    final kanji = await KanjiReadingRepository.load(prefs);
    final words = await WordProgressRepository.load(prefs);
    final recovery = recoveryForRepos(
      prefs: prefs,
      kana: kana,
      kanji: kanji,
      words: words,
    );
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
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
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
    expect(find.text(kBringFocusTitle), findsOneWidget);
    expect(find.text('換主角 わたし → かれ'), findsOneWidget);

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
            beats: const [ShiftBeat.base],
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

  testWidgets(
    'slow sense write ignores a double confirm and still advances one beat',
    (tester) async {
      final analytics = _GatedAnalyticsLog();
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

      analytics.senseGate = Completer<void>();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pump();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pump();
      analytics.senseGate!.complete();
      await tester.pumpAndSettle();

      final senses = _grades(await analytics.all())
          .where((a) => a.meta[AttemptMeta.evidence] == ShiftCheck.sense.name);
      expect(senses, hasLength(1));
      expect(senses.single.meta[AttemptMeta.beat], ShiftBeat.base.name);
      expect(find.text('あおい うみ'), findsOneWidget);
      expect(find.text(AppStrings.shiftClose), findsNothing);
    },
  );

  testWidgets('hold lane slow sense write records one sense row only', (
    tester,
  ) async {
    final analytics = _GatedAnalyticsLog();
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftPracticeScreen(
          drill: drill,
          lane: ShiftLane.hold,
          beats: const [ShiftBeat.base],
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

    analytics.senseGate = Completer<void>();
    await tester.tap(find.text(AppStrings.shiftSenseOk));
    await tester.pump();
    await tester.tap(find.text(AppStrings.shiftSenseOk));
    await tester.pump();
    analytics.senseGate!.complete();
    await tester.pumpAndSettle();

    final senses = _grades(await analytics.all())
        .where((a) => a.meta[AttemptMeta.evidence] == ShiftCheck.sense.name);
    expect(senses, hasLength(1));
    expect(find.text(AppStrings.shiftClose), findsOneWidget);
  });

  testWidgets('picker does not start until the learner chooses a drill', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    ShiftDrill? started;
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(onStarted: (drill) => started = drill),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftSelfGradeNote), findsWidgets);
    await _tapVisible(tester, find.text(AppStrings.shiftStart));
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

  testWidgets(
    'action drill teaches forms first, then grades verb and roles apart',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          words: words,
          child: ShiftPracticeScreen(
            drill: drill,
            sourceUrl: 'https://example.test/note',
            clock: () => DateTime(2026, 9, 11, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.shiftIntroLead), findsOneWidget);
      expect(find.text('わたしが かばんを もってきます'), findsNothing);
      expect(find.text('かれが かばんを もってきます'), findsNothing);
      expect(find.text('藍色的天空'), findsNothing);
      await _finishIntro(tester);
      expect(find.text('わたしが かばんを もってきます'), findsOneWidget);
      expect(find.text('watashi ga kaban o mottekimasu'), findsNothing);
      expect(find.text('我把包包帶過來。'), findsNothing);
      expect(find.text(AppStrings.shiftVerbPrompt), findsNothing);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      expect(find.text('watashi ga kaban o mottekimasu'), findsOneWidget);
      expect(find.text('我把包包帶過來。'), findsNothing);
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();

      var logged = _grades(await analytics.all());
      expect(logged, hasLength(1));
      expect(logged.single.meta[AttemptMeta.evidence], ShiftCheck.read.name);
      expect(logged.single.meta[AttemptMeta.beat], ShiftBeat.base.name);

      expect(find.text(AppStrings.shiftVerbPrompt), findsOneWidget);
      expect(find.text(drill.formHint), findsNothing);
      await tester.tap(find.text('もってきます'));
      await tester.pumpAndSettle();
      logged = _grades(await analytics.all());
      expect(logged, hasLength(2));
      expect(logged.last.meta[AttemptMeta.evidence], ShiftCheck.verb.name);
      expect(logged.last.correct, isFalse);
      expect(logged.last.meta[AttemptMeta.prompted], isFalse);
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));

      expect(find.text(AppStrings.shiftRolesWho), findsOneWidget);
      await tester.tap(find.text('かれ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ほん'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftRolesReady));
      await tester.pumpAndSettle();
      logged = _grades(await analytics.all());
      expect(logged, hasLength(3));
      expect(logged.last.meta[AttemptMeta.evidence], ShiftCheck.roles.name);
      expect(logged.last.correct, isFalse);
      expect(logged.last.meta[AttemptMeta.prompted], isFalse);
      expect(find.text(drill.base.relation), findsNothing);
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));

      await tester.enterText(find.byType(TextField), drill.base.meaning);
      await tester.pumpAndSettle();
      expect(_grades(await analytics.all()), hasLength(3));
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      expect(find.text('我把包包帶過來。'), findsOneWidget);
      expect(find.text(AppStrings.shiftSenseOk), findsNothing);
      await tester.tap(find.text(AppStrings.shiftSenseOkAfterHint));
      await tester.pumpAndSettle();

      expect(find.text('かれが かばんを もってきます'), findsOneWidget);
      expect(find.text(AppStrings.shiftBridgeActor), findsOneWidget);
      expect(find.text('kare ga kaban o mottekimasu'), findsNothing);

      await tester.tap(find.text(AppStrings.recallHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftVerbHint));
      expect(find.text(drill.formHint), findsOneWidget);
      await tester.tap(find.text('もってくる'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      await _tapVisible(tester, find.text(AppStrings.shiftRolesHint));
      await tester.tap(find.text('かれ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('かばん').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftRolesReady));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      await tester.enterText(find.byType(TextField), '他把包包帶過來。');
      await tester.tap(find.text(AppStrings.shiftSenseHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseOkAfterHint));
      await tester.pumpAndSettle();

      logged = _grades(await analytics.all());
      expect(logged, hasLength(8));
      expect(logged[3].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(logged[3].meta[AttemptMeta.beat], ShiftBeat.base.name);
      expect(logged[3].meta[AttemptMeta.prompted], isTrue);
      expect(
        logged[3].meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
      expect(logged[4].meta[AttemptMeta.beat], ShiftBeat.shift.name);
      expect(logged[4].meta[AttemptMeta.evidence], ShiftCheck.read.name);
      expect(logged[4].meta[AttemptMeta.prompted], isTrue);
      expect(logged[5].meta[AttemptMeta.evidence], ShiftCheck.verb.name);
      expect(logged[5].correct, isTrue);
      expect(logged[5].meta[AttemptMeta.prompted], isTrue);
      expect(ShiftSession.isTransferVerb(logged[5]), isTrue);
      expect(logged[6].meta[AttemptMeta.evidence], ShiftCheck.roles.name);
      expect(logged[6].correct, isTrue);
      expect(ShiftSession.isTransferRoles(logged[6]), isTrue);
      expect(logged[7].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(logged[7].meta[AttemptMeta.source], 'https://example.test/note');
      expect(ShiftSession.isTransferSense(logged[7]), isTrue);
      expect(ShiftSession.marksFocusMastered(logged), isFalse);
      expect(find.text(AppStrings.shiftClose), findsOneWidget);
      expect(
        find.text(
          AppStrings.shiftVerbSelfGrade(prompted: false, correct: false),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          AppStrings.shiftRolesSelfGrade(prompted: false, correct: false),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          AppStrings.shiftSenseSelfGrade(
            prompted: true,
            correct: true,
            readSupport: ShiftReadSupport.independent,
          ),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          AppStrings.shiftSenseSelfGrade(
            prompted: false,
            correct: true,
            readSupport: ShiftReadSupport.independent,
          ),
        ),
        findsNothing,
      );
      expect(words.stats, isEmpty);
    },
  );

  testWidgets(
    'roles hint carries semantic support into unprompted sense self-grade',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          child: ShiftPracticeScreen(
            drill: drill,
            beats: const [ShiftBeat.base],
            clock: () => DateTime(2026, 9, 10, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _finishIntro(tester);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();

      await tester.tap(find.text(drill.base.dictionaryForm));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));

      await _tapVisible(tester, find.text(AppStrings.shiftRolesHint));
      expect(find.text(drill.base.relation), findsOneWidget);
      await tester.tap(find.text(drill.base.actor));
      await tester.pumpAndSettle();
      await tester.tap(find.text(drill.base.item));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftRolesReady));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));

      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftSenseOk), findsNothing);
      await tester.tap(find.text(AppStrings.shiftSenseOkAfterHint));
      await tester.pumpAndSettle();

      final logged = _grades(await analytics.all());
      expect(logged, hasLength(4));
      expect(logged[2].meta[AttemptMeta.evidence], ShiftCheck.roles.name);
      expect(logged[2].meta[AttemptMeta.prompted], isTrue);
      expect(logged[3].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(logged[3].meta[AttemptMeta.prompted], isTrue);
      expect(
        logged[3].meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
    },
  );

  testWidgets(
    'roles miss reveal carries who/what support into sense; correct lock does not',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          words: words,
          child: ShiftPracticeScreen(
            drill: drill,
            beats: const [ShiftBeat.base],
            clock: () => DateTime(2026, 9, 11, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _finishIntro(tester);
      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もってくる'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));

      expect(find.text(AppStrings.shiftRolesHint), findsOneWidget);
      await tester.tap(find.text('かれ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ほん'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftRolesReady));
      await tester.pumpAndSettle();
      expect(find.text(drill.base.relation), findsNothing);
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      await tester.enterText(find.byType(TextField), '自評用筆記');
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftSenseOk), findsNothing);
      await tester.tap(find.text(AppStrings.shiftSenseOkAfterHint));
      await tester.pumpAndSettle();

      final logged = _grades(await analytics.all());
      expect(logged, hasLength(4));
      expect(logged[2].meta[AttemptMeta.evidence], ShiftCheck.roles.name);
      expect(logged[2].correct, isFalse);
      expect(logged[2].meta[AttemptMeta.prompted], isFalse);
      expect(logged[3].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(logged[3].meta[AttemptMeta.prompted], isTrue);
      expect(
        logged[3].meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
      expect(
        find.text(
          AppStrings.shiftRolesSelfGrade(prompted: false, correct: false),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          AppStrings.shiftSenseSelfGrade(
            prompted: true,
            correct: true,
            readSupport: ShiftReadSupport.independent,
          ),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          AppStrings.shiftVerbSelfGrade(prompted: false, correct: true),
        ),
        findsWidgets,
      );
      expect(words.stats, isEmpty);
    },
  );

  testWidgets('correct unprompted roles leave sense unprompted', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftPracticeScreen(
          drill: drill,
          beats: const [ShiftBeat.base],
          clock: () => DateTime(2026, 9, 11, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _finishIntro(tester);
    await _completeActionBeat(tester, drill.base, unprompted: true);

    final logged = _grades(await analytics.all());
    expect(logged, hasLength(4));
    expect(logged[2].meta[AttemptMeta.evidence], ShiftCheck.roles.name);
    expect(logged[2].correct, isTrue);
    expect(logged[2].meta[AttemptMeta.prompted], isFalse);
    expect(logged[3].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
    expect(logged[3].meta[AttemptMeta.prompted], isFalse);
    expect(
      logged[3].meta[AttemptMeta.readSupport],
      ShiftReadSupport.independent,
    );
    expect(
      find.text(
        AppStrings.shiftSenseSelfGrade(
          prompted: false,
          correct: true,
          readSupport: ShiftReadSupport.independent,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets(
    'reserved-shift sitting still teaches first, then only the held beat',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          child: ShiftPracticeScreen(
            drill: drill,
            beats: const [ShiftBeat.shift],
            clock: () => DateTime(2026, 9, 12, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftIntroLead), findsOneWidget);
      expect(find.text('かれが かばんを もってきます'), findsNothing);
      await _finishIntro(tester);
      expect(find.text('かれが かばんを もってきます'), findsOneWidget);
      expect(find.text('わたしが かばんを もってきます'), findsNothing);
      await _completeActionBeat(tester, drill.shift, unprompted: true);
      expect(find.text(AppStrings.shiftClose), findsOneWidget);
      final logged = await analytics.all();
      expect(
        logged.every((a) => a.meta[AttemptMeta.beat] == ShiftBeat.shift.name),
        isTrue,
      );
      expect(
        logged.any((a) => a.meta[AttemptMeta.evidence] == ShiftCheck.verb.name),
        isTrue,
      );
      expect(logged.any((a) => a.meta[AttemptMeta.scored] == true), isTrue);
    },
  );

  testWidgets('320x640 2x action intro stays reachable then completes a beat', (
    tester,
  ) async {
    _configureView(
      tester,
      size: const Size(320, 640),
      textScale: 2,
      keyboardInset: 300,
    );
    final analytics = InMemoryAnalyticsLog();
    final drill = ShiftSession.drillById('bring-item-hon-mizu')!;
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftPracticeScreen(
          drill: drill,
          clock: () => DateTime(2026, 9, 11, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _finishIntro(tester);
    expect(find.text('かのじょが ほんを もってきます'), findsOneWidget);
    await _completeActionBeat(tester, drill.base, unprompted: true);
    expect(find.text('かのじょが みずを もってきます'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'roles gloss carries into sense evidence; 想好了 cannot claim unprompted',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      final drill = ShiftSession.drillById('bring-actor-watashi-kare')!;
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          words: words,
          child: ShiftPracticeScreen(
            drill: drill,
            clock: () => DateTime(2026, 9, 11, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _finishIntro(tester);
      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もってくる'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      expect(find.text(drill.base.relation), findsNothing);
      await _tapVisible(tester, find.text(AppStrings.shiftRolesHint));
      expect(find.text(drill.base.relation), findsOneWidget);
      await tester.tap(find.text('わたし').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('かばん').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftRolesReady));
      await tester.pumpAndSettle();
      var logged = _grades(await analytics.all());
      expect(logged.last.meta[AttemptMeta.evidence], ShiftCheck.roles.name);
      expect(logged.last.meta[AttemptMeta.prompted], isTrue);
      expect(find.text(drill.base.relation), findsOneWidget);
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      await tester.enterText(find.byType(TextField), '自評用筆記');
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftSenseOk), findsNothing);
      expect(find.text(AppStrings.shiftSenseOkAfterHint), findsOneWidget);
      await tester.tap(find.text(AppStrings.shiftSenseOkAfterHint));
      await tester.pumpAndSettle();

      logged = _grades(await analytics.all());
      final roles = logged.where(
        (a) => a.meta[AttemptMeta.evidence] == ShiftCheck.roles.name,
      );
      final sense = logged.where(
        (a) => a.meta[AttemptMeta.evidence] == ShiftCheck.sense.name,
      );
      expect(roles.single.meta[AttemptMeta.prompted], isTrue);
      expect(sense.single.meta[AttemptMeta.prompted], isTrue);
      expect(
        sense.single.meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
      expect(words.stats, isEmpty);
    },
  );

  testWidgets(
    '320x640 2x official Home path: roles gloss stays on the next sense',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      _configureView(tester, size: const Size(320, 640), textScale: 2);
      await _pumpOfficialHome(
        tester,
        speech: const SilentSpeechService(),
        analytics: analytics,
        words: words,
      );
      await _tapVisible(tester, find.text(AppStrings.shiftAction));
      await _tapVisible(tester, find.text('換主角 わたし → かれ'));
      await _tapVisible(tester, find.text(AppStrings.shiftStart));
      expect(find.text(AppStrings.shiftIntroLead), findsOneWidget);
      await _finishIntro(tester);
      expect(find.text('わたしが かばんを もってきます'), findsOneWidget);
      await _tapVisible(tester, find.text(AppStrings.iReadUnprompted));
      await _tapVisible(tester, find.text(AppStrings.iReadIt));
      await _tapVisible(tester, find.text('もってくる'));
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      await _tapVisible(tester, find.text(AppStrings.shiftRolesHint));
      expect(find.text('「わたし」是做的人,「かばん」是帶過來的東西。'), findsOneWidget);
      await _tapVisible(tester, find.text('わたし').last);
      await _tapVisible(tester, find.text('かばん').last);
      await _tapVisible(tester, find.text(AppStrings.shiftRolesReady));
      await _tapVisible(tester, find.text(AppStrings.shiftContinue));
      await _show(tester, find.byType(TextField).last);
      await tester.enterText(find.byType(TextField).last, '自評用筆記');
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(AppStrings.shiftSenseReady));
      expect(find.text(AppStrings.shiftSenseOk), findsNothing);
      await _tapVisible(tester, find.text(AppStrings.shiftSenseOkAfterHint));
      expect(tester.takeException(), isNull);

      final logged = _grades(await analytics.all());
      final roles = logged.where(
        (a) => a.meta[AttemptMeta.evidence] == ShiftCheck.roles.name,
      );
      final sense = logged.where(
        (a) => a.meta[AttemptMeta.evidence] == ShiftCheck.sense.name,
      );
      expect(roles, hasLength(1));
      expect(roles.single.meta[AttemptMeta.prompted], isTrue);
      expect(sense, hasLength(1));
      expect(sense.single.meta[AttemptMeta.prompted], isTrue);
      expect(
        sense.single.meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
      expect(words.stats, isEmpty);
    },
  );

  testWidgets(
    'leaving practice during a slow sense write does not advance the beat',
    (tester) async {
      final analytics = _GatedAnalyticsLog();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    ShiftPracticeScreen.route(
                      drill,
                      clock: () => DateTime(2026, 9, 10, 10),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();

      analytics.senseGate = Completer<void>();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      analytics.senseGate!.complete();
      await tester.pumpAndSettle();

      final all = await analytics.all();
      final senses = _grades(all)
          .where((a) => a.meta[AttemptMeta.evidence] == ShiftCheck.sense.name);
      final sights = all.where(
        (a) => a.meta[AttemptMeta.sight] == ShiftSightKind.practice,
      );
      expect(senses, hasLength(1));
      expect(sights.map((a) => a.meta[AttemptMeta.beat]), [
        ShiftBeat.base.name,
      ]);
      expect(find.text('あおい うみ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving picker during reload does not throw', (tester) async {
    final analytics = _GatedFlushAnalyticsLog();
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _harness(analytics: analytics, child: ShiftFocusScreen()),
    );
    analytics.flushGate = Completer<void>();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    analytics.flushGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// Holds [record] on sense rows until [senseGate] completes — reproduces a
/// slow durable write while the learner can still tap confirm.
class _GatedAnalyticsLog implements AnalyticsLog {
  final List<Attempt> _items = [];
  Completer<void>? senseGate;

  @override
  int get unpersistedCount => 0;

  @override
  Future<void> record(Attempt attempt) async {
    _items.add(attempt);
    if (attempt.meta[AttemptMeta.evidence] == ShiftCheck.sense.name &&
        senseGate != null) {
      await senseGate!.future;
    }
  }

  @override
  Future<List<Attempt>> all() async => List.unmodifiable(_items);

  @override
  Future<int> count() async => _items.length;

  @override
  Future<void> flushPending() async {}
}

/// Holds [flushPending] until [flushGate] completes — reproduces a slow
/// authoritative read while the picker is left.
class _GatedFlushAnalyticsLog implements AnalyticsLog {
  final List<Attempt> _items = [];
  Completer<void>? flushGate;

  @override
  int get unpersistedCount => 0;

  @override
  Future<void> record(Attempt attempt) async => _items.add(attempt);

  @override
  Future<List<Attempt>> all() async => List.unmodifiable(_items);

  @override
  Future<int> count() async => _items.length;

  @override
  Future<void> flushPending() async {
    if (flushGate != null) await flushGate!.future;
  }
}

List<Attempt> _grades(List<Attempt> all) => [
  for (final attempt in all)
    if (attempt.meta[AttemptMeta.scored] != false &&
        (attempt.meta[AttemptMeta.evidence] == ShiftCheck.read.name ||
            attempt.meta[AttemptMeta.evidence] == ShiftCheck.verb.name ||
            attempt.meta[AttemptMeta.evidence] == ShiftCheck.roles.name ||
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
      ChangeNotifierProvider<ProgressPersistenceController>.value(
        value: ProgressPersistenceController(
          kanaFlush: () async {},
          kanjiFlush: () async {},
          wordFlush: () async {},
          analyticsFlush: analytics.flushPending,
        ),
      ),
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
  AnalyticsLog? analytics,
  WordProgressRepository? words,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await PreferencesService.create();
  final kana = await KanaProgressRepository.load(prefs);
  final kanji = await KanjiReadingRepository.load(prefs);
  final wordRepo = words ?? await WordProgressRepository.load(prefs);
  final analyticsLog = analytics ?? InMemoryAnalyticsLog();
  final recovery = recoveryForRepos(
    prefs: prefs,
    kana: kana,
    kanji: kanji,
    words: wordRepo,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: wordRepo),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            kanjiFlush: kanji.flushPending,
            wordFlush: wordRepo.flushPending,
            analyticsFlush: analyticsLog.flushPending,
          ),
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<SpeechService>.value(value: speech),
        Provider<AnalyticsLog>.value(value: analyticsLog),
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

Future<void> _finishIntro(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    final label = i < 3 ? AppStrings.shiftIntroNext : AppStrings.shiftIntroDone;
    await _tapVisible(tester, find.text(label));
  }
}

Future<void> _completeActionBeat(
  WidgetTester tester,
  ShiftSentence sentence, {
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
  await _tapVisible(tester, find.text(sentence.dictionaryForm));
  await _tapVisible(tester, find.text(AppStrings.shiftContinue));
  await _tapVisible(tester, find.text(sentence.actor).last);
  await _tapVisible(tester, find.text(sentence.item).last);
  await _tapVisible(tester, find.text(AppStrings.shiftRolesReady));
  await _tapVisible(tester, find.text(AppStrings.shiftContinue));
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
