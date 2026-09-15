// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_exporter.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_restorer.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/main.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:kotonoha/ui/learn/learn_screen.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #149 B9, the half the source guard cannot reach.
///
/// `pure_layer_imports_test` reads `lib/main.dart` as text and proves every
/// owner a screen looks up is *registered*. It cannot prove the screen then
/// receives the instance the composition root built, that there is only one of
/// each, or that the same one survives a route change. A second instance
/// created below the root would satisfy the source guard and still split the
/// app's truth in two: two `KanaProgressRepository` objects would each hold
/// half the learner's progress and neither would notify the other.
///
/// So this boots the real [bootstrap] and compares object identity: against the
/// instances handed in through the test seams, and across a push and a pop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every owner `bootstrap` registers, read from one context.
  Map<Type, Object> ownersAt(BuildContext context) => {
    KanaProgressRepository: context.read<KanaProgressRepository>(),
    KanjiReadingRepository: context.read<KanjiReadingRepository>(),
    WordProgressRepository: context.read<WordProgressRepository>(),
    PlacementCheckRepository: context.read<PlacementCheckRepository>(),
    TravelFocusRepository: context.read<TravelFocusRepository>(),
    ProgressPersistenceController: context
        .read<ProgressPersistenceController>(),
    ProgressRestoreRecoveryController: context
        .read<ProgressRestoreRecoveryController>(),
    SpeechService: context.read<SpeechService>(),
    AnalyticsLog: context.read<AnalyticsLog>(),
    ProgressSnapshotExporter: context.read<ProgressSnapshotExporter>(),
    ProgressSnapshotRestorer: context.read<ProgressSnapshotRestorer>(),
  };

  void expectSameOwners(
    Map<Type, Object> actual,
    Map<Type, Object> expected, {
    required String where,
  }) {
    expect(
      actual.keys.toSet(),
      expected.keys.toSet(),
      reason: 'a different set of owners was visible $where',
    );
    for (final type in expected.keys) {
      expect(
        identical(actual[type], expected[type]),
        isTrue,
        reason: '$type is a different instance $where',
      );
    }
  }

  testWidgets('every screen reads the one instance bootstrap built', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Known objects for the two seams, so identity can be checked against a
    // reference the test holds rather than only against itself.
    const speech = SilentSpeechService();
    final analytics = InMemoryAnalyticsLog();
    await tester.pumpWidget(
      await bootstrap(speech: speech, analytics: analytics),
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    final atHome = ownersAt(tester.element(find.byType(HomeScreen)));
    expect(atHome, hasLength(11));

    // The seams prove the root wired what it was given, not a fresh object.
    expect(identical(atHome[SpeechService], speech), isTrue);
    expect(identical(atHome[AnalyticsLog], analytics), isTrue);

    // A pushed route sees the same objects, not a second set.
    await tester.tap(find.text(AppStrings.learnHiragana));
    await tester.pumpAndSettle();
    expect(find.byType(LearnScreen), findsOneWidget);
    expectSameOwners(
      ownersAt(tester.element(find.byType(LearnScreen))),
      atHome,
      where: 'on a pushed route',
    );

    // And so does the home once the route is popped.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expectSameOwners(
      ownersAt(tester.element(find.byType(HomeScreen))),
      atHome,
      where: 'back on the home after a pop',
    );

    // A second, unrelated route resolves to the same owners too, so the
    // identity does not depend on which screen happens to look them up.
    await tester.tap(find.text(AppStrings.progress));
    await tester.pumpAndSettle();
    expect(find.byType(ProgressScreen), findsOneWidget);
    expectSameOwners(
      ownersAt(tester.element(find.byType(ProgressScreen))),
      atHome,
      where: 'on the 歩み route',
    );
  });

  testWidgets('a write on one route is visible to the next', (tester) async {
    // Identity is only worth asserting because it is what makes one owner's
    // write visible everywhere. This is that property, observed end to end.
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await bootstrap(
        speech: const SilentSpeechService(),
        analytics: InMemoryAnalyticsLog(),
      ),
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();

    final kana = tester
        .element(find.byType(HomeScreen))
        .read<KanaProgressRepository>();
    expect(kana.learnedUnitCount, 0);
    await kana.markUnitLearned('hira_row_0');
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.progress));
    await tester.pumpAndSettle();
    final onProgress = tester
        .element(find.byType(ProgressScreen))
        .read<KanaProgressRepository>();
    expect(identical(onProgress, kana), isTrue);
    expect(
      onProgress.learnedUnitCount,
      1,
      reason: 'a second instance would still read zero here',
    );
  });
}
