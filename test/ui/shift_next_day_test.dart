// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> expand(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets(
    'Home hold: day 0 is base only and never leaks the reserved shift',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      var now = DateTime(2026, 9, 10, 10);
      await expand(tester);
      await _pumpHome(
        tester,
        analytics: analytics,
        words: words,
        clock: () => now,
      );

      expect(find.text(AppStrings.shiftAction), findsOneWidget);
      await tester.tap(find.text(AppStrings.shiftAction));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftHoldStart), findsOneWidget);
      expect(find.text('あおい うみ'), findsNothing);
      expect(find.text('藍色的海'), findsNothing);

      await tester.tap(find.text(AppStrings.shiftHoldStart));
      await tester.pumpAndSettle();
      expect(find.text('あおい そら'), findsOneWidget);
      expect(find.text(AppStrings.shiftHeldUntilTomorrow), findsWidgets);
      expect(find.text('あおい うみ'), findsNothing);
      expect(find.text('aoi umi'), findsNothing);
      expect(find.text('藍色的海'), findsNothing);

      await _completeBeat(tester, unprompted: true);
      expect(find.text(AppStrings.shiftClose), findsOneWidget);
      expect(
        find.textContaining(AppStrings.shiftHeldUntilTomorrow),
        findsWidgets,
      );
      expect(find.text('あおい うみ'), findsNothing);
      expect(
        find.text(
          AppStrings.shiftReadSelfGrade(prompted: false, correct: true),
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
        findsWidgets,
      );

      expect(words.stats, isEmpty);
      final reserved = (await analytics.all()).where(
        (a) =>
            a.meta[AttemptMeta.lane] == ShiftLane.hold.name &&
            a.meta[AttemptMeta.holdUntil] == '2026-09-11',
      );
      expect(reserved, isNotEmpty);

      await tester.tap(find.text(AppStrings.done));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftHeldUntilTomorrow), findsWidgets);
      expect(find.text(AppStrings.shiftHoldContinue), findsOneWidget);
      expect(find.text('あおい うみ'), findsNothing);

      await tester.tap(find.text(AppStrings.shiftHoldContinue));
      await tester.pumpAndSettle();
      expect(find.text('あおい そら'), findsOneWidget);
      expect(find.text('あおい うみ'), findsNothing);
      expect(find.text(AppStrings.shiftConfirmStart), findsNothing);
    },
  );

  testWidgets(
    'day 1 confirm shows the reserved shift without replaying answers',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      var now = DateTime(2026, 9, 10, 10);
      await analytics.record(
        ShiftSession.reservation(drill: drill, sessionId: 'h', at: now),
      );
      await analytics.record(
        ShiftSession.attempt(
          drill: drill,
          beat: ShiftBeat.base,
          check: ShiftCheck.read,
          prompted: false,
          correct: true,
          sessionId: 'h',
          at: now,
          lane: ShiftLane.hold,
        ),
      );
      await analytics.record(
        ShiftSession.attempt(
          drill: drill,
          beat: ShiftBeat.base,
          check: ShiftCheck.sense,
          prompted: true,
          correct: true,
          sessionId: 'h',
          at: now,
          lane: ShiftLane.hold,
          readSupport: ShiftReadSupport.independent,
        ),
      );

      now = DateTime(2026, 9, 11, 9);
      await expand(tester);
      await tester.pumpWidget(
        _harness(
          analytics: analytics,
          child: ShiftFocusScreen(
            clock: () => now,
            attempts: await analytics.all(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftConfirmStart), findsOneWidget);
      expect(find.text('あおい うみ'), findsNothing);
      expect(find.text('aoi umi'), findsNothing);
      expect(find.text('藍色的海'), findsNothing);
      expect(find.text('aoi sora'), findsNothing);
      expect(find.text('藍色的天空'), findsNothing);

      await tester.tap(find.text(AppStrings.shiftConfirmStart));
      await tester.pumpAndSettle();
      expect(find.text('あおい うみ'), findsOneWidget);
      expect(find.text(AppStrings.shiftFirstUnseen), findsWidgets);
      expect(find.text(AppStrings.shiftConfirmLead), findsOneWidget);
      expect(find.text('aoi umi'), findsNothing);
      expect(find.text('藍色的海'), findsNothing);
      expect(find.text('藍色的天空'), findsNothing);

      await tester.tap(find.text(AppStrings.recallHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iReadAfterHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.shiftReadSelfGrade(prompted: true, correct: true)),
        findsWidgets,
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
      expect(
        find.text(
          AppStrings.shiftReadSelfGrade(prompted: false, correct: true),
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
    },
  );

  testWidgets('exposure then exit is not first-unseen after restart', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    final day0 = DateTime(2026, 9, 10, 10);
    var now = day0;
    await analytics.record(
      ShiftSession.reservation(drill: drill, sessionId: 'h', at: day0),
    );
    now = DateTime(2026, 9, 11, 9);
    await expand(tester);
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(
          clock: () => now,
          attempts: await analytics.all(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftConfirmStart));
    await tester.pumpAndSettle();
    expect(find.text('あおい うみ'), findsOneWidget);
    expect(find.text(AppStrings.shiftFirstUnseen), findsWidgets);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(
          clock: () => now,
          attempts: await analytics.all(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftAlreadyShown), findsWidgets);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
    await tester.tap(find.text(AppStrings.shiftConfirmStart));
    await tester.pumpAndSettle();
    expect(find.text('あおい うみ'), findsOneWidget);
    expect(find.text(AppStrings.shiftAlreadyShown), findsWidgets);
    expect(find.text('aoi umi'), findsNothing);
  });

  testWidgets('no unseen variant is labeled 舊句複習, not a new item', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final drill = ShiftSession.drillById('na-adj-shizuka-noun')!;
    final at = DateTime(2026, 9, 10, 10);
    for (final beat in ShiftBeat.values) {
      for (final check in ShiftCheck.values) {
        await analytics.record(
          ShiftSession.attempt(
            drill: drill,
            beat: beat,
            check: check,
            prompted: false,
            correct: true,
            sessionId: 'full',
            at: at,
          ),
        );
      }
    }
    await expand(tester);
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(
          clock: () => DateTime(2026, 9, 11, 10),
          attempts: await analytics.all(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('しずかな + 名詞'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftReviewStart), findsOneWidget);
    expect(find.text(AppStrings.shiftReviewOnly), findsWidgets);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
    expect(find.text(AppStrings.shiftHoldStart), findsNothing);
    expect(find.text('しずかな まち'), findsNothing);

    await tester.tap(find.text(AppStrings.shiftReviewStart));
    await tester.pumpAndSettle();
    expect(find.text('しずかな へや'), findsOneWidget);
    expect(find.text(AppStrings.shiftReviewOnly), findsWidgets);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
  });

  testWidgets(
    'Home 換句: failed read after 讀得出來 does not claim independent support',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      await expand(tester);
      await _pumpHome(
        tester,
        analytics: analytics,
        words: words,
        clock: () => DateTime(2026, 9, 10, 10),
      );
      await tester.tap(find.text(AppStrings.shiftAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftStart));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.iCouldnt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseReady));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shiftSenseOk));
      await tester.pumpAndSettle();

      final first = ShiftSession.selfGrades(await analytics.all());
      expect(first, hasLength(2));
      expect(first[0].check, ShiftCheck.read);
      expect(first[0].correct, isFalse);
      expect(first[0].prompted, isFalse);
      expect(first[1].check, ShiftCheck.sense);
      expect(first[1].correct, isTrue);
      expect(first[1].prompted, isFalse);
      expect(first[1].readSupport, ShiftReadSupport.prompted);

      await _completeBeat(tester, unprompted: false);
      expect(find.text(AppStrings.shiftClose), findsOneWidget);
      expect(
        find.text(
          AppStrings.shiftReadSelfGrade(prompted: false, correct: false),
        ),
        findsWidgets,
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
      expect(words.stats, isEmpty);
    },
  );

  testWidgets('Home 換句: verified 讀得出來 keeps independent support on sense', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    await expand(tester);
    await _pumpHome(
      tester,
      analytics: analytics,
      words: words,
      clock: () => DateTime(2026, 9, 10, 10),
    );
    await tester.tap(find.text(AppStrings.shiftAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftStart));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftSenseReady));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftSenseOk));
    await tester.pumpAndSettle();

    final first = ShiftSession.selfGrades(await analytics.all());
    expect(first, hasLength(2));
    expect(first[0].correct, isTrue);
    expect(first[0].prompted, isFalse);
    expect(first[1].correct, isTrue);
    expect(first[1].readSupport, ShiftReadSupport.independent);

    await _completeBeat(tester, unprompted: true);
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
    expect(find.textContaining('讀音自行讀出'), findsWidgets);
    expect(words.stats, isEmpty);
  });

  testWidgets(
    'day 1 first confirm then More is already-seen review, not first-unseen',
    (tester) async {
      final analytics = InMemoryAnalyticsLog();
      final words = await WordProgressRepository.load();
      final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
      var now = DateTime(2026, 9, 10, 10);
      await analytics.record(
        ShiftSession.reservation(drill: drill, sessionId: 'h', at: now),
      );
      await analytics.record(
        ShiftSession.attempt(
          drill: drill,
          beat: ShiftBeat.base,
          check: ShiftCheck.read,
          prompted: false,
          correct: true,
          sessionId: 'h',
          at: now,
          lane: ShiftLane.hold,
        ),
      );
      await analytics.record(
        ShiftSession.attempt(
          drill: drill,
          beat: ShiftBeat.base,
          check: ShiftCheck.sense,
          prompted: true,
          correct: true,
          sessionId: 'h',
          at: now,
          lane: ShiftLane.hold,
          readSupport: ShiftReadSupport.independent,
        ),
      );

      now = DateTime(2026, 9, 11, 9);
      await expand(tester);
      await _pumpHome(
        tester,
        analytics: analytics,
        words: words,
        clock: () => now,
      );
      await tester.tap(find.text(AppStrings.shiftAction));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftConfirmStart), findsOneWidget);
      await tester.tap(find.text(AppStrings.shiftConfirmStart));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftFirstUnseen), findsWidgets);
      await _completeBeat(tester, unprompted: true);
      expect(find.text(AppStrings.practiceAgain), findsOneWidget);

      final afterConfirm = await analytics.all();
      expect(
        ShiftSession.sightOf(drill, ShiftBeat.shift, attempts: afterConfirm),
        ShiftSight.seen,
      );
      expect(
        afterConfirm.where(
          (a) =>
              a.meta[AttemptMeta.beat] == ShiftBeat.shift.name &&
              a.meta[AttemptMeta.scored] == true,
        ),
        hasLength(2),
      );

      await tester.tap(find.text(AppStrings.practiceAgain));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
      expect(find.text(AppStrings.shiftReviewOnly), findsWidgets);
      expect(find.text('あおい そら'), findsOneWidget);
      expect(words.stats, isEmpty);
    },
  );

  testWidgets('legacy base-only stays unknown across two Home picker visits', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final words = await WordProgressRepository.load();
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    await analytics.record(
      Attempt(
        ts: DateTime(2026, 9, 1).millisecondsSinceEpoch,
        itemId: ShiftSession.itemId(drill, ShiftBeat.base),
        itemType: ItemType.shift,
        mode: PracticeMode.shift.name,
        correct: true,
        sessionId: 'old',
        meta: const {
          AttemptMeta.prompted: true,
          AttemptMeta.evidence: 'read',
          AttemptMeta.beat: 'base',
          AttemptMeta.drill: 'i-adj-aoi-noun',
          AttemptMeta.focus: 'adj-mod',
        },
      ),
    );
    final now = DateTime(2026, 9, 11, 10);
    await expand(tester);
    await _pumpHome(
      tester,
      analytics: analytics,
      words: words,
      clock: () => now,
    );

    await tester.tap(find.text(AppStrings.shiftAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftSightUnknown), findsWidgets);
    expect(find.text(AppStrings.shiftReviewStart), findsOneWidget);
    expect(find.text(AppStrings.shiftHoldStart), findsNothing);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftAction));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftSightUnknown), findsWidgets);
    expect(find.text(AppStrings.shiftReviewStart), findsOneWidget);
    expect(find.text(AppStrings.shiftHoldStart), findsNothing);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
    expect(
      ShiftSession.sightOf(
        drill,
        ShiftBeat.shift,
        attempts: await analytics.all(),
      ),
      ShiftSight.unknown,
    );
  });

  testWidgets('legacy unknown sight is not treated as first-unseen', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    await analytics.record(
      Attempt(
        ts: DateTime(2026, 9, 1).millisecondsSinceEpoch,
        itemId: ShiftSession.itemId(drill, ShiftBeat.base),
        itemType: ItemType.shift,
        mode: PracticeMode.shift.name,
        correct: true,
        sessionId: 'old',
        meta: const {
          AttemptMeta.prompted: true,
          AttemptMeta.evidence: 'read',
          AttemptMeta.beat: 'base',
          AttemptMeta.drill: 'i-adj-aoi-noun',
          AttemptMeta.focus: 'adj-mod',
        },
      ),
    );
    await expand(tester);
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(
          clock: () => DateTime(2026, 9, 11),
          attempts: await analytics.all(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftSightUnknown), findsWidgets);
    expect(find.text(AppStrings.shiftReviewStart), findsOneWidget);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
    expect(find.text('あおい うみ'), findsNothing);

    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(
          clock: () => DateTime(2026, 9, 11),
          attempts: await analytics.all(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftSightUnknown), findsWidgets);
    expect(find.text(AppStrings.shiftReviewStart), findsOneWidget);
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
    expect(find.text('あおい うみ'), findsNothing);
  });

  testWidgets('day 1 confirm More uses fresh history as already shown review', (
    tester,
  ) async {
    final analytics = InMemoryAnalyticsLog();
    final drill = ShiftSession.drillById('i-adj-aoi-noun')!;
    var now = DateTime(2026, 9, 10, 10);
    await analytics.record(
      ShiftSession.reservation(drill: drill, sessionId: 'h', at: now),
    );
    now = DateTime(2026, 9, 11, 12);
    await expand(tester);
    await tester.pumpWidget(
      _harness(
        analytics: analytics,
        child: ShiftFocusScreen(clock: () => now),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.shiftConfirmStart));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftFirstUnseen), findsWidgets);

    await _completeBeat(tester, unprompted: false);
    expect(find.text(AppStrings.shiftClose), findsOneWidget);
    expect(find.text(AppStrings.shiftAlreadyShown), findsNothing);

    await tester.tap(find.text(AppStrings.practiceAgain));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.shiftFirstUnseen), findsNothing);
    expect(find.text(AppStrings.shiftReviewOnly), findsWidgets);
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
