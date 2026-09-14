// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_placement_discard.dart';

/// Phases of an in-flight progress restore. Only [committed] (or a cleared
/// journal after it) is finished. Anything else on the next [recoverIfNeeded]
/// must roll back primaries — except [committed], which must never be rolled
/// back even when journal cleanup is still pending.
enum RestoreJournalPhase { staging, applying, rollingBack, committed }

/// Thrown when a progress mutation is refused because an unfinished restore
/// journal still blocks normal learning writes.
class ProgressRestoreJournalBlocked implements Exception {
  const ProgressRestoreJournalBlocked();

  @override
  String toString() => 'ProgressRestoreJournalBlocked';
}

/// Thrown when a progress mutation is refused while a restore transaction is
/// in flight.
class ProgressRestoreInProgress implements Exception {
  const ProgressRestoreInProgress();

  @override
  String toString() => 'ProgressRestoreInProgress';
}

/// Outcome of [ProgressRestoreJournal.recoverIfNeeded] at startup.
class RestoreJournalRecoveryResult {
  const RestoreJournalRecoveryResult({required this.needsRecovery});

  /// True when a blocking journal remains after recovery — primaries may be
  /// mixed or corrupt and normal learning writes must stay refused.
  final bool needsRecovery;

  static const ok = RestoreJournalRecoveryResult(needsRecovery: false);
}

/// Primary keys participating in a restore transaction — the same five bodies
/// [ProgressSnapshotRepository] captures.
abstract final class RestoreJournalStores {
  static const all = <String>[
    ProgressSnapshotRepository.kanaStatsStore,
    ProgressSnapshotRepository.learnedUnitsStore,
    ProgressSnapshotRepository.seenUnlocksStore,
    ProgressSnapshotRepository.kanjiStatsStore,
    ProgressSnapshotRepository.wordStatsStore,
  ];
}

/// Placement draft keys snapshotted when a restore must invalidate a stale
/// check. Rolled back with the five primaries when commit never lands.
abstract final class RestoreJournalPlacementStores {
  static const all = PlacementCheckRepository.durableKeys;
}

class _ValidatedJournal {
  const _ValidatedJournal({
    required this.phase,
    required this.rollback,
    this.staging,
    this.placementRollback,
    this.placementDiscardPending = false,
  });

  final RestoreJournalPhase phase;
  final Map<String, String?> rollback;
  final Map<String, String>? staging;
  final Map<String, String?>? placementRollback;
  final bool placementDiscardPending;
}

/// `progress_restore_journal_v1` — coordinates staging, applying, rollback and
/// startup recovery for the five canonical progress primaries.
///
/// Rollback captures each primary's exact raw string at transaction start (null
/// when absent). Staging holds the encoded replacement for each body. Memory is
/// updated only after every primary write succeeds and the journal records a
/// durable [RestoreJournalPhase.committed] decision.
class ProgressRestoreJournal {
  ProgressRestoreJournal(this._prefs);

  static const String journalKey = 'progress_restore_journal_v1';

  final PreferencesService _prefs;

  /// True when an unfinished, non-committed journal is on disk. A [committed]
  /// journal awaiting cleanup does not block — the restore decision is durable.
  /// Corrupt or schema-invalid payloads always block.
  static bool blocksExport(PreferencesService prefs) {
    final raw = prefs.readString(journalKey);
    if (raw == null) return false;
    final parsed = _parse(raw);
    if (parsed == null) return true;
    return parsed.phase != RestoreJournalPhase.committed;
  }

  /// Before repository load: finish committed cleanup, or roll back any
  /// interrupted transaction so primaries never present a new/old mix as normal
  /// data. A failed rollback leaves the journal in place and keeps blocking.
  static Future<RestoreJournalRecoveryResult> recoverIfNeeded(
    PreferencesService prefs,
  ) async {
    await prefs.reload();
    final journal = ProgressRestoreJournal(prefs);
    final parsed = journal._validated;
    if (parsed == null) {
      if (journal._rawPresent) {
        return const RestoreJournalRecoveryResult(needsRecovery: true);
      }
      return RestoreJournalRecoveryResult.ok;
    }
    if (parsed.phase == RestoreJournalPhase.committed) {
      if (parsed.placementDiscardPending) {
        await ProgressRestorePlacementDiscard.markPending(prefs);
      }
      await journal._removeJournalBestEffort();
      return RestoreJournalRecoveryResult.ok;
    }
    final rolled = await journal._rollbackPrimaries(parsed);
    if (!rolled) {
      return const RestoreJournalRecoveryResult(needsRecovery: true);
    }
    await journal._removeJournalBestEffort();
    return RestoreJournalRecoveryResult(
      needsRecovery: blocksExport(prefs),
    );
  }

