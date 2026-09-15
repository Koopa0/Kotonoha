// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

import 'fake_repository_write_gate.dart';

export 'fake_repository_write_gate.dart' show FakeRepositoryWriteGate;

/// In-memory [KanjiReadingRepository] that keeps the production notify and
/// save / retry rules without touching `PreferencesService`.
///
/// It implements only what the contract leaves abstract. `allKanji`,
/// `statForUnit`, `seenUnitCount`, `stats` and `dueUnitIds` are inherited, so
/// the due-ordering rule cannot differ here from production.
///
/// [writeGate] parks a flush after the in-memory mutation has notified, so a
/// leave-page test can dispose a ViewModel while the write is genuinely in
/// flight. [failWrites] makes the next flush throw and stay dirty.
class FakeKanjiReadingRepository extends KanjiReadingRepository {
  FakeKanjiReadingRepository({
    Map<String, ReadingStat>? stats,
    this.statsHealth = StoreHealth.empty,
  }) : _stats = Map<String, ReadingStat>.of(
         stats ?? const <String, ReadingStat>{},
       ) {
    _durable.addAll(_stats);
  }

  @override
  final StoreHealth statsHealth;

  final Map<String, ReadingStat> _stats;

  /// What a successful flush has committed, for asserting that a failed write
  /// did not reach durable storage.
  final Map<String, ReadingStat> _durable = <String, ReadingStat>{};

  Future<void> _tail = Future<void>.value();

  // Generation counters rather than a dirty flag, mirroring the local owner:
  // a flush commits the generation it started with, so a mutation that
  // arrives while a write is parked stays pending instead of riding it.
  int _gen = 0;
  int _persistedGen = 0;

  bool _restoreLocked = false;
  bool _restoreJournalBlocksWrites = false;

  /// Parks the next flush until released. The in-memory mutation has already
  /// notified by then.
  FakeRepositoryWriteGate? writeGate;

  /// When true, the next flush throws [StoreWriteFailure] and stays dirty.
  bool failWrites = false;

  /// The stats a successful flush committed.
  Map<String, ReadingStat> get durableStats =>
      UnmodifiableMapView<String, ReadingStat>(_durable);

  @override
  @protected
  Map<String, ReadingStat> get statsView =>
      UnmodifiableMapView<String, ReadingStat>(_stats);

  @override
  bool get isRestoreJournalBlocked => _restoreJournalBlocksWrites;

  Future<void>? _blockedWriteFuture() {
    if (_restoreJournalBlocksWrites) {
      return Future<void>.error(const ProgressRestoreJournalBlocked());
    }
    if (_restoreLocked) {
      return Future<void>.error(const ProgressRestoreInProgress());
    }
    return null;
  }

  @override
  Future<void> recordAnswer(
    String unitId, {
    required bool correct,
    required DateTime at,
  }) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _stats[unitId] = statForUnit(unitId).recordAnswer(correct: correct, at: at);
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Retries a dirty persist without applying a new mutation. Clean is a
  /// no-op — this must not mark the owner dirty just to join the queue.
  @override
  Future<void> flushPending() => _serialized(_flush);

  @override
  Future<void> prepareForRestore() async {
    _restoreLocked = true;
    await _tail;
  }

  @override
  void finishRestore() {
    _restoreLocked = false;
  }

  @override
  void setRestoreJournalBlocked(bool blocked) {
    if (_restoreJournalBlocksWrites == blocked) return;
    _restoreJournalBlocksWrites = blocked;
    notifyListeners();
  }

  @override
  Future<void> reloadFromPlatform() async {
    _stats
      ..clear()
      ..addAll(_durable);
    _persistedGen = _gen;
    notifyListeners();
  }

  @override
  void replaceFromRestore({required Map<String, ReadingStat> stats}) {
    _stats
      ..clear()
      ..addAll(stats);
    _durable
      ..clear()
      ..addAll(stats);
    _persistedGen = _gen;
    notifyListeners();
  }

  @override
  Future<void> reset() {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _stats.clear();
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  Future<void> _serialized(Future<void> Function() action) {
    if (_restoreJournalBlocksWrites) {
      return Future<void>.error(const ProgressRestoreJournalBlocked());
    }
    if (_restoreLocked) {
      return Future<void>.error(const ProgressRestoreInProgress());
    }
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _flush() async {
    if (_gen == _persistedGen) return;
    // Snapshot both before parking. The local owner encodes its payload
    // before awaiting the platform, so it persists the stats the write
    // started with; committing the live map after the await would fold in any
    // change made while the write was in flight.
    final gen = _gen;
    final pending = Map<String, ReadingStat>.of(_stats);
    final gate = writeGate;
    if (gate != null) await gate.pass();
    if (failWrites) {
      throw const StoreWriteFailure(ProgressStoreKeys.kanjiStats);
    }
    _durable
      ..clear()
      ..addAll(pending);
    _persistedGen = gen;
  }
}
