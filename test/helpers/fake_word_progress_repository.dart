// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/word_stat.dart';

import 'fake_kana_progress_repository.dart';

/// In-memory [WordProgressRepository] that keeps the production notify,
/// save / retry, and snapshot-ownership rules without touching
/// [PreferencesService]. Constructor inputs are copied so a caller cannot
/// alias the owner. A successful flush copies memory onto a durable
/// snapshot; [reloadFromPlatform] reads that snapshot back.
///
/// Learning rules stay on [WordStat]: [recordAnswer], [introduce] and
/// [markIntroduced] delegate to that value type. This is not a second
/// scheduler.
///
/// [writeGate] parks a flush after the in-memory mutation, so leave-page
/// tests can dispose the ViewModel before success or failure lands.
class FakeWordProgressRepository extends WordProgressRepository {
  FakeWordProgressRepository({
    Map<String, WordStat>? stats,
    this.statsHealth = StoreHealth.empty,
  }) : _stats = Map<String, WordStat>.of(stats ?? const <String, WordStat>{}) {
    _commitDurable();
  }

  @override
  final StoreHealth statsHealth;

  final Map<String, WordStat> _stats;
  final Map<String, WordStat> _durableStats = {};

  Future<void> _tail = Future<void>.value();

  /// Monotonic store version: dirty while [_statsGen] is ahead of
  /// [_statsPersistedGen]; mirrors [LocalWordProgressRepository].
  int _statsGen = 0;
  int _statsPersistedGen = 0;

  bool _restoreLocked = false;
  bool _restoreJournalBlocksWrites = false;

  /// Parks the next flush until released. The in-memory mutation has
  /// already notified.
  FakeRepositoryWriteGate? writeGate;

  /// When true, the next flush throws [StoreWriteFailure] and stays dirty.
  bool failWrites = false;

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
  Map<String, WordStat> get stats => Map.unmodifiable(_stats);

  @override
  WordStat statForItem(String progressId) =>
      _stats[progressId] ?? const WordStat();

  @override
  int get seenItemCount => _stats.values.where((s) => s.isSeen).length;

  @override
  Future<void> introduce(String progressId, {required DateTime at}) {
    if (statForItem(progressId).isSeen) return flushPending();
    return recordAnswer(progressId, correct: true, at: at);
  }

  @override
  Future<void> markIntroduced(String progressId, {required DateTime at}) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    final current = statForItem(progressId);
    if (current.isSeen) return flushPending();
    _stats[progressId] = current.markIntroduced(at: at);
    _statsGen++;
    notifyListeners();
    return _serialized(_flush);
  }

  @override
  Future<void> recordAnswer(
    String progressId, {
    required bool correct,
    required DateTime at,
  }) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _stats[progressId] = statForItem(progressId)
        .recordAnswer(correct: correct, at: at);
    _statsGen++;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Retries a dirty persist without applying a new mutation. Clean is a
  /// no-op — this must not mark the owner dirty just to join the queue.
  @override
  Future<void> flushPending() => _serialized(_flush);

  @override
  List<String> dueItemIds(DateTime now) {
    final due =
        _stats.entries
            .where((e) => e.value.dueAt != null && !e.value.dueAt!.isAfter(now))
            .toList()
          ..sort((a, b) => a.value.dueAt!.compareTo(b.value.dueAt!));
    return [for (final e in due) e.key];
  }

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
      ..addAll(_durableStats);
    _statsGen++;
    _statsPersistedGen = _statsGen;
    notifyListeners();
  }

  @override
  void replaceFromRestore({required Map<String, WordStat> stats}) {
    _stats
      ..clear()
      ..addAll(stats);
    _commitDurable();
    _statsGen++;
    _statsPersistedGen = _statsGen;
    notifyListeners();
  }

  @override
  Future<void> reset() {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _stats.clear();
    _statsGen++;
    notifyListeners();
    return _serialized(_flushReset);
  }

  Future<void> _flushReset() async {
    if (_statsGen == _statsPersistedGen) return;
    final gen = _statsGen;
    final payload = Map<String, WordStat>.of(_stats);
    final gate = writeGate;
    if (gate != null) await gate.pass();
    try {
      if (failWrites) {
        throw const StoreWriteFailure(ProgressStoreKeys.wordStats);
      }
      _commitDurable(payload);
      if (_statsGen == gen) {
        _statsPersistedGen = gen;
      }
    } catch (_) {
      // Re-check generation after the await: a later-submitted mutation
      // owns the store now and must never be overwritten.
      if (_statsGen == gen) {
        // The optimistic clear must not survive a refused persist — memory
        // agrees with the durable snapshot that reset failed to overwrite.
        _stats
          ..clear()
          ..addAll(_durableStats);
        _statsPersistedGen = gen;
      } else {
        _statsGen++;
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Joins the serialized persist queue without applying a domain mutation.
  /// Refuses while a restore is in flight or the journal still blocks
  /// writes — the same gates [LocalWordProgressRepository] uses.
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
    if (_statsGen == _statsPersistedGen) return;
    final gen = _statsGen;
    final payload = Map<String, WordStat>.of(_stats);
    final gate = writeGate;
    if (gate != null) await gate.pass();
    if (failWrites) {
      throw const StoreWriteFailure(ProgressStoreKeys.wordStats);
    }
    _commitDurable(payload);
    if (_statsGen == gen) {
      _statsPersistedGen = gen;
    }
  }

  void _commitDurable([Map<String, WordStat>? payload]) {
    final source = payload ?? _stats;
    _durableStats
      ..clear()
      ..addAll(source);
  }
}
