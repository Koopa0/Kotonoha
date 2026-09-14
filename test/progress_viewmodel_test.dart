// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/progress/progress_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the 歩み ViewModel's contract without pumping a widget: coverage
/// as a map (never a grade), the present-tense status counts, the
/// hard-gated observations, and that the map follows the kana owner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 6);

  Future<
    ({
      ProgressViewModel vm,
      KanaProgressRepository kana,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm() async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final vm = ProgressViewModel(kana: kana, analytics: log);
    return (vm: vm, kana: kana, log: log);
  }

  test('a cold start covers nothing and has observed nothing yet', () async {
    final t = await makeVm();
    expect(t.vm.seenCount, 0);
    expect(t.vm.totalCount, t.kana.allKana.length);
    expect(t.vm.coverage, 0);
    expect(t.vm.countWithStatus(KanaStatus.unseen), t.vm.totalCount);
    expect(t.vm.countWithStatus(KanaStatus.strong), 0);
    expect(t.vm.observations, isEmpty);
    expect(t.vm.hasObserved, isFalse);
    t.vm.dispose();
  });

  test('met kana move coverage and the status counts', () async {
    final t = await makeVm();
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    // 4 strong (5 correct each) + 1 clearly weak (3 wrong) → 5 kana met.
    for (final k in kHiraganaGojuon.take(4)) {
      for (var i = 0; i < 5; i++) {
        await t.kana.recordAnswer(k, correct: true, at: at, latencyMs: 300);
      }
    }
    for (var i = 0; i < 3; i++) {
      await t.kana.recordAnswer(kHiraganaGojuon[4], correct: false, at: at);
    }
    expect(t.vm.seenCount, 5);
    expect(t.vm.coverage, closeTo(5 / t.vm.totalCount, 1e-9));
    expect(t.vm.countWithStatus(KanaStatus.strong), 4);
    expect(t.vm.countWithStatus(KanaStatus.weak), 1);
    expect(t.vm.countWithStatus(KanaStatus.unseen), t.vm.totalCount - 5);
    expect(notifications, greaterThan(0));
    t.vm.dispose();
  });

  test('observing an empty stream says nothing, honestly', () async {
    final t = await makeVm();
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    await t.vm.observe();
    expect(t.vm.hasObserved, isTrue);
    expect(t.vm.observations, isEmpty);
    expect(notifications, 1);
    t.vm.dispose();
  });
}
