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

class _ValidatedJournal {
  const _ValidatedJournal({
    required this.phase,
    required this.rollback,
    required this.staging,
  });

  final RestoreJournalPhase phase;
  final Map<String, String?> rollback;
  final Map<String, String> staging;
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
  /// Corrupt or schema-invalid payloads always block.
  static bool blocksExport(PreferencesService prefs) {
    final raw = prefs.readString(journalKey);
    if (raw == null) return false;
    final validated = _parseValidated(raw);
    if (validated == null) return true;
    if (validated.phase == RestoreJournalPhase.committed) return false;
    return true;
  }

  /// Before repository load: finish committed cleanup, or roll back any
  /// interrupted transaction so primaries never present a new/old mix as normal
  /// data. A failed rollback leaves the journal in place and keeps blocking.
  static Future<RestoreJournalRecoveryResult> recoverIfNeeded(
    PreferencesService prefs,
  ) async {
    final journal = ProgressRestoreJournal(prefs);
    await prefs.reload();
    final raw = prefs.readString(journalKey);
    if (raw == null) return RestoreJournalRecoveryResult.ok;
    final validated = journal._parseValidatedSync(raw);
    if (validated == null) {
      return const RestoreJournalRecoveryResult(needsRecovery: true);
    }
    if (validated.phase == RestoreJournalPhase.committed) {
      await journal._removeJournalBestEffort();
      return RestoreJournalRecoveryResult.ok;
    }
    final rolled = await journal._rollbackPrimaries(validated);
    if (!rolled) {
      return const RestoreJournalRecoveryResult(needsRecovery: true);
    }
    await journal._removeJournalBestEffort();
    return RestoreJournalRecoveryResult(
      needsRecovery: blocksExport(prefs),
    );
  }

  RestoreJournalPhase? _durablePhaseSync() {
    final raw = _prefs.readString(journalKey);
    return _parseValidatedSync(raw)?.phase;
  }

  Future<RestoreJournalPhase?> _durablePhase() async {
    await _prefs.reload();
    return _durablePhaseSync();
  }

  _ValidatedJournal? _validatedDocumentSync() =>
      _parseValidatedSync(_prefs.readString(journalKey));

  Future<_ValidatedJournal?> _validatedDocument() async {
    await _prefs.reload();
    return _validatedDocumentSync();
  }

  _ValidatedJournal? _parseValidatedSync(String? raw) => _parseValidated(raw);

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
      await _prefs.reload();
      throw RestoreJournalWriteFailure(primaryKey);
    }
  }

  /// Records a durable committed decision, then best-effort journal cleanup.
  /// Primaries already hold the new bodies; a failed remove leaves [committed]
  /// on disk and must not be rolled back on the next launch.
  Future<void> commit() async {
    await _writeJournalPhase(RestoreJournalPhase.committed);
    await _prefs.reload();
    if (!await _isCommittedDurable()) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    try {
      await _removeJournalBestEffort();
    } catch (_) {
      // A platform reply may throw after the removal already landed. The
      // committed phase on durable storage is the decision — do not roll back.
    }
  }

  /// Rolls every primary back to the captured rollback raw. Returns false when
  /// the journal is corrupt or any platform write/remove is refused — the
  /// journal stays blocking in that case.
  Future<bool> _rollbackPrimaries(_ValidatedJournal validated) async {
    await _writeJournalPhase(RestoreJournalPhase.rollingBack);

    for (final key in RestoreJournalStores.all) {
      final raw = validated.rollback[key];
      if (raw is String) {
        if (!await _prefs.writeString(key, raw)) {
          await _prefs.reload();
          return false;
        }
      } else if (raw == null) {
        if (!await _prefs.remove(key)) {
          await _prefs.reload();
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  /// Aborts an in-flight transaction. Throws [RestoreJournalRollbackFailure]
  /// when rollback cannot be confirmed on disk — the journal is left blocking.
  /// Never rolls back once [RestoreJournalPhase.committed] is durable.
  Future<void> abortAndRollback() async {
    await _prefs.reload();
    if (await _isCommittedDurable()) return;
    final validated = await _validatedDocument();
    if (validated == null) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
    final rolled = await _rollbackPrimaries(validated);
    if (!rolled) {
      throw RestoreJournalRollbackFailure(journalKey);
    }
    if (!await _prefs.remove(journalKey)) {
      await _prefs.reload();
      throw RestoreJournalRollbackFailure(journalKey);
    }
  }

  Future<void> _writeJournalPhase(RestoreJournalPhase phase) async {
    final validated = _validatedDocumentSync();
    if (validated == null) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    await _writeJournal(<String, Object?>{
      'phase': phase.name,
      'rollback': validated.rollback,
      'staging': validated.staging,
    });
  }

  Future<void> _writeJournal(Map<String, Object?> doc) async {
    if (_parseValidated(jsonEncode(doc)) == null) {
      throw RestoreJournalWriteFailure(journalKey);
    }
    if (!await _prefs.writeString(journalKey, jsonEncode(doc))) {
      await _prefs.reload();
      throw RestoreJournalWriteFailure(journalKey);
    }
  }

  Future<void> _removeJournalBestEffort() async {
    await _prefs.remove(journalKey);
  }

  Future<bool> _isCommittedDurable() async {
    await _prefs.reload();
    return _durablePhaseSync() == RestoreJournalPhase.committed;
  }

  /// Whether a blocking journal remains on disk (unfinished transaction or
  /// corrupt payload — not a committed cleanup still pending).
  static bool needsRecovery(PreferencesService prefs) => blocksExport(prefs);

  static RestoreJournalPhase? _readPhase(String? raw) {
    final validated = _parseValidated(raw);
    return validated?.phase;
  }

  static _ValidatedJournal? _parseValidated(String? raw) {
    if (raw == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
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
      if (value == null) {
        rollback[key] = null;
      } else if (value is String) {
        rollback[key] = value;
      } else {
        return null;
      }
    }

    final stagingRaw = decoded['staging'];
    if (stagingRaw is! Map) return null;
    final staging = <String, String>{};
    for (final key in RestoreJournalStores.all) {
      if (!stagingRaw.containsKey(key)) return null;
      final value = stagingRaw[key];
      if (value is! String) return null;
      staging[key] = value;
    }

    return _ValidatedJournal(
      phase: phase,
      rollback: rollback,
      staging: staging,
    );
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
