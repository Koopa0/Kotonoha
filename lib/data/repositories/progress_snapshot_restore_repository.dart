// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/domain/models/progress_snapshot.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';

/// Preview of a validated Snapshot v2 file — no store writes.
class ProgressRestorePreview {
  const ProgressRestorePreview(this.snapshot);

  final ProgressSnapshot snapshot;
}

/// Applies a validated [ProgressSnapshot] through [ProgressRestoreJournal].
/// Memory is replaced only after every primary write succeeds.
class ProgressSnapshotRestoreRepository {
  ProgressSnapshotRestoreRepository({
    required this._prefs,
    required this._kana,
    required this._kanji,
    required this._words,
    PlacementCheckRepository? placement,
    this._codec = const ProgressSnapshotCodec(),
  }) : _journal = ProgressRestoreJournal(_prefs),
       _placement = placement;

  final PreferencesService _prefs;
  final KanaProgressRepository _kana;
  final KanjiReadingRepository _kanji;
  final WordProgressRepository _words;
  final PlacementCheckRepository? _placement;
  final ProgressSnapshotCodec _codec;
  final ProgressRestoreJournal _journal;

  static const _auxiliaryKeys = <String>[
    'kana_stats_last_good_v1',
    'kana_stats_quarantine_v1',
    'learned_units_last_good_v1',
    'learned_units_quarantine_v1',
    'seen_unlocks_last_good_v1',
    'seen_unlocks_quarantine_v1',
    'kanji_units_last_good_v1',
    'kanji_units_quarantine_v1',
    'word_stats_last_good_v1',
    'word_stats_quarantine_v1',
  ];

  /// Strict decode only — zero preference writes.
  ProgressRestorePreview? previewEncoded(String raw) {
    final result = _codec.decodeAndValidate(raw);
    if (result is! SnapshotDecodeSuccess) return null;
    return ProgressRestorePreview(result.snapshot);
  }

  /// Replaces all five primaries transactionally, then updates memory.
  ///
  /// Throws [RestoreJournalWriteFailure] after rolling primaries back. Validation
  /// must happen before calling — this does not re-decode.
  Future<void> apply(ProgressSnapshot snapshot) async {
    await Future.wait([
      _kana.prepareForRestore(),
      _kanji.prepareForRestore(),
      _words.prepareForRestore(),
    ]);
    try {
      final staging = _encodeStaging(snapshot);
      try {
        await _journal.beginStaging(staging);
        for (final key in RestoreJournalStores.all) {
          await _journal.applyPrimary(key, staging[key]!);
        }
        for (final key in _auxiliaryKeys) {
          if (!await _prefs.remove(key)) {
            throw RestoreJournalWriteFailure(key);
          }
        }
        await _journal.commit();
        await _discardPlacementDraftAfterCommit();
      } on RestoreJournalWriteFailure {
        await _syncMemoryFromDurable();
        try {
          await _journal.abortAndRollback();
        } on RestoreJournalRollbackFailure {
          // Journal stays blocking — primaries may still be mixed on disk.
        }
        await _syncMemoryFromDurable();
        _syncJournalWriteBlocking();
        rethrow;
      } catch (_) {
        await _prefs.reload();
        if (_isDurableCommitted()) {
          await _discardPlacementDraftAfterCommit();
          _applyToMemory(snapshot);
          return;
        }
        try {
          await _journal.abortAndRollback();
        } on RestoreJournalRollbackFailure {
          // Journal stays blocking — primaries may still be mixed on disk.
        }
        await _syncMemoryFromDurable();
        _syncJournalWriteBlocking();
        rethrow;
      }
      _applyToMemory(snapshot);
    } finally {
      _kana.finishRestore();
      _kanji.finishRestore();
      _words.finishRestore();
    }
  }

  bool _isDurableCommitted() {
    final raw = _prefs.readString(ProgressRestoreJournal.journalKey);
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      return decoded['phase'] == RestoreJournalPhase.committed.name;
    } on FormatException {
      return false;
    }
  }

  Future<void> _syncMemoryFromDurable() async {
    await Future.wait([
      _kana.reloadFromPlatform(),
      _kanji.reloadFromPlatform(),
      _words.reloadFromPlatform(),
    ]);
  }

  void _syncJournalWriteBlocking() {
    final blocked = ProgressRestoreJournal.needsRecovery(_prefs);
    _kana.setRestoreJournalBlocked(blocked);
    _kanji.setRestoreJournalBlocked(blocked);
    _words.setRestoreJournalBlocked(blocked);
  }

  Future<void> _discardPlacementDraftAfterCommit() async {
    final placement = _placement;
    if (placement == null) return;
    try {
      await placement.discardAfterRestore();
    } on StoreWriteFailure catch (error) {
      throw RestoreJournalWriteFailure(error.key);
    }
  }

  void _applyToMemory(ProgressSnapshot snapshot) {
    _kana.replaceFromRestore(
      stats: snapshot.kanaStats,
      learnedUnits: snapshot.learnedUnits,
      seenUnlocks: snapshot.seenUnlocks,
    );
    _kanji.replaceFromRestore(stats: snapshot.kanjiReadingStats);
    _words.replaceFromRestore(stats: snapshot.wordStats);
  }

  Map<String, String> _encodeStaging(ProgressSnapshot snapshot) {
    return <String, String>{
      ProgressSnapshotRepository.kanaStatsStore: jsonEncode(
        snapshot.kanaStats.map((k, v) => MapEntry(k, v.toJson())),
      ),
      ProgressSnapshotRepository.learnedUnitsStore: jsonEncode(
        snapshot.learnedUnits.toList(),
      ),
      ProgressSnapshotRepository.seenUnlocksStore: jsonEncode(
        snapshot.seenUnlocks.toList(),
      ),
      ProgressSnapshotRepository.kanjiStatsStore: jsonEncode(
        snapshot.kanjiReadingStats.map((k, v) => MapEntry(k, v.toJson())),
      ),
      ProgressSnapshotRepository.wordStatsStore: jsonEncode(
        snapshot.wordStats.map((k, v) => MapEntry(k, v.toJson())),
      ),
    };
  }
}
