// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/progress_snapshot.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';

/// Refuses an export when a canonical store came up [StoreHealth.recoveryRequired]
/// at startup: that store began empty because its primary was unreadable with no
/// usable last-known-good, so a snapshot taken now would silently wrap
/// unresolved data loss as if it were a complete backup. [stores] names each
/// affected primary key.
class SnapshotExportBlocked implements Exception {
  SnapshotExportBlocked(List<String> stores)
    : stores = List.unmodifiable(stores);

  /// The primary keys of the store(s) still needing recovery. Unmodifiable — a
  /// caller cannot mutate the reported set.
  final List<String> stores;

  @override
  String toString() => 'SnapshotExportBlocked(stores: $stores)';
}

/// Captures the app's in-memory canonical progress into a portable
/// [ProgressSnapshot] and encodes it — the one read that spans the three
/// progress owners, so it is a use case rather than a fourth repository.
///
/// It reads the three source repositories' current in-memory state — it never
/// writes, flushes, removes a key, or notifies a listener. In particular it does
/// NOT call `flushPending` and does not require a prior platform write to have
/// succeeded: a mutation that is committed to memory but whose platform write
/// failed or is still gated is included, because that is the truth the learner
/// sees. Applying a snapshot back into the stores is deliberately OUT OF SCOPE
/// here — this owns capture + encode only; [ProgressRestoreTransaction] owns
/// the journalled replace and must not change this capture contract.
class ProgressSnapshotCapture {
  ProgressSnapshotCapture({
    required this._kana,
    required this._kanji,
    required this._words,
    this._prefs,
    this._codec = const ProgressSnapshotCodec(),
  });

  final KanaProgressRepository _kana;
  final KanjiReadingRepository _kanji;
  final WordProgressRepository _words;
  final PreferencesService? _prefs;
  final ProgressSnapshotCodec _codec;

  /// Canonical stores still needing recovery, named by primary key. Empty
  /// when export may proceed. Unmodifiable — a caller cannot mutate the
  /// reported set.
  ///
  /// Restore-journal blocking comes from the on-disk journal gate and from
  /// [KanaProgressRepository.isRestoreJournalBlocked] on each owner — the
  /// same flag [ProgressRestoreRecovery] sets when durable state cannot be
  /// confirmed. A pending or failed ordinary save does not set it.
  List<String> get blockedStores => List.unmodifiable([
    if (_kana.statsHealth == StoreHealth.recoveryRequired)
      ProgressStoreKeys.kanaStats,
    if (_kana.learnedUnitsHealth == StoreHealth.recoveryRequired)
      ProgressStoreKeys.learnedUnits,
    if (_kana.seenUnlocksHealth == StoreHealth.recoveryRequired)
      ProgressStoreKeys.seenUnlocks,
    if (_kanji.statsHealth == StoreHealth.recoveryRequired)
      ProgressStoreKeys.kanjiStats,
    if (_words.statsHealth == StoreHealth.recoveryRequired)
      ProgressStoreKeys.wordStats,
    if (_restoreJournalBlocksExport) ProgressRestoreJournal.journalKey,
  ]);

  bool get _restoreJournalBlocksExport =>
      _kana.isRestoreJournalBlocked ||
      _kanji.isRestoreJournalBlocked ||
      _words.isRestoreJournalBlocked ||
      (_prefs != null && ProgressRestoreJournal.blocksExport(_prefs));

  /// Synchronously captures the five in-memory progress bodies into an
  /// immutable [ProgressSnapshot] — no await, so nothing can interleave between
  /// reading the three repositories' state and the capture is a single
  /// consistent instant.
  ///
  /// Throws [SnapshotExportBlocked] if any canonical store came up
  /// [StoreHealth.recoveryRequired] at startup. An empty store (a legal fresh
  /// install) and a recovered store (salvaged / restored / preservation-pending
  /// — a usable value is in memory) both export normally.
  ProgressSnapshot capture({required DateTime createdAt}) {
    final blocked = blockedStores;
    if (blocked.isNotEmpty) throw SnapshotExportBlocked(blocked);

    return ProgressSnapshot(
      createdAt: createdAt,
      kanaStats: _kana.stats,
      learnedUnits: _kana.learnedUnits,
      seenUnlocks: _kana.seenUnlocks,
      kanjiReadingStats: _kanji.stats,
      wordStats: _words.stats,
    );
  }

  /// [capture]s the current state and encodes it to the canonical Snapshot v2
  /// string.
  String exportEncoded({required DateTime createdAt}) =>
      _codec.encode(capture(createdAt: createdAt));
}
