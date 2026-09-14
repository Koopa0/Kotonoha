// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns the travel-focus editor: the draft of retained focuses and their
/// dates, the two-focus limit, and the save / clear writes with their
/// in-flight and failure state. The screen renders the tiles, shows the
/// date picker, and pops on a landed write.
///
/// Contract (the same one the widget state used to hold):
/// - Saving, switching or clearing writes only the plan — never kana or
///   詞と句 mastery.
/// - The draft never exceeds [TravelFocusPlan.maxFocuses]; a third pick
///   shows the limit hint instead.
/// - Every edit and write is refused while a save is in flight or a
///   previous write has failed ([isBlocked]); the banner owns that failure.
/// - A write that fails leaves the editor open for retry; one that lands
///   reports success so the view can close.
///
/// Re-notifies on the persistence owner so the block stays live. Pure of
/// widgets and navigation.
class TravelFocusViewModel extends ChangeNotifier {
  TravelFocusViewModel({
    required this.focuses,
    required this.persistence,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _draft = List<TravelFocus>.of(focuses.plan.focuses) {
    persistence.addListener(notifyListeners);
  }

  /// Owner of the retained plan.
  final TravelFocusRepository focuses;

  /// App-scoped owner of every write's future and its failure state.
  final ProgressPersistenceController persistence;

  final DateTime Function() _clock;

  List<TravelFocus> _draft;
  bool _limitHint = false;
  bool _saving = false;

  /// The focuses as edited, not yet saved.
  List<TravelFocus> get draft => List.unmodifiable(_draft);

  /// The third pick was refused; shown until the next edit.
  bool get showsLimitHint => _limitHint;
  bool get isSaving => _saving;

  /// Edits and writes are refused: a save is in flight or one has failed.
  bool get isBlocked => _saving || persistence.hasWriteFailure;

  /// The editor's idea of now — the date picker opens on today.
  DateTime get now => _clock();

  bool isSelected(TravelSceneId scene) =>
      _draft.any((focus) => focus.scene == scene);

  TravelFocus? focusFor(TravelSceneId scene) {
    for (final focus in _draft) {
      if (focus.scene == scene) return focus;
    }
    return null;
  }

  DateTime? dateOf(TravelSceneId scene) => focusFor(scene)?.date;

  /// The day the date picker should open on for [scene].
  DateTime initialDateFor(TravelSceneId scene) =>
      dateOf(scene) ?? TravelFocusPlan.dayOf(now);

  /// Adds or removes [scene]; a third add shows the limit hint instead.
  void toggle(TravelSceneId scene) {
    if (isBlocked) return;
    if (isSelected(scene)) {
      _draft = [
        for (final f in _draft)
          if (f.scene != scene) f,
      ];
      _limitHint = false;
    } else if (_draft.length >= TravelFocusPlan.maxFocuses) {
      _limitHint = true;
    } else {
      _draft = [..._draft, TravelFocus(scene: scene)];
      _limitHint = false;
    }
    notifyListeners();
  }

  /// Dates a retained focus. Ignored for a scene that is not retained.
  void setDate(TravelSceneId scene, DateTime date) {
    if (isBlocked || !isSelected(scene)) return;
    _draft = [
      for (final f in _draft)
        if (f.scene == scene) TravelFocus(scene: scene, date: date) else f,
    ];
    notifyListeners();
  }

  void clearDate(TravelSceneId scene) {
    if (isBlocked || !isSelected(scene)) return;
    _draft = [
      for (final f in _draft)
        if (f.scene == scene) TravelFocus(scene: scene) else f,
    ];
    notifyListeners();
  }

  /// Saves the draft. Resolves to `true` once the write landed; `false`
  /// when refused or failed (the editor stays open, the banner owns it).
  Future<bool> save() => _write(() => focuses.saveFocuses(_draft));

  /// Clears every retained focus. Resolves like [save].
  Future<bool> clear() => _write(focuses.clear);

  Future<bool> _write(Future<void> Function() action) async {
    if (isBlocked) return false;
    _saving = true;
    notifyListeners();
    final pending = action();
    persistence.trackTravelFocus(pending);
    try {
      await pending;
    } catch (_) {
      _saving = false;
      notifyListeners();
      return false;
    }
    _saving = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    persistence.removeListener(notifyListeners);
    super.dispose();
  }
}
