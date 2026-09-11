// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/data/shift_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';

/// Composes the 換句 picker, optional next-day hold / confirm, and the
/// analytics shape for one self-grade or sighting.
///
/// Evidence stays per drill / beat / check. A correct self-grade never
/// masters a focus, a Satori chapter, or a sibling sentence. Free-text
/// explanations are not an input here — the screen must not send them.
///
/// Delayed confirm reuses the attempt stream. Hold / sight / read-support
/// metadata associate a reserved beat with a later sitting; they are not
/// a second ledger and do not write word / kana SRS.
///
/// Content tickets append curated [ShiftDrill] rows. Planning keys only on
/// [ShiftDrill.id] plus [ShiftBeat] / [ShiftCheck]; it does not generate
/// variants or read modifier / head copy. History UI stays here.
///
/// Pure logic: no `package:flutter/*` imports.
abstract final class ShiftSession {
  static List<ShiftFocus> focuses({List<ShiftDrill> drills = kShiftDrills}) {
    final grouped = <String, List<ShiftDrill>>{};
    final titles = <String, String>{};
    for (final drill in drills) {
      grouped.putIfAbsent(drill.focusId, () => <ShiftDrill>[]).add(drill);
      titles[drill.focusId] = drill.focusTitle;
    }
    return [
      for (final id in grouped.keys)
        ShiftFocus(id: id, title: titles[id]!, drills: grouped[id]!),
    ];
  }

  static ShiftDrill? drillById(
    String id, {
    List<ShiftDrill> drills = kShiftDrills,
  }) {
    for (final drill in drills) {
      if (drill.id == id) return drill;
    }
    return null;
  }

  static String itemId(ShiftDrill drill, ShiftBeat beat) =>
      'shift:${drill.id}:${beat.name}';

