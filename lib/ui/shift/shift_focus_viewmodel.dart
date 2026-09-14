// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns the 換句 picker: the curated catalogue, the named drill, each
/// drill's plan against the attempt stream (same-day, hold, confirm,
/// review), the picker-preview sightings, and the durable-write state with
/// its retry. The screen renders the list, keeps the source field, and
/// navigates.
///
/// Contract (the same one the widget state used to hold):
/// - Plans are read from the authoritative stream: memory after a flush.
///   Unpersisted rows stay in [AnalyticsLog.all]; a failed durable write
///   must not add a second "already saved" flag.
/// - A drill whose plan previews a reserved sentence is marked as sighted
///   once per picker visit, so tomorrow's confirm knows it was shown.
/// - A failed write keeps the row in memory; [isUnsaved] stays honest and
///   [retryPersist] flushes it.
///
/// Pure of timers, widgets and navigation.
class ShiftFocusViewModel extends ChangeNotifier {
  ShiftFocusViewModel({
    required this.analytics,
    required this.persistence,
    List<ShiftDrill>? drills,
    List<Attempt>? attempts,
    String? pickerSessionId,
    DateTime Function()? clock,
  }) : drills =
           drills ?? ShiftSession.focuses().expand((f) => f.drills).toList(),
       _seeded = attempts != null,
       _attempts = attempts ?? const [],
       _pickerSessionId =
           pickerSessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
       _clock = clock ?? DateTime.now {
    _selectedId = this.drills.first.id;
  }

  final AnalyticsLog analytics;

  /// App-scoped owner of every write's future and its failure state.
  final ProgressPersistenceController persistence;

  /// The human-checked slice the learner picks from.
  final List<ShiftDrill> drills;

  final bool _seeded;
  final String _pickerSessionId;
  final DateTime Function() _clock;
  final Set<String> _previewed = <String>{};

  late String _selectedId;
  List<Attempt> _attempts;
  bool _unsaved = false;
  bool _retrying = false;

  List<ShiftFocus> get focuses => ShiftSession.focuses(drills: drills);
  String get selectedId => _selectedId;
  ShiftDrill? get selected =>
      ShiftSession.drillById(_selectedId, drills: drills);

  /// The stream every plan is read from.
  List<Attempt> get attempts => _attempts;

  /// Rows the log still holds only in memory.
  bool get isUnsaved => _unsaved;
  bool get isRetrying => _retrying;

  ShiftPlan plan(ShiftDrill drill, {ShiftLane requested = ShiftLane.sameDay}) =>
      ShiftSession.plan(
        drill: drill,
        now: _clock(),
        attempts: _attempts,
        requested: requested,
      );

  ShiftPlan? get selectedPlan {
    final drill = selected;
    return drill == null ? null : plan(drill);
  }

  ShiftPlan? get holdPlan {
    final drill = selected;
    return drill == null ? null : plan(drill, requested: ShiftLane.hold);
  }

  /// Whether the next-day hold is offered beside the primary start.
  bool get showHold {
    final sameDay = selectedPlan;
    final hold = holdPlan;
    if (sameDay == null || hold == null) return false;
    if (sameDay.lane == ShiftLane.confirm) return false;
    if (sameDay.noUnseenVariant && !sameDay.holdPending) return false;
    return hold.shiftSight == ShiftSight.unseen || sameDay.holdPending;
  }

  List<ShiftSelfGrade> selfGradesFor(String drillId) =>
      ShiftSession.selfGrades(_attempts, drillId: drillId);

  void select(String drillId) {
    if (_selectedId == drillId) return;
    _selectedId = drillId;
    notifyListeners();
  }

  /// First visit: read the stream (unless seeded) and mark previews.
  Future<void> load() async {
    if (_seeded) {
      await _markVisiblePreviews();
    } else {
      await reload();
    }
  }

  /// Re-reads the authoritative stream and marks any new previews.
  Future<void> reload() async {
    _attempts = await _authoritativeAttempts();
    _unsaved = analytics.unpersistedCount > 0;
    notifyListeners();
    await _markVisiblePreviews();
  }

  /// Re-reads the authoritative stream without touching previews — for the
  /// plan behind a 「もう一回」.
  Future<List<Attempt>> refreshAttempts() async {
    _attempts = await _authoritativeAttempts();
    notifyListeners();
    return _attempts;
  }

  /// Retries the durable write of every unsaved row.
  Future<void> retryPersist() async {
    if (_retrying) return;
    _retrying = true;
    notifyListeners();
    await persistence.retry();
    try {
      await analytics.flushPending();
    } on Object {
      // Leave [isUnsaved] honest. Do not invent a persist.
    }
    _retrying = false;
    _unsaved = analytics.unpersistedCount > 0;
    notifyListeners();
  }

  /// Memory after a flush. Unpersisted rows stay in [AnalyticsLog.all];
  /// a failed durable write must not add a second "already saved" flag.
  Future<List<Attempt>> _authoritativeAttempts() async {
    try {
      await analytics.flushPending();
    } on Object {
      // [unpersistedCount] stays honest. Do not invent a persisted row.
    }
    return List<Attempt>.of(await analytics.all());
  }

  Future<void> _markVisiblePreviews() async {
    final now = _clock();
    for (final drill in drills) {
      final drillPlan = plan(drill);
      final preview = ShiftSession.pickerPreview(drillPlan);
      if (preview == null) continue;
      if (!_previewed.add(drill.id)) continue;
      final pending = analytics.record(
        ShiftSession.sighting(
          drill: drill,
          beat: ShiftBeat.base,
          kind: ShiftSightKind.preview,
          sessionId: _pickerSessionId,
          at: now,
          lane: drillPlan.lane,
        ),
      );
      persistence.trackAnalytics(pending);
      try {
        await pending;
      } on Object {
        // Memory retains the preview; do not invent a persist.
      }
    }
    _unsaved = analytics.unpersistedCount > 0;
    notifyListeners();
  }
}
