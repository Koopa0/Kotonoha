// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';

/// Phases of an in-flight progress restore. Only [committed] is finished;
/// anything else on the next [recoverIfNeeded] must roll back primaries and
/// clear the journal before normal load or export.
enum RestoreJournalPhase {
  staging,
  applying,
  rollingBack,
  committed,
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

/// Typed reason a restore journal blocks export or needs recovery.
enum RestoreJournalBlockReason {
  /// A restore transaction was interrupted before [RestoreJournalPhase.committed].
  interrupted,
}

/// `progress_restore_journal_v1` — coordinates staging, applying, rollback and
/// startup recovery for the five canonical progress primaries.
///
/// Rollback captures each primary's exact raw string at transaction start (null
/// when absent). Staging holds the encoded replacement for each body. Memory is
/// updated only after every primary write succeeds and the journal is cleared.
class ProgressRestoreJournal {
  ProgressRestoreJournal(this._prefs);

  static const String journalKey = 'progress_restore_journal_v1';

  final PreferencesService _prefs;

  /// True when an unfinished journal is on disk — export must refuse until
  /// [recoverIfNeeded] clears it.
  static bool blocksExport(PreferencesService prefs) {
    final phase = _readPhase(prefs.readString(journalKey));
    return phase != null && phase != RestoreJournalPhase.committed;
  }

  /// Before repository load: roll back any interrupted transaction so primaries
  /// never present a new/old mix as normal data.
  static Future<void> recoverIfNeeded(PreferencesService prefs) async {
    final journal = ProgressRestoreJournal(prefs);
    final phase = journal._phase;
    if (phase == null || phase == RestoreJournalPhase.committed) {
      if (phase == RestoreJournalPhase.committed) {
        await journal._clearJournal();
      }
      return;
    }
    await journal._rollbackPrimaries();
    await journal._clearJournal();
  }

  RestoreJournalPhase? get _phase => _readPhase(_prefs.readString(journalKey));

  Map<String, dynamic>? get _document {
    final raw = _prefs.readString(journalKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Treat a corrupt journal like an interrupted apply — rollback what we can.
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

  /// Successful end — remove the journal. Primaries already hold the new bodies.
  Future<void> commit() async {
    await _clearJournal();
  }

  Future<void> _rollbackPrimaries() async {
    final doc = _document;
    if (doc == null) {
      await _clearJournal();
      return;
    }
    await _writeJournalPhase(RestoreJournalPhase.rollingBack);
    final rollback = doc['rollback'];
    if (rollback is Map) {
      for (final key in RestoreJournalStores.all) {
        final raw = rollback[key];
        if (raw is String) {
          await _prefs.writeString(key, raw);
        } else if (raw == null) {
          await _prefs.remove(key);
        }
      }
    }
  }

  Future<void> abortAndRollback() async {
    await _rollbackPrimaries();
    await _clearJournal();
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

  Future<void> _clearJournal() async {
    await _prefs.remove(journalKey);
  }

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

/// A platform write during restore failed — caller must [ProgressRestoreJournal.abortAndRollback].
class RestoreJournalWriteFailure implements Exception {
  RestoreJournalWriteFailure(this.key);

  final String key;

  @override
  String toString() => 'RestoreJournalWriteFailure(key: $key)';
}