  /// Local calendar day. Delayed confirm is a date boundary, not elapsed hours.
  static String calendarDay(DateTime at) {
    final y = at.year.toString().padLeft(4, '0');
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime startOfDay(DateTime at) =>
      DateTime(at.year, at.month, at.day);

  static DateTime nextCalendarDate(DateTime at) =>
      startOfDay(at).add(const Duration(days: 1));

  static ShiftLane? parseLane(Object? raw) {
    if (raw is! String) return null;
    for (final lane in ShiftLane.values) {
      if (lane.name == raw) return lane;
    }
    return null;
  }

  static Attempt attempt({
    required ShiftDrill drill,
    required ShiftBeat beat,
    required ShiftCheck check,
    required bool prompted,
    required bool correct,
    required String sessionId,
    required DateTime at,
    String? sourceUrl,
    ShiftLane lane = ShiftLane.sameDay,
    String? readSupport,
  }) {
    final source = sourceUrl?.trim();
    return Attempt(
      ts: at.millisecondsSinceEpoch,
      itemId: itemId(drill, beat),
      itemType: ItemType.shift,
      mode: PracticeMode.shift.name,
      correct: correct,
      sessionId: sessionId,
      meta: {
        AttemptMeta.prompted: prompted,
        AttemptMeta.evidence: check.name,
        AttemptMeta.beat: beat.name,
        AttemptMeta.drill: drill.id,
        AttemptMeta.focus: drill.focusId,
        AttemptMeta.lane: lane.name,
        AttemptMeta.scored: true,
        if (check == ShiftCheck.sense &&
            readSupport != null &&
            readSupport.isNotEmpty)
          AttemptMeta.readSupport: readSupport,
        if (source != null && source.isNotEmpty) AttemptMeta.source: source,
      },
    );
  }

  /// Menu or practice display. Not a self-grade. A later sitting that finds
  /// this row is not a first-unseen confirm.
  static Attempt sighting({
    required ShiftDrill drill,
    required ShiftBeat beat,
    required String kind,
    required String sessionId,
    required DateTime at,
    ShiftLane lane = ShiftLane.sameDay,
    String? sourceUrl,
  }) {
    final source = sourceUrl?.trim();
    return Attempt(
      ts: at.millisecondsSinceEpoch,
      itemId: itemId(drill, beat),
      itemType: ItemType.shift,
      mode: PracticeMode.shift.name,
      correct: false,
      sessionId: sessionId,
      meta: {
        AttemptMeta.scored: false,
        AttemptMeta.sight: kind,
        AttemptMeta.lane: lane.name,
        AttemptMeta.beat: beat.name,
        AttemptMeta.drill: drill.id,
        AttemptMeta.focus: drill.focusId,
        if (source != null && source.isNotEmpty) AttemptMeta.source: source,
      },
    );
  }

  /// Reserves the shift beat for the next local calendar day. Does not
  /// display or sight the reserved sentence.
  static Attempt reservation({
    required ShiftDrill drill,
    required String sessionId,
    required DateTime at,
    String? sourceUrl,
  }) {
    final source = sourceUrl?.trim();
    return Attempt(
      ts: at.millisecondsSinceEpoch,
      itemId: itemId(drill, ShiftBeat.shift),
      itemType: ItemType.shift,
      mode: PracticeMode.shift.name,
      correct: false,
      sessionId: sessionId,
      meta: {
        AttemptMeta.scored: false,
        AttemptMeta.lane: ShiftLane.hold.name,
        AttemptMeta.holdUntil: calendarDay(nextCalendarDate(at)),
        AttemptMeta.beat: ShiftBeat.shift.name,
        AttemptMeta.drill: drill.id,
        AttemptMeta.focus: drill.focusId,
        if (source != null && source.isNotEmpty) AttemptMeta.source: source,
      },
    );
  }

  /// Transfer evidence is the sense check on the swapped sentence.
  /// Prompted and unprompted stay distinct; neither masters the focus.
  static bool isTransferSense(Attempt attempt) =>
      attempt.mode == PracticeMode.shift.name &&
      _beatOf(attempt) == ShiftBeat.shift &&
      attempt.meta[AttemptMeta.evidence] == ShiftCheck.sense.name &&
      attempt.meta[AttemptMeta.scored] != false;

  /// A self-grade — even an unprompted transfer success — must never mark
  /// the focus, a chapter, or sibling drills as mastered.
  static bool marksFocusMastered(Iterable<Attempt> attempts) {
    for (final _ in attempts) {
      return false;
    }
    return false;
  }

  /// Free-text (Chinese or kana) is a thinking pad, never a grade.
  /// An exact match of the curated meaning is still not understanding.
  static bool gradesExplanation(String learnerText, String meaning) {
    return learnerText.trim() == meaning.trim() && false;
  }

  static bool isShiftAttempt(Attempt attempt) =>
      attempt.mode == PracticeMode.shift.name ||
      attempt.itemType == ItemType.shift;

  static bool forDrill(Attempt attempt, String drillId) =>
      isShiftAttempt(attempt) && attempt.meta[AttemptMeta.drill] == drillId;

  /// Known display of this beat. Missing grades on legacy rows are
  /// [ShiftSight.unknown], not unseen.
  static ShiftSight sightOf(
    ShiftDrill drill,
    ShiftBeat beat, {
    Iterable<Attempt> attempts = const [],
  }) {
    final mine = [
      for (final attempt in attempts)
        if (forDrill(attempt, drill.id)) attempt,
    ];
    var sawBeat = false;
    var protocolKnown = false;
    for (final attempt in mine) {
      if (_hasProtocolMeta(attempt)) protocolKnown = true;
      if (_exposes(attempt, beat)) sawBeat = true;
    }
    if (sawBeat) return ShiftSight.seen;
    if (mine.isEmpty) return ShiftSight.unseen;
    if (protocolKnown) return ShiftSight.unseen;
    return ShiftSight.unknown;
  }

  static String? latestHoldUntil(Iterable<Attempt> attempts, String drillId) {
    Attempt? latest;
    for (final attempt in attempts) {
      if (!forDrill(attempt, drillId)) continue;
      if (attempt.meta[AttemptMeta.lane] != ShiftLane.hold.name) continue;
      final until = attempt.meta[AttemptMeta.holdUntil];
      if (until is! String || until.isEmpty) continue;
      if (latest == null || attempt.ts >= latest.ts) latest = attempt;
    }
    return latest?.meta[AttemptMeta.holdUntil] as String?;
  }

  static bool hasShiftGradeAfterHold({
    required Iterable<Attempt> attempts,
    required String drillId,
    required String holdUntil,
  }) {
    for (final attempt in attempts) {
      if (!forDrill(attempt, drillId)) continue;
      if (!_isGrade(attempt)) continue;
      if (_beatOf(attempt) != ShiftBeat.shift) continue;
      if (calendarDay(DateTime.fromMillisecondsSinceEpoch(attempt.ts))
              .compareTo(holdUntil) >=
          0) {
        return true;
      }
    }
    return false;
  }

  /// Optional hold never replaces same-session practice. Confirm is due only
  /// on a later local calendar day than the reservation.
  static ShiftPlan plan({
    required ShiftDrill drill,
    required DateTime now,
    Iterable<Attempt> attempts = const [],
    ShiftLane requested = ShiftLane.sameDay,
  }) {
    final today = calendarDay(now);
    final baseSight = sightOf(drill, ShiftBeat.base, attempts: attempts);
    final shiftSight = sightOf(drill, ShiftBeat.shift, attempts: attempts);
    final holdUntil = latestHoldUntil(attempts, drill.id);
    final holdPending = holdUntil != null && today.compareTo(holdUntil) < 0;
    final confirmDue = holdUntil != null && today.compareTo(holdUntil) >= 0;
    final confirmed =
        confirmDue &&
        hasShiftGradeAfterHold(
          attempts: attempts,
          drillId: drill.id,
          holdUntil: holdUntil,
        );
    final noUnseenVariant = shiftSight != ShiftSight.unseen;

    if (confirmDue && !confirmed) {
      return ShiftPlan(
        drill: drill,
        lane: ShiftLane.confirm,
        beats: const [ShiftBeat.shift],
        baseSight: baseSight,
        shiftSight: shiftSight,
        firstUnseen: shiftSight == ShiftSight.unseen,
        holdPending: false,
        confirmDue: true,
        noUnseenVariant: noUnseenVariant,
        holdUntil: holdUntil,
      );
    }

    if (holdPending && requested != ShiftLane.sameDay) {
      return ShiftPlan(
        drill: drill,
        lane: ShiftLane.hold,
        beats: const [ShiftBeat.base],
        baseSight: baseSight,
        shiftSight: shiftSight,
        firstUnseen: false,
        holdPending: true,
        confirmDue: false,
        noUnseenVariant: noUnseenVariant,
        holdUntil: holdUntil,
      );
    }

    if (requested == ShiftLane.hold && shiftSight == ShiftSight.unseen) {
      return ShiftPlan(
        drill: drill,
        lane: ShiftLane.hold,
        beats: const [ShiftBeat.base],
        baseSight: baseSight,
        shiftSight: shiftSight,
        firstUnseen: false,
        holdPending: true,
        confirmDue: false,
        noUnseenVariant: false,
        holdUntil: holdUntil ?? calendarDay(nextCalendarDate(now)),
      );
    }

    if (noUnseenVariant) {
      return ShiftPlan(
        drill: drill,
        lane: ShiftLane.review,
        beats: const [ShiftBeat.base, ShiftBeat.shift],
        baseSight: baseSight,
        shiftSight: shiftSight,
        firstUnseen: false,
        holdPending: holdPending,
        confirmDue: confirmDue && confirmed,
        noUnseenVariant: true,
        holdUntil: holdUntil,
      );
    }

    return ShiftPlan(
      drill: drill,
      lane: ShiftLane.sameDay,
      beats: const [ShiftBeat.base, ShiftBeat.shift],
      baseSight: baseSight,
      shiftSight: shiftSight,
      firstUnseen: false,
      holdPending: holdPending,
      confirmDue: false,
      noUnseenVariant: false,
      holdUntil: holdUntil,
    );
  }

  /// Sentence the picker may show. Reserved / first-confirm beats stay hidden.
  static String? pickerPreview(ShiftPlan plan) {
    if (plan.lane == ShiftLane.confirm) return null;
    return plan.drill.base.kana;
  }

  static List<ShiftSelfGrade> selfGrades(
    Iterable<Attempt> attempts, {
    String? drillId,
  }) {
    final rows = <ShiftSelfGrade>[];
    for (final attempt in attempts) {
      if (!isShiftAttempt(attempt)) continue;
      if (drillId != null && !forDrill(attempt, drillId)) continue;
      if (!_isGrade(attempt)) continue;
      final beat = _beatOf(attempt);
      final check = _checkOf(attempt);
      if (beat == null || check == null) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(attempt.ts);
      final support = attempt.meta[AttemptMeta.readSupport];
      rows.add(
        ShiftSelfGrade(
          at: at,
          day: calendarDay(at),
          drillId: attempt.meta[AttemptMeta.drill] as String? ?? '',
          beat: beat,
          check: check,
          prompted: attempt.meta[AttemptMeta.prompted] == true,
          correct: attempt.correct,
          readSupport: support is String ? support : null,
          lane: parseLane(attempt.meta[AttemptMeta.lane]),
        ),
      );
    }
    rows.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      return a.at.compareTo(b.at);
    });
    return rows;
  }

  static bool _hasProtocolMeta(Attempt attempt) =>
      attempt.meta.containsKey(AttemptMeta.sight) ||
      attempt.meta.containsKey(AttemptMeta.lane) ||
      attempt.meta.containsKey(AttemptMeta.holdUntil);

  static bool _exposes(Attempt attempt, ShiftBeat beat) {
    if (_beatOf(attempt) != beat) return false;
    final sight = attempt.meta[AttemptMeta.sight];
    if (sight == ShiftSightKind.preview || sight == ShiftSightKind.practice) {
      return true;
    }
    return _isGrade(attempt);
  }

  static bool _isGrade(Attempt attempt) {
    if (attempt.meta[AttemptMeta.scored] == false) return false;
    final evidence = attempt.meta[AttemptMeta.evidence];
    return evidence == ShiftCheck.read.name ||
        evidence == ShiftCheck.sense.name;
  }

  static ShiftBeat? _beatOf(Attempt attempt) {
    final raw = attempt.meta[AttemptMeta.beat];
    if (raw == ShiftBeat.base.name) return ShiftBeat.base;
    if (raw == ShiftBeat.shift.name) return ShiftBeat.shift;
    if (attempt.itemId.endsWith(':${ShiftBeat.base.name}')) {
      return ShiftBeat.base;
    }
    if (attempt.itemId.endsWith(':${ShiftBeat.shift.name}')) {
      return ShiftBeat.shift;
    }
    return null;
  }

  static ShiftCheck? _checkOf(Attempt attempt) {
    final raw = attempt.meta[AttemptMeta.evidence];
    if (raw == ShiftCheck.read.name) return ShiftCheck.read;
    if (raw == ShiftCheck.sense.name) return ShiftCheck.sense;
    return null;
  }
}
