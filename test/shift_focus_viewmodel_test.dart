// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/shift_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/shift/shift_focus_viewmodel.dart';

/// Reads the 換句 picker ViewModel's contract without pumping a widget: the
/// catalogue and the named drill, plans against the attempt stream, the
/// one-per-visit preview sightings, reload / refresh from the authoritative
/// stream, and the retry state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);
  final first = kShiftDrills.first;

  ({ShiftFocusViewModel vm, InMemoryAnalyticsLog log}) makeVm({
    List<Attempt>? attempts,
    List<ShiftDrill>? drills,
    InMemoryAnalyticsLog? log,
  }) {
    final analytics = log ?? InMemoryAnalyticsLog();
    final vm = ShiftFocusViewModel(
      analytics: analytics,
      persistence: ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: () async {},
        analyticsFlush: analytics.flushPending,
      ),
      drills: drills,
      attempts: attempts,
      pickerSessionId: 'picker',
      clock: () => now,
    );
    return (vm: vm, log: analytics);
  }

  test('opens on the curated slice with the first drill named', () {
    final t = makeVm();
    expect(t.vm.drills, isNotEmpty);
    expect(t.vm.focuses, isNotEmpty);
    expect(
      t.vm.focuses.expand((f) => f.drills).map((d) => d.id),
      t.vm.drills.map((d) => d.id),
    );
    expect(t.vm.selectedId, first.id);
    expect(t.vm.selected, first);
    expect(t.vm.attempts, isEmpty);
    expect(t.vm.isUnsaved, isFalse);
    expect(t.vm.isRetrying, isFalse);
    final plan = t.vm.selectedPlan!;
    expect(plan.drill, first);
    expect(plan.lane, ShiftLane.sameDay);
    expect(t.vm.holdPlan!.lane, ShiftLane.hold);
    expect(
      t.vm.showHold,
      t.vm.holdPlan!.shiftSight == ShiftSight.unseen || plan.holdPending,
    );
    t.vm.dispose();
  });

  test('naming a drill re-plans; naming it again is silent', () {
    final t = makeVm();
    final other = t.vm.drills[1];
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.select(other.id);
    expect(t.vm.selected, other);
    expect(t.vm.selectedPlan!.drill, other);
    t.vm.select(other.id);
    expect(notifications, 1);
    t.vm.dispose();
  });

  test('a narrowed catalogue plans only its own drills', () {
    final t = makeVm(drills: [kShiftDrills[1]]);
    expect(t.vm.drills, [kShiftDrills[1]]);
    expect(t.vm.selectedId, kShiftDrills[1].id);
    expect(t.vm.focuses.expand((f) => f.drills), [kShiftDrills[1]]);
    t.vm.dispose();
  });

  test('the first visit previews every drill once, never a confirm', () async {
    // A hold reserved yesterday is due today: its confirm stays hidden.
    final reservation = ShiftSession.reservation(
      drill: first,
      sessionId: 'earlier',
      at: now.subtract(const Duration(days: 1)),
    );
    final t = makeVm(attempts: [reservation]);
    expect(t.vm.selectedPlan!.lane, ShiftLane.confirm);
    expect(ShiftSession.pickerPreview(t.vm.selectedPlan!), isNull);

    await t.vm.load();
    Future<List<Attempt>> previews() async => [
      for (final a in await t.log.all())
        if (a.meta[AttemptMeta.sight] == ShiftSightKind.preview) a,
    ];
    final shown = (await previews())
        .map((a) => a.meta[AttemptMeta.drill])
        .toSet();
    expect(shown, hasLength(t.vm.drills.length - 1));
    expect(shown, isNot(contains(first.id)));
    for (final a in await previews()) {
      expect(a.sessionId, 'picker');
      expect(a.meta[AttemptMeta.scored], isFalse);
    }

    await t.vm.load(); // a second pass never re-sights a drill
    expect(await previews(), hasLength(t.vm.drills.length - 1));
    t.vm.dispose();
  });

  test('a fresh stream previews the base of every drill', () async {
    final t = makeVm(attempts: const []);
    await t.vm.load();
    final rows = await t.log.all();
    expect(rows, hasLength(t.vm.drills.length));
    expect(
      rows.every((a) => a.meta[AttemptMeta.sight] == ShiftSightKind.preview),
      isTrue,
    );
    expect(
      rows.every((a) => a.meta[AttemptMeta.beat] == ShiftBeat.base.name),
      isTrue,
    );
    t.vm.dispose();
  });

  test('reload reads the authoritative stream and its self-grades', () async {
    final log = InMemoryAnalyticsLog();
    final t = makeVm(log: log);
    expect(t.vm.selfGradesFor(first.id), isEmpty);
    await log.record(
      ShiftSession.attempt(
        drill: first,
        beat: ShiftBeat.base,
        check: ShiftCheck.read,
        prompted: false,
        correct: true,
        sessionId: 'practice',
        at: now,
      ),
    );
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    await t.vm.load(); // not seeded → reads the log (and previews)
    expect(
      t.vm.attempts.where((a) => a.meta[AttemptMeta.scored] == true),
      hasLength(1),
    );
    final grade = t.vm.selfGradesFor(first.id).single;
    expect(grade.check, ShiftCheck.read);
    expect(grade.correct, isTrue);
    expect(grade.prompted, isFalse);
    expect(notifications, greaterThan(0));

    await log.record(
      ShiftSession.attempt(
        drill: first,
        beat: ShiftBeat.base,
        check: ShiftCheck.sense,
        prompted: true,
        correct: false,
        sessionId: 'practice',
        at: now.add(const Duration(minutes: 1)),
      ),
    );
    final refreshed = await t.vm.refreshAttempts();
    expect(
      refreshed.where((a) => a.meta[AttemptMeta.scored] == true),
      hasLength(2),
    );
    expect(t.vm.selfGradesFor(first.id), hasLength(2));
    t.vm.dispose();
  });

  test('retry runs once at a time and settles', () async {
    final t = makeVm();
    var sawRetrying = false;
    t.vm.addListener(() => sawRetrying |= t.vm.isRetrying);
    await t.vm.retryPersist();
    expect(sawRetrying, isTrue);
    expect(t.vm.isRetrying, isFalse);
    expect(t.vm.isUnsaved, isFalse);
    t.vm.dispose();
  });
}
