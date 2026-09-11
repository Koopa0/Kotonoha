// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/data/shift_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';

/// Composes the 換句 picker and the analytics shape for one judgement.
///
/// Evidence stays per drill / beat / check. A correct self-grade or a
/// unique-structure hit never masters a focus, a Satori chapter, or a
/// sibling sentence. Free-text explanations are not an input here — the
/// screen must not send them as a grade.
///
/// Exposure / next-day reservation stay with #73. This type only names
/// which checks a drill emits so history can display them.
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

  /// Adjective drills keep read → sense. Action drills insert verb and
  /// roles after reading, still before free-text sense.
  static List<ShiftCheck> checksFor(ShiftDrill drill) {
    if (drill.isAction) {
      return const [
        ShiftCheck.read,
        ShiftCheck.verb,
        ShiftCheck.roles,
        ShiftCheck.sense,
      ];
    }
    return const [ShiftCheck.read, ShiftCheck.sense];
  }

  static String itemId(ShiftDrill drill, ShiftBeat beat) =>
      'shift:${drill.id}:${beat.name}';

  static Attempt attempt({
    required ShiftDrill drill,
    required ShiftBeat beat,
    required ShiftCheck check,
    required bool prompted,
    required bool correct,
    required String sessionId,
    required DateTime at,
    String? sourceUrl,
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
        if (source != null && source.isNotEmpty) AttemptMeta.source: source,
      },
    );
  }

  /// Unique dictionary-form answer. Teaching must have listed [picked]
  /// on the intro cards before the screen offers it.
  static bool gradesVerb(String picked, ShiftSentence sentence) {
    final answer = sentence.dictionaryForm.trim();
    return answer.isNotEmpty && picked.trim() == answer;
  }

  /// Unique who / what answer. Free Chinese is not an input.
  static bool gradesRoles({
    required String actor,
    required String item,
    required ShiftSentence sentence,
  }) {
    return actor.trim() == sentence.actor.trim() &&
        item.trim() == sentence.item.trim() &&
        sentence.actor.isNotEmpty &&
        sentence.item.isNotEmpty;
  }

  /// Transfer evidence is the sense check on the swapped sentence.
  /// Prompted and unprompted stay distinct; neither masters the focus.
  static bool isTransferSense(Attempt attempt) =>
      attempt.mode == PracticeMode.shift.name &&
      attempt.meta[AttemptMeta.beat] == ShiftBeat.shift.name &&
      attempt.meta[AttemptMeta.evidence] == ShiftCheck.sense.name;

  static bool isTransferVerb(Attempt attempt) =>
      attempt.mode == PracticeMode.shift.name &&
      attempt.meta[AttemptMeta.beat] == ShiftBeat.shift.name &&
      attempt.meta[AttemptMeta.evidence] == ShiftCheck.verb.name;

  static bool isTransferRoles(Attempt attempt) =>
      attempt.mode == PracticeMode.shift.name &&
      attempt.meta[AttemptMeta.beat] == ShiftBeat.shift.name &&
      attempt.meta[AttemptMeta.evidence] == ShiftCheck.roles.name;

  /// A self-grade or a structural hit — even an unprompted transfer
  /// success — must never mark the focus, a chapter, or sibling drills
  /// as mastered.
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
}
