// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// P0-B — the persistence banner surface as a widget: the honest copy per
// StoreHealth, coalescing + runtime priority, session acknowledgement, and the
// accessibility / layout contract (live region, 48px retry target, no overflow
// at width 360 + TextScaler 2.0). The controller is driven directly so each
// surface state is reached deterministically.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/persistence_banner.dart';
import 'package:provider/provider.dart';

import '../services/fake_preferences_service.dart';
import '../support/restore_recovery_test_support.dart';

void main() {
  ProgressPersistenceController controllerWith({
    List<StoreHealth> health = const [],
    Future<void> Function()? kanaFlush,
  }) {
    return ProgressPersistenceController(
      kanaFlush: kanaFlush ?? () async {},
      kanjiFlush: () async {},
      wordFlush: () async {},
      health: health,
    );
  }

  Future<void> pumpBanner(
    WidgetTester tester,
    ProgressPersistenceController controller, {
    Size size = const Size(360, 720),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recovery = await idleRestoreRecovery();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: controller,
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: const Scaffold(
                body: PersistenceBanner(child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // A pending failure, reached the same way production does: a tracked write
  // that errors. Settled with a pump so the controller's handler runs.
  Future<void> failKana(
    WidgetTester tester,
    ProgressPersistenceController controller,
  ) async {
    controller.trackKana(Future<void>.error(const StoreWriteFailure('kana')));
    await tester.pump(); // deliver the error → notifyListeners
    await tester.pump(); // rebuild with the banner
  }

  group('recovery copy is honest and distinct per StoreHealth', () {
    final cases = <StoreHealth, String>{
      StoreHealth.salvaged: AppStrings.persistRecoverySalvaged,
      StoreHealth.restored: AppStrings.persistRecoveryRestored,
      StoreHealth.preservationPending:
          AppStrings.persistRecoveryPreservationPending,
      StoreHealth.recoveryRequired: AppStrings.persistRecoveryRecoveryRequired,
    };
    for (final entry in cases.entries) {
      testWidgets('${entry.key.name} shows its own line', (tester) async {
        await pumpBanner(tester, controllerWith(health: [entry.key]));
        expect(find.text(entry.value), findsOneWidget);
        // Never another state's line.
        for (final other in cases.values) {
          if (other != entry.value) {
            expect(find.text(other), findsNothing);
          }
        }
      });
    }
  });

  testWidgets('empty / loaded stores stay silent', (tester) async {
    await pumpBanner(
      tester,
      controllerWith(health: [StoreHealth.loaded, StoreHealth.empty]),
    );
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('multiple abnormal stores coalesce to the most severe line', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      controllerWith(
        health: [StoreHealth.salvaged, StoreHealth.recoveryRequired],
      ),
    );
    // One banner, and it speaks the most severe (recoveryRequired), not salvaged.
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(
      find.text(AppStrings.persistRecoveryRecoveryRequired),
      findsOneWidget,
    );
    expect(find.text(AppStrings.persistRecoverySalvaged), findsNothing);
  });

  testWidgets('a runtime write failure outranks a recovery notice', (
    tester,
  ) async {
    final controller = controllerWith(health: [StoreHealth.salvaged]);
    await pumpBanner(tester, controller);
    expect(find.text(AppStrings.persistRecoverySalvaged), findsOneWidget);

    await failKana(tester, controller);
    expect(controller.hasWriteFailure, isTrue); // controller detected it
    // Failure copy wins; the recovery line yields and only one banner shows.
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
    expect(find.text(AppStrings.persistRecoverySalvaged), findsNothing);
  });

  testWidgets('a recovery notice is dismissible for the session', (
    tester,
  ) async {
    await pumpBanner(tester, controllerWith(health: [StoreHealth.restored]));
    expect(find.text(AppStrings.persistRecoveryRestored), findsOneWidget);
    await tester.tap(find.text(AppStrings.persistAck));
    await tester.pump();
    expect(find.text(AppStrings.persistRecoveryRestored), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('the failure surface has a live region for screen readers', (
    tester,
  ) async {
    final controller = controllerWith();
    await pumpBanner(tester, controller);
    await failKana(tester, controller);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.liveRegion ?? false),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the retry action meets the 48px minimum hit target', (
    tester,
  ) async {
    final controller = controllerWith();
    await pumpBanner(tester, controller);
    await failKana(tester, controller);
    final size = tester.getSize(
      find.widgetWithText(TextButton, AppStrings.persistRetry),
    );
    expect(size.height, greaterThanOrEqualTo(48.0));
    expect(size.width, greaterThanOrEqualTo(48.0));
  });

  testWidgets('does not overflow at width 360 with TextScaler 2.0', (
    tester,
  ) async {
    final controller = controllerWith();
    // The default surface is already 360 wide — exercise it at TextScaler 2.0.
    await pumpBanner(tester, controller, textScale: 2);
    await failKana(tester, controller);
    // A RenderFlex overflow throws during layout; none should be captured.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the failure surface survives a route change', (tester) async {
    final controller = controllerWith();
    final recovery = await idleRestoreRecovery();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: controller,
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
        ],
        // The banner lives in MaterialApp.builder, above the navigator — just
        // as production wires it — so it outlives the route that caused it.
        child: MaterialApp(
          builder: (context, child) =>
              PersistenceBanner(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('second route')),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await failKana(tester, controller);
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('second route'), findsOneWidget);
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
  });

  testWidgets('a lifecycle hide drains pending writes (best-effort)', (
    tester,
  ) async {
    var flushes = 0;
    final controller = ProgressPersistenceController(
      kanaFlush: () async {
        flushes++;
      },
      kanjiFlush: () async {},
      wordFlush: () async {},
    );
    await pumpBanner(tester, controller);
    // The OS backgrounds the app: resumed → … → paused fires onHide/onPause,
    // which the banner host wires to drain(). Best-effort, never a guarantee.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(flushes, greaterThanOrEqualTo(1));
  });

  testWidgets('a lifecycle drain whose flush fails reaches the owner', (
    tester,
  ) async {
    final controller = ProgressPersistenceController(
      kanaFlush: () async {
        throw const StoreWriteFailure('kana');
      },
      kanjiFlush: () async {},
      wordFlush: () async {},
    );
    await pumpBanner(tester, controller);
    // Backgrounding drains best-effort; the flush fails and the owner catches
    // it (the banner then shows on the next foreground — a paused app renders
    // no frames, which is why the surface is verified via the owner here and
    // via a live tracked write in the tests above).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(controller.hasWriteFailure, isTrue);
  });

  // --- P0-B Acceptance Repair #1 — behaviour that was red on the first cut. ---

  testWidgets('the top inset is consumed once, not twice', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.reset);
    final controller = controllerWith();
    final recovery = await idleRestoreRecovery();
    // Production-shaped: banner in MaterialApp.builder; the route below has its
    // own SafeArea and a top-aligned marker.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: controller,
          ),
          ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
            value: recovery,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              PersistenceBanner(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(
            body: SafeArea(
              child: Align(alignment: Alignment.topLeft, child: Text('marker')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // No banner → the route keeps its normal safe area (marker below the inset).
    expect(tester.getTopLeft(find.text('marker')).dy, 40);

    await failKana(tester, controller);
    final bannerBottom = tester.getBottomLeft(find.byType(MaterialBanner)).dy;
    final markerTop = tester.getTopLeft(find.text('marker')).dy;
    // The route must NOT re-consume the top inset the banner already cleared.
    expect(markerTop, moreOrLessEquals(bannerBottom, epsilon: 1));
  });

  testWidgets('the retry action is not a live button while retrying', (
    tester,
  ) async {
    final gate = Completer<void>();
    final controller = ProgressPersistenceController(
      kanaFlush: () => gate.future, // the retry parks here
      kanjiFlush: () async {},
      wordFlush: () async {},
    );
    await pumpBanner(tester, controller);
    controller.trackKana(Future<void>.error(const StoreWriteFailure('kana')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(TextButton)); // start the retry
    await tester.pump();
    await tester.pump();
    // A second tap must not be silently swallowed by a still-enabled button.
    expect(tester.widget<TextButton>(find.byType(TextButton)).enabled, isFalse);
    // A quiet "retrying" state, and the failure surface itself stays up.
    expect(find.text(AppStrings.persistRetrying), findsOneWidget);
    expect(find.text(AppStrings.persistFailedLine), findsOneWidget);
    gate.complete();
    await tester.pump();
    await tester.pump();
    // The retry succeeded, so the surface clears.
    expect(find.text(AppStrings.persistFailedLine), findsNothing);
  });

  testWidgets('the retry action meets 4.5:1 contrast, enabled and disabled', (
    tester,
  ) async {
    final controller = controllerWith();
    await pumpBanner(tester, controller);
    await failKana(tester, controller);
    final button = tester.widget<TextButton>(find.byType(TextButton));
    final enabledFg = button.style!.foregroundColor!.resolve(<WidgetState>{})!;
    expect(_contrast(enabledFg, AppColors.card), greaterThanOrEqualTo(4.5));
    // The retrying/disabled label stays readable too.
    final disabledFg = button.style!.foregroundColor!.resolve(<WidgetState>{
      WidgetState.disabled,
    })!;
    expect(_contrast(disabledFg, AppColors.card), greaterThanOrEqualTo(4.5));
  });

  for (final health in const [
    StoreHealth.salvaged,
    StoreHealth.restored,
    StoreHealth.preservationPending,
    StoreHealth.recoveryRequired,
  ]) {
    testWidgets(
      '${health.name} recovery copy fits width 360 at TextScaler 2.0',
      (tester) async {
        await pumpBanner(
          tester,
          controllerWith(health: [health]),
          textScale: 2,
        );
        expect(tester.takeException(), isNull); // no overflow
        expect(find.byType(MaterialBanner), findsOneWidget);
        // The dismiss action is present and reachable.
        expect(find.text(AppStrings.persistAck), findsOneWidget);
      },
    );
  }

  Future<(ProgressRestoreRecoveryController, FakePreferencesService)>
  blockingRecoverySetup() async {
    final fake = FakePreferencesService();
    final seeded = await KanaProgressRepository.load(fake);
    await seeded.markUnitLearned('keep_me');
    final before = {
      for (final key in RestoreJournalStores.all) key: fake.durable[key],
    };
    fake.durable[ProgressSnapshotRepository.kanaStatsStore] =
        '{"partial":true}';
    fake.seed(
      ProgressRestoreJournal.journalKey,
      jsonEncode(<String, Object?>{
        'phase': RestoreJournalPhase.applying.name,
        'rollback': before,
        'staging': <String, String>{
          for (final key in RestoreJournalStores.all) key: '{"partial":true}',
        },
      }),
    );
    fake.failWriteOnAttempt[ProgressSnapshotRepository.learnedUnitsStore] = {2};
    await ProgressRestoreJournal.recoverIfNeeded(fake);
    final kana = await KanaProgressRepository.load(fake);
    final kanji = await KanjiReadingRepository.load(fake);
    final words = await WordProgressRepository.load(fake);
    final recovery = ProgressRestoreRecoveryController(
      prefs: fake,
      kana: kana,
      kanji: kanji,
      words: words,
      needsRecovery: true,
    );
    return (recovery, fake);
  }

  test('restore journal retry success clears needsRecovery', () async {
    final (recovery, fake) = await blockingRecoverySetup();
    expect(recovery.needsRecovery, isTrue);

    fake.failWriteOnAttempt.clear();
    await recovery.retry();

    expect(recovery.needsRecovery, isFalse);
  });

  test('restore journal retry failure keeps needsRecovery', () async {
    final (recovery, fake) = await blockingRecoverySetup();
    fake.failWriteOnAttempt[ProgressSnapshotRepository.learnedUnitsStore] = {3};

    await recovery.retry();

    expect(recovery.needsRecovery, isTrue);
  });

  test('recovery copy avoids proportion claims and expiring present tense', () {
    // salvaged must not assert a proportion, but still note the raw is kept.
    expect(AppStrings.persistRecoverySalvaged, isNot(contains('一小部分')));
    expect(AppStrings.persistRecoverySalvaged, contains('原始'));
    // preservationPending must be a startup-time fact, not a present claim a
    // later successful write would silently falsify.
    expect(AppStrings.persistRecoveryPreservationPending, contains('啟動'));
  });
}

double _lin(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// WCAG relative-contrast ratio between two opaque colours (1..21).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
