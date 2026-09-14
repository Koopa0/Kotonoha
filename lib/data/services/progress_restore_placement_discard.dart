// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';

/// `progress_restore_placement_discard_v1` — durable decision that a placement
/// draft from before a committed restore must not be resumed or re-applied.
///
/// The marker is written as part of [ProgressRestoreJournal.commit] before any
/// placement keys are cleared. Bootstrap retries discard while it remains.
abstract final class ProgressRestorePlacementDiscard {
  static const String pendingKey = ProgressStoreKeys.placementDiscardPending;

  /// True when a committed restore still owes placement-draft cleanup.
  static bool isPending(PreferencesService prefs) =>
      prefs.readString(pendingKey) != null;

  /// Records the durable discard decision. Best-effort — callers treat a `false`
  /// return like a failed discard attempt and leave the marker absent only when
  /// the write itself never landed.
  static Future<bool> markPending(PreferencesService prefs) async =>
      await prefs.writeString(pendingKey, 'pending');

  /// Clears the marker once placement keys are gone from durable storage.
  static Future<void> clearPending(PreferencesService prefs) async {
    await prefs.remove(pendingKey);
  }

  // Quarantine and last-good first, primary last: an interrupted cleanup
  // can never leave a primary without its recovery slots.
  static const _placementKeys = <String>[
    ProgressStoreKeys.placementCheckQuarantine,
    ProgressStoreKeys.placementCheckLastGood,
    ProgressStoreKeys.placementCheck,
  ];

  /// Finishes placement-draft cleanup left by a committed restore. Safe to call
  /// on every bootstrap before the placement repository loads.
  static Future<void> recoverIfNeeded(PreferencesService prefs) async {
    await prefs.reload();
    if (!isPending(prefs)) return;
    for (final key in _placementKeys) {
      if (prefs.readString(key) == null) continue;
      try {
        if (!await prefs.remove(key)) return;
      } on Object {
        return;
      }
    }
    await clearPending(prefs);
  }
}