  bool get _rawPresent => _prefs.readString(journalKey) != null;

  _ValidatedJournal? get _validated => _parse(_prefs.readString(journalKey));

  Map<String, dynamic>? get _document {
    final raw = _prefs.readString(journalKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Corrupt — leave the journal blocking.
    }
    return null;
  }

  /// Begins staging: snapshot current primaries for rollback and persist the
  /// encoded replacements. Does not touch primaries yet.
  ///
  /// When [placementRollback] is set, the restore must clear that draft before
  /// [commit] and roll it back with the primaries if the transaction aborts.
  Future<void> beginStaging(
    Map<String, String> stagingEncoded, {
    Map<String, String?>? placementRollback,
  }) async {
    assert(stagingEncoded.keys.toSet().containsAll(RestoreJournalStores.all));
    final rollback = <String, String?>{};
    for (final key in RestoreJournalStores.all) {
      rollback[key] = _prefs.readString(key);
    }
    await _writeJournal(<String, Object?>{
      'phase': RestoreJournalPhase.staging.name,
      'rollback': rollback,
      'staging': stagingEncoded,
      if (placementRollback != null) 'placementRollback': placementRollback,
    });
  }

  /// Marks applying and writes [primaryKey] with [encoded]. Call once per store
  /// in [RestoreJournalStores.all] order.
  Future<void> applyPrimary(String primaryKey, String encoded) async {
    await _writeJournalPhase(RestoreJournalPhase.applying);
    if (!await _prefs.writeString(primaryKey, encoded)) {
      throw RestoreJournalWriteFailure(primaryKey);
    }
  }

  /// Records a durable committed decision, then removes the journal. Cleanup
  /// may fail after [committed] is already durable — that still counts as
  /// success. Throws when the committed marker never lands on durable storage.
  ///
  /// When [recordPlacementDiscardPending] is true, the committed journal and
  /// [ProgressRestorePlacementDiscard.pendingKey] both record that any
  /// pre-restore placement draft must be cleared before it can be resumed.
  Future<void> commit({bool recordPlacementDiscardPending = false}) async {
    final doc = _document;
    if (doc == null) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    doc['phase'] = RestoreJournalPhase.committed.name;
    if (recordPlacementDiscardPending) {
      doc['placementDiscardPending'] = true;
    }
    if (!await _prefs.writeString(journalKey, jsonEncode(doc))) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    await _prefs.reload();
    if (_validated?.phase != RestoreJournalPhase.committed) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    if (recordPlacementDiscardPending) {
      await ProgressRestorePlacementDiscard.markPending(_prefs);
    }
    try {
      if (!await _prefs.remove(journalKey)) {
        return; // committed durable; cleanup pending is OK
      }
    } on Object {
      await _prefs.reload();
      if (_prefs.readString(journalKey) == null) {
        return; // native removal succeeded before the throw
      }
      if (_validated?.phase == RestoreJournalPhase.committed) {
        return; // cleanup failed but commit is durable
      }
      rethrow;
    }
    await _prefs.reload();
  }

  /// Rolls every primary back to the captured rollback raw. Returns false when
  /// the journal is corrupt or any platform write/remove is refused — the
  /// journal stays blocking in that case.
  Future<bool> _rollbackPrimaries(_ValidatedJournal parsed) async {
    if (!await _tryWriteJournalPhase(RestoreJournalPhase.rollingBack)) {
      return false;
    }

    for (final key in RestoreJournalStores.all) {
      final raw = parsed.rollback[key];
      if (raw == null) {
        if (!await _prefs.remove(key)) return false;
      } else {
        if (!await _prefs.writeString(key, raw)) return false;
      }
    }
    return await _rollbackPlacement(parsed.placementRollback);
  }

  Future<bool> _rollbackPlacement(Map<String, String?>? placementRollback) async {
    if (placementRollback == null) return true;
    for (final key in RestoreJournalPlacementStores.all) {
      if (!placementRollback.containsKey(key)) return false;
      final raw = placementRollback[key];
      if (raw == null) {
        if (!await _prefs.remove(key)) return false;
      } else {
        if (!await _prefs.writeString(key, raw)) return false;
      }
    }
    return true;
  }

