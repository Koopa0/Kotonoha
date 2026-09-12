// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
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
/// [ProgressSnapshot] and encodes it.
///
/// It reads the three source repositories' current in-memory state — it never
/// writes, flushes, removes a key, or notifies a listener. In particular it does
/// NOT call `flushPending` and does not require a prior platform write to have
/// succeeded: a mutation that is committed to memory but whose platform write
/// failed or is still gated is included, because that is the truth the learner
/// sees. Applying a snapshot back into the stores is deliberately OUT OF SCOPE
/// here — this owns capture + encode only. The restore transaction (journal +
/// rollback of these five primaries) lands in a follow-up on the same ticket;
/// it must not change this capture contract.
class ProgressSnapshotRepository {
  ProgressSnapshotRepository({
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

  /// Primary keys of the five snapshot bodies — the same identities the
  /// source repositories own. Restore must replace exactly these, and an
  /// unresolved restore journal must name them when it blocks export.
  static const String kanaStatsStore = 'kana_stats_v1';
  static const String learnedUnitsStore = 'learned_units_v1';
  static const String seenUnlocksStore = 'seen_unlocks_v1';
  static const String kanjiStatsStore = 'kanji_units_v1';
  static const String wordStatsStore = 'word_stats_v1';

  /// Canonical stores still needing recovery. Empty when export may proceed.
  /// Unmodifiable — a caller cannot mutate the reported set.
  List<String> get blockedStores => List.unmodifiable([
    if (_kana.statsHealth == StoreHealth.recoveryRequired) kanaStatsStore,
    if (_kana.learnedUnitsHealth == StoreHealth.recoveryRequired)
      learnedUnitsStore,
    if (_kana.seenUnlocksHealth == StoreHealth.recoveryRequired)
      seenUnlocksStore,
    if (_kanji.statsHealth == StoreHealth.recoveryRequired) kanjiStatsStore,
    if (_words.statsHealth == StoreHealth.recoveryRequired) wordStatsStore,
    if (_prefs != null && ProgressRestoreJournal.blocksExport(_prefs))
      ProgressRestoreJournal.journalKey,
  ]);

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
