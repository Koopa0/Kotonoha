// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';

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

/// `progress_restore_journal_v1` — coordinates staging, applying, rollback and
/// startup recovery for the five canonical progress primaries.
///
/// Rollback captures each primary's exact raw string at transaction start (null
/// when absent). Staging holds the encoded replacement for each body. Memory is
/// updated only after every primary write succeeds and the journal records a
/// durable [RestoreJournalPhase.committed] decision and cleanup succeeds.
class ProgressRestoreJournal {
  ProgressRestoreJournal(this._prefs);

  static const String journalKey = 'progress_restore_journal_v1';

  final PreferencesService _prefs;

  /// True when an unfinished, non-committed journal is on disk. A [committed]
  /// journal awaiting cleanup does not block — the restore decision is durable.
  static bool blocksExport(PreferencesService prefs) {
    final phase = _readPhase(prefs.readString(journalKey));
    if (phase == null || phase == RestoreJournalPhase.committed) return false;
    return true;
  }

  /// Before repository load: finish committed cleanup, or roll back any
  /// interrupted transaction so primaries never present a new/old mix as normal
  /// data. A failed rollback leaves the journal in place and keeps blocking.
  static Future<RestoreJournalRecoveryResult> recoverIfNeeded(
    PreferencesService prefs,
  ) async {
    final journal = ProgressRestoreJournal(prefs);
    final phase = journal._phase;
    if (phase == null) return RestoreJournalRecoveryResult.ok;
    if (phase == RestoreJournalPhase.committed) {
      await journal._removeJournalBestEffort();
      return RestoreJournalRecoveryResult.ok;
    }
    final rolled = await journal._rollbackPrimaries();
    if (!rolled) {
      return const RestoreJournalRecoveryResult(needsRecovery: true);
    }
    await journal._removeJournalBestEffort();
    return RestoreJournalRecoveryResult(
      needsRecovery: blocksExport(prefs),
    );
  }

  RestoreJournalPhase? get _phase => _readPhase(_prefs.readString(journalKey));

  Map<String, dynamic>? get _document {
    final raw = _prefs.readString(journalKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Corrupt — no rollback map; leave the journal blocking.
    }
    return null;
  }

  /// Begins staging: snapshot current primaries for rollback and persist the
  /// encoded replacements. Does not touch primaries yet.
  Future<void> beginStaging(Map<String, String> stagingEncoded) async {
    assert(stagingEncoded.keys.toSet().containsAll(RestoreJournalStores.all));
    final rollback = <String, String?>{};
    for (final key in RestoreJournalStores.all) {
      rollback[key] = _prefs.readString(key);
    }
    await _writeJournal(<String, Object?>{
      'phase': RestoreJournalPhase.staging.name,
      'rollback': rollback,
      'staging': stagingEncoded,
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

  /// Records a durable committed decision, then best-effort journal cleanup.
  /// Primaries already hold the new bodies; a failed remove leaves [committed]
  /// on disk and must not be rolled back on the next launch.
  Future<void> commit() async {
    await _writeJournalPhase(RestoreJournalPhase.committed);
    await _removeJournalBestEffort();
  }

  /// Rolls every primary back to the captured rollback raw. Returns false when
  /// the journal is corrupt or any platform write/remove is refused — the
  /// journal stays blocking in that case.
  Future<bool> _rollbackPrimaries() async {
    final doc = _document;
    if (doc == null) return false;

    await _writeJournalPhase(RestoreJournalPhase.rollingBack);
    final rollback = doc['rollback'];
    if (rollback is! Map) return false;

    for (final key in RestoreJournalStores.all) {
      final raw = rollback[key];
      if (raw is String) {
        if (!await _prefs.writeString(key, raw)) return false;
      } else if (raw == null) {
        if (!await _prefs.remove(key)) return false;
      }
    }
    return true;
  }

  /// Aborts an in-flight transaction. Throws [RestoreJournalRollbackFailure]
  /// when rollback cannot be confirmed on disk — the journal is left blocking.
  /// Never rolls back once [RestoreJournalPhase.committed] is durable.
  Future<void> abortAndRollback() async {
    if (_phase == RestoreJournalPhase.committed) return;
    final rolled = await _rollbackPrimaries();
    if (!rolled) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
    if (!await _prefs.remove(journalKey)) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
  }

  Future<void> _writeJournalPhase(RestoreJournalPhase phase) async {
    final doc = _document;
    if (doc == null) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    doc['phase'] = phase.name;
    await _writeJournal(doc);
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

  static RestoreJournalPhase? _readPhase(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return RestoreJournalPhase.applying;
      final name = decoded['phase'];
      if (name is! String) return RestoreJournalPhase.applying;
      for (final phase in RestoreJournalPhase.values) {
        if (phase.name == name) return phase;
      }
      return RestoreJournalPhase.applying;
    } on FormatException {
      return RestoreJournalPhase.applying;
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