  /// Aborts an in-flight transaction. Throws [RestoreJournalRollbackFailure]
  /// when rollback cannot be confirmed on disk — the journal is left blocking.
  /// Never rolls back once [RestoreJournalPhase.committed] is durable.
  Future<void> abortAndRollback() async {
    await _prefs.reload();
    final parsed = _validated;
    if (parsed == null) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
    if (parsed.phase == RestoreJournalPhase.committed) {
      return;
    }
    final rolled = await _rollbackPrimaries(parsed);
    if (!rolled) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
    if (!await _prefs.remove(journalKey)) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
  }

  Future<void> _writeJournalPhase(RestoreJournalPhase phase) async {
    if (!await _tryWriteJournalPhase(phase)) {
      throw RestoreJournalWriteFailure(journalKey);
    }
  }

  Future<bool> _tryWriteJournalPhase(RestoreJournalPhase phase) async {
    final doc = _document;
    if (doc == null) return false;
    doc['phase'] = phase.name;
    return await _prefs.writeString(journalKey, jsonEncode(doc));
  }

  Future<void> _writeJournal(Map<String, Object?> doc) async {
    if (!await _prefs.writeString(journalKey, jsonEncode(doc))) {
      throw RestoreJournalWriteFailure(journalKey);
    }
  }

  Future<void> _removeJournalBestEffort() async {
    await _prefs.remove(journalKey);
  }

  /// Whether a blocking journal remains on disk (unfinished transaction or
  /// corrupt payload — not a committed cleanup still pending).
  static bool needsRecovery(PreferencesService prefs) => blocksExport(prefs);

  static _ValidatedJournal? _parse(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final phaseName = decoded['phase'];
      if (phaseName is! String) return null;
      RestoreJournalPhase? phase;
      for (final candidate in RestoreJournalPhase.values) {
        if (candidate.name == phaseName) {
          phase = candidate;
          break;
        }
      }
      if (phase == null) return null;

      final rollbackRaw = decoded['rollback'];
      if (rollbackRaw is! Map) return null;
      final rollback = <String, String?>{};
      for (final key in RestoreJournalStores.all) {
        if (!rollbackRaw.containsKey(key)) return null;
        final value = rollbackRaw[key];
        if (value is String) {
          rollback[key] = value;
        } else if (value == null) {
          rollback[key] = null;
        } else {
          return null;
        }
      }

      Map<String, String>? staging;
      final stagingRaw = decoded['staging'];
      if (stagingRaw != null) {
        if (stagingRaw is! Map) return null;
        staging = <String, String>{};
        for (final key in RestoreJournalStores.all) {
          if (!stagingRaw.containsKey(key)) return null;
          final value = stagingRaw[key];
          if (value is! String) return null;
          staging[key] = value;
        }
      }

      Map<String, String?>? placementRollback;
      final placementRaw = decoded['placementRollback'];
      if (placementRaw != null) {
        if (placementRaw is! Map) return null;
        placementRollback = <String, String?>{};
        for (final key in RestoreJournalPlacementStores.all) {
          if (!placementRaw.containsKey(key)) return null;
          final value = placementRaw[key];
          if (value is String) {
            placementRollback[key] = value;
          } else if (value == null) {
            placementRollback[key] = null;
          } else {
            return null;
          }
        }
      }

      final placementDiscardPending =
          decoded['placementDiscardPending'] == true;

      return _ValidatedJournal(
        phase: phase,
        rollback: rollback,
        staging: staging,
        placementRollback: placementRollback,
        placementDiscardPending: placementDiscardPending,
      );
    } on FormatException {
      return null;
    }
  }
}

/// A platform write during restore failed before commit — caller must attempt
/// [ProgressRestoreJournal.abortAndRollback].
class RestoreJournalWriteFailure implements Exception {
  RestoreJournalWriteFailure(this.key);

  final String key;

  @override
  String toString() => 'RestoreJournalWriteFailure(key: $key)';
}

/// Rollback could not be confirmed on durable storage — the journal stays
/// blocking until [ProgressRestoreJournal.recoverIfNeeded] succeeds.
class RestoreJournalRollbackFailure implements Exception {
  RestoreJournalRollbackFailure(this.key);

  final String key;

  @override
  String toString() => 'RestoreJournalRollbackFailure(key: $key)';
}
