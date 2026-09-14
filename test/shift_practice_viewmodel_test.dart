// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/shift_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/shift/shift_practice_viewmodel.dart';

/// An analytics log whose durable write can be made to fail: the row stays
/// in memory, [unpersistedCount] counts it, and [flushPending] persists it
/// once writes work again.
class _FlakyAnalyticsLog implements AnalyticsLog {
  final List<Attempt> _rows = [];
  int _unpersisted = 0;
  bool failWrites = false;

  @override
  Future<void> record(Attempt attempt) async {
    _rows.add(attempt);
    if (failWrites) {
      _unpersisted++;
      throw StateError('disk full');
    }
  }

  @override
  Future<List<Attempt>> all() async => List.unmodifiable(_rows);

  @override
  Future<int> count() async => _rows.length;

  @override
  int get unpersistedCount => _unpersisted;

  @override
  Future<void> flushPending() async {
    if (failWrites) throw StateError('disk full');
    _unpersisted = 0;
  }
}

/// Reads the 換句 practice ViewModel's contract without pumping a widget or
/// any speech service: the phase walk per beat, the reservation and
/// sightings, every check's evidence (hints never leak another check), the
/// close and its history, and the durable-write state with its retry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);

  final noun = kShiftDrills.firstWhere((d) => !d.isAction);
  final action = kShiftDrills.firstWhere((d) => d.isAction);

  ({ShiftPracticeViewModel vm, _FlakyAnalyticsLog log}) makeVm(
    ShiftDrill drill, {
    ShiftLane lane = ShiftLane.sameDay,
    List<ShiftBeat>? beats,
    String? sourceUrl,
    _FlakyAnalyticsLog? log,
  }) {
    final analytics = log ?? _FlakyAnalyticsLog();
    final vm = ShiftPracticeViewModel(
      drill: drill,
      analytics: analytics,
      persistence: ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: () async {},
        analyticsFlush: analytics.flushPending,
      ),
      sessionId: 's1',
      sourceUrl: sourceUrl,
      lane: lane,
      beats: beats,
      clock: () => now,
    );
    return (vm: vm, log: analytics);
  }

  void skipIntro(ShiftPracticeViewModel vm) {
    while (vm.phase == ShiftPhase.intro) {
      vm.advanceIntro();
    }
  }

  Iterable<Attempt> grades(List<Attempt> all) =>
      all.where((a) => a.meta[AttemptMeta.scored] == true);

  Iterable<Attempt> sightings(List<Attempt> all) =>
      all.where((a) => a.meta.containsKey(AttemptMeta.sight));

  test('opens on the first beat, teaching first when there is an intro', () {
    final t = makeVm(noun);
    expect(t.vm.beat, ShiftBeat.base);
    expect(t.vm.beats, [ShiftBeat.base, ShiftBeat.shift]);
    expect(t.vm.beatIndex, 0);
    expect(t.vm.sentence, noun.base);
    expect(t.vm.say, noun.base.kana.replaceAll(' ', ''));
    expect(t.vm.isAction, isFalse);
    expect(
      t.vm.phase,
      noun.introduce.isEmpty ? ShiftPhase.readCommit : ShiftPhase.intro,
    );
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isUnsaved, isFalse);
    expect(t.vm.history, isEmpty);
    t.vm.dispose();
  });

  test('start writes one practice sighting for the first beat', () async {
    final t = makeVm(noun, sourceUrl: ' https://example.com/a ');
    await t.vm.start();
    final rows = await t.log.all();
    expect(rows, hasLength(1));
    final sight = rows.single;
    expect(sight.meta[AttemptMeta.sight], ShiftSightKind.practice);
    expect(sight.meta[AttemptMeta.beat], ShiftBeat.base.name);
    expect(sight.meta[AttemptMeta.drill], noun.id);
    expect(sight.meta[AttemptMeta.lane], ShiftLane.sameDay.name);
    expect(sight.meta[AttemptMeta.source], 'https://example.com/a');
    expect(sight.meta[AttemptMeta.scored], isFalse);
    expect(sight.sessionId, 's1');
    t.vm.dispose();
  });

  test('a hold lane reserves the shift before sighting the base', () async {
    final t = makeVm(noun, lane: ShiftLane.hold);
    await t.vm.start();
    final rows = await t.log.all();
    expect(rows, hasLength(2));
    expect(rows[0].meta[AttemptMeta.lane], ShiftLane.hold.name);
    expect(rows[0].meta.containsKey(AttemptMeta.holdUntil), isTrue);
    expect(rows[0].meta[AttemptMeta.beat], ShiftBeat.shift.name);
    expect(rows[1].meta[AttemptMeta.sight], ShiftSightKind.practice);
    expect(rows[1].meta[AttemptMeta.lane], ShiftLane.hold.name);
    t.vm.dispose();
  });

  test('a non-action drill walks read → sense per beat, then closes', () async {
    final t = makeVm(noun);
    await t.vm.start();
    skipIntro(t.vm);
    expect(t.vm.phase, ShiftPhase.readCommit);

    t.vm.commitRead(unprompted: true);
    expect(t.vm.phase, ShiftPhase.readGrade);
    expect(t.vm.readUnprompted, isTrue);
    t.vm.gradeRead(correct: true);
    expect(t.vm.phase, ShiftPhase.senseCommit);

    t.vm.commitSense(unprompted: true);
    expect(t.vm.phase, ShiftPhase.senseGrade);
    expect(t.vm.senseUnprompted, isTrue);
    await t.vm.gradeSense(correct: true);
    expect(t.vm.beat, ShiftBeat.shift);
    expect(t.vm.beatIndex, 1);
    expect(t.vm.phase, ShiftPhase.readCommit);
    expect(t.vm.readUnprompted, isFalse);
    expect(t.vm.senseUnprompted, isFalse);
    expect(t.vm.isSenseGrading, isFalse);

    t.vm.commitRead(unprompted: false);
    t.vm.gradeRead(correct: true);
    t.vm.commitSense(unprompted: false);
    await t.vm.gradeSense(correct: false);
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.history, hasLength(4));
    expect(t.vm.history.every((g) => g.drillId == noun.id), isTrue);

    final all = await t.log.all();
    expect(sightings(all).map((a) => a.meta[AttemptMeta.beat]), [
      ShiftBeat.base.name,
      ShiftBeat.shift.name,
    ]);
    final graded = grades(all).toList();
    expect(graded, hasLength(4));
    expect(graded.every((a) => a.mode == PracticeMode.shift.name), isTrue);
    expect(graded.every((a) => a.itemType == ItemType.shift), isTrue);
    // Base beat: unprompted read, independent sense.
    expect(graded[0].meta[AttemptMeta.evidence], ShiftCheck.read.name);
    expect(graded[0].meta[AttemptMeta.prompted], isFalse);
    expect(graded[0].correct, isTrue);
    expect(graded[1].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
    expect(graded[1].meta[AttemptMeta.prompted], isFalse);
    expect(
      graded[1].meta[AttemptMeta.readSupport],
      ShiftReadSupport.independent,
    );
    // Shift beat: hinted read, hinted sense, prompted read support.
    expect(graded[2].meta[AttemptMeta.beat], ShiftBeat.shift.name);
    expect(graded[2].meta[AttemptMeta.prompted], isTrue);
    expect(graded[3].meta[AttemptMeta.evidence], ShiftCheck.sense.name);
    expect(graded[3].meta[AttemptMeta.prompted], isTrue);
    expect(graded[3].correct, isFalse);
    expect(graded[3].meta[AttemptMeta.readSupport], ShiftReadSupport.prompted);
    t.vm.dispose();
  });

  test(
    'an action drill adds verb and roles; hints prompt only their check',
    () async {
      final t = makeVm(action, beats: const [ShiftBeat.base]);
      await t.vm.start();
      skipIntro(t.vm);
      final sentence = t.vm.sentence;
      expect(t.vm.isAction, isTrue);

      t.vm.commitRead(unprompted: true);
      t.vm.gradeRead(correct: true);
      expect(t.vm.phase, ShiftPhase.verbAsk);

      t.vm.hintVerb();
      expect(t.vm.verbPrompted, isTrue);
      final wrongVerb = sentence.verbChoices.firstWhere(
        (c) => !t.vm.isVerbCorrect(c),
      );
      expect(t.vm.isVerbCorrect(sentence.dictionaryForm), isTrue);
      t.vm.pickVerb(wrongVerb);
      expect(t.vm.pickedVerb, wrongVerb);
      expect(t.vm.phase, ShiftPhase.verbReveal);
      t.vm.pickVerb(sentence.dictionaryForm); // already picked
      expect(t.vm.pickedVerb, wrongVerb);
      t.vm.afterVerb();
      expect(t.vm.phase, ShiftPhase.rolesAsk);

      expect(t.vm.canLockRoles, isFalse);
      t.vm.lockRoles(); // nothing to lock yet
      expect(t.vm.phase, ShiftPhase.rolesAsk);
      t.vm.selectActor(sentence.actor);
      t.vm.selectItem(sentence.item);
      expect(t.vm.canLockRoles, isTrue);
      expect(t.vm.rolesPrompted, isFalse);
      t.vm.lockRoles();
      expect(t.vm.phase, ShiftPhase.rolesReveal);
      t.vm.afterRoles();
      expect(t.vm.phase, ShiftPhase.senseCommit);

      // Roles were answered unaided and un-hinted: the sense may be
      // independent.
      t.vm.commitSense(unprompted: true);
      expect(t.vm.senseUnprompted, isTrue);
      await t.vm.gradeSense(correct: true);
      expect(t.vm.isFinished, isTrue);

      final graded = grades(await t.log.all()).toList();
      expect(graded.map((a) => a.meta[AttemptMeta.evidence]), [
        ShiftCheck.read.name,
        ShiftCheck.verb.name,
        ShiftCheck.roles.name,
        ShiftCheck.sense.name,
      ]);
      expect(graded[1].meta[AttemptMeta.prompted], isTrue); // the verb hint
      expect(graded[1].correct, isFalse);
      expect(graded[2].meta[AttemptMeta.prompted], isFalse);
      expect(graded[2].correct, isTrue);
      expect(graded[3].meta[AttemptMeta.prompted], isFalse);
      expect(
        graded[3].meta[AttemptMeta.readSupport],
        ShiftReadSupport.independent,
      );
      t.vm.dispose();
    },
  );

  test('a roles hint or a revealed roles answer prompts the sense', () async {
    for (final viaHint in [true, false]) {
      final t = makeVm(action, beats: const [ShiftBeat.base]);
      skipIntro(t.vm);
      final sentence = t.vm.sentence;
      t.vm.commitRead(unprompted: true);
      t.vm.gradeRead(correct: false); // a missed read: prompted support
      t.vm.pickVerb(sentence.dictionaryForm);
      t.vm.afterVerb();
      if (viaHint) {
        t.vm.hintRoles();
        t.vm.selectActor(sentence.actor);
        t.vm.selectItem(sentence.item);
      } else {
        final wrongActor = sentence.actorChoices.firstWhere(
          (c) => c != sentence.actor,
        );
        t.vm.selectActor(wrongActor);
        t.vm.selectItem(sentence.item);
      }
      t.vm.lockRoles();
      t.vm.afterRoles();
      t.vm.commitSense(unprompted: true);
      expect(t.vm.senseUnprompted, isFalse, reason: 'viaHint=$viaHint');
      await t.vm.gradeSense(correct: true);
      final sense = grades(await t.log.all()).last;
      expect(sense.meta[AttemptMeta.evidence], ShiftCheck.sense.name);
      expect(sense.meta[AttemptMeta.prompted], isTrue);
      expect(sense.meta[AttemptMeta.readSupport], ShiftReadSupport.prompted);
      t.vm.dispose();
    }
  });

  test('commands off their phase are ignored', () async {
    final t = makeVm(noun);
    skipIntro(t.vm);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.gradeRead(correct: true);
    t.vm.commitSense(unprompted: true);
    await t.vm.gradeSense(correct: true);
    t.vm.hintVerb();
    t.vm.pickVerb('x');
    t.vm.afterVerb();
    t.vm.hintRoles();
    t.vm.selectActor('x');
    t.vm.lockRoles();
    t.vm.afterRoles();
    t.vm.advanceIntro();
    expect(t.vm.phase, ShiftPhase.readCommit);
    expect(notifications, 0);
    expect(grades(await t.log.all()), isEmpty);
    t.vm.dispose();
  });

  test('a failed durable write stays honest and retry flushes it', () async {
    final log = _FlakyAnalyticsLog()..failWrites = true;
    final t = makeVm(noun, log: log);
    await t.vm.start();
    expect(t.vm.isUnsaved, isTrue);
    expect(await log.all(), hasLength(1)); // memory retains the row

    log.failWrites = false;
    var sawRetrying = false;
    t.vm.addListener(() => sawRetrying |= t.vm.isRetrying);
    await t.vm.retryPersist();
    expect(sawRetrying, isTrue);
    expect(t.vm.isRetrying, isFalse);
    expect(t.vm.isUnsaved, isFalse);
    t.vm.dispose();
  });
}
