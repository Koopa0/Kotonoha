// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';

/// Day-to-day cursor for a retained travel plan.
///
/// Picks at most one scene for the Home next step and never invents material
/// outside that scene. Dates are a weak tie-break only — they never declare
/// the plan finished and never count down.
abstract final class TravelPrep {
  /// Today's one kana reinforcement is still outstanding when compose can
  /// actually serve a due kana and the Home travel path has not already
  /// run that boost on this calendar day.
  static bool needsKanaBoost({
    required TravelFocusPlan plan,
    required int dueKanaCount,
    required DateTime now,
  }) {
    if (!plan.isActive || dueKanaCount <= 0) return false;
    return !TravelFocusPlan.sameDay(plan.kanaBoostOn, now);
  }

  /// The scene Home should continue now, or null when every selected scene
  /// already had its short Home step today — a pause, not completion.
  static TravelSceneId? pickScene(TravelFocusPlan plan, DateTime now) {
    if (!plan.isActive) return null;
    final today = TravelFocusPlan.dayOf(now);
    final pending = [
      for (final focus in plan.focuses)
        if (!TravelFocusPlan.sameDay(plan.servedOn[focus.scene], today)) focus,
    ];
    if (pending.isEmpty) return null;
    pending.sort((a, b) {
      final served = _servedOrder(plan, a.scene, b.scene);
      if (served != 0) return served;
      return _dateTieBreak(a, b, today);
    });
    return pending.first.scene;
  }

  /// Unseen readable first, then due already-seen, then a listen on seen
  /// items. An unreadable scene points at the missing kana — never pads
  /// from another scene or the global pool.
  static TravelPrepKind kindFor(TravelSceneView view) {
    if (view.unreadReadable.isNotEmpty) return TravelPrepKind.meet;
    if (view.dueReadable.isNotEmpty) return TravelPrepKind.recall;
    if (view.seenReadable.isNotEmpty) return TravelPrepKind.listen;
    return TravelPrepKind.learnKana;
  }

  static int _servedOrder(
    TravelFocusPlan plan,
    TravelSceneId a,
    TravelSceneId b,
  ) {
    final sa = plan.servedOn[a];
    final sb = plan.servedOn[b];
    if (sa == null && sb == null) return 0;
    if (sa == null) return -1;
    if (sb == null) return 1;
    return sa.compareTo(sb);
  }

  static int _dateTieBreak(TravelFocus a, TravelFocus b, DateTime today) {
    final da = a.date == null
        ? null
        : today.difference(TravelFocusPlan.dayOf(a.date!)).inDays.abs();
    final db = b.date == null
        ? null
        : today.difference(TravelFocusPlan.dayOf(b.date!)).inDays.abs();
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    return 0;
  }
}

/// What the Home travel step does once a scene has been picked.
enum TravelPrepKind { meet, recall, listen, learnKana }
