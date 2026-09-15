// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

import 'fake_repository_write_gate.dart';

export 'fake_repository_write_gate.dart' show FakeRepositoryWriteGate;

/// In-memory [KanaProgressRepository] that keeps the production notify,
/// save / retry, and snapshot-ownership rules without touching
/// [PreferencesService]. Constructor inputs are copied so a caller cannot
/// alias the owner. A successful flush copies memory onto a durable
/// snapshot; [reloadFromPlatform] reads that snapshot back.
///
/// [writeGate] parks a flush after the in-memory mutation, so leave-page
/// tests can dispose the ViewModel before success or failure lands.
class FakeKanaProgressRepository extends KanaProgressRepository {
  FakeKanaProgressRepository({
    Map<String, KanaStat>? stats,
    Set<String>? learnedUnits,
    Set<String>? seenUnlocks,
    this.statsHealth = StoreHealth.empty,
    this.learnedUnitsHealth = StoreHealth.empty,
    this.seenUnlocksHealth = StoreHealth.empty,
  }) : _stats = Map<String, KanaStat>.of(stats ?? const <String, KanaStat>{}),
       _learnedUnits = Set<String>.of(learnedUnits ?? const <String>{}),
       _seenUnlocks = Set<String>.of(seenUnlocks ?? const <String>{}) {
    _commitDurable();
  }

  @override
  final StoreHealth statsHealth;
  @override
  final StoreHealth learnedUnitsHealth;
  @override
  final StoreHealth seenUnlocksHealth;

  final Map<String, KanaStat> _stats;
  final Set<String> _learnedUnits;
  final Set<String> _seenUnlocks;
  final Map<String, KanaStat> _durableStats = {};
  final Set<String> _durableLearned = {};
  final Set<String> _durableUnlocks = {};

  Future<void> _tail = Future<void>.value();
  bool _dirty = false;
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
  bool isUnitLearned(String unitId) => _learnedUnits.contains(unitId);

  @override
  int get learnedUnitCount => _learnedUnits.length;

  @override
  Set<String> get learnedUnits => Set.unmodifiable(_learnedUnits);

  @override
  Future<void> markUnitLearned(String unitId) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    if (_learnedUnits.add(unitId)) {
      _dirty = true;
      notifyListeners();
    }
    return _serialized(_flush);
  }

  @override
  bool isUnlockSeen(String id) => _seenUnlocks.contains(id);

  @override
  Set<String> get seenUnlocks => Set.unmodifiable(_seenUnlocks);

  @override
  Future<void> markUnlockSeen(String id) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    if (_seenUnlocks.add(id)) {
      _dirty = true;
      notifyListeners();
    }
    return _serialized(_flush);
  }

  @override
  List<Kana> get allKana => kAllKana;

  @override
  List<Kana> kanaForScript(KanaScript script) =>
      allKana.where((k) => k.script == script).toList();

  @override
  List<Kana> gojuonForScript(KanaScript script) =>
      kanaForScript(script).where((k) => k.isGojuon).toList();

  @override
  List<Kana> extendedForScript(KanaScript script) =>
      kanaForScript(script).where((k) => !k.isGojuon).toList();

  @override
  List<Kana> get gojuonKana => allKana.where((k) => k.isGojuon).toList();

  @override
  int seenInSet(List<Kana> set) => set.where((k) => statFor(k).isSeen).length;

  @override
  Map<String, KanaStat> get stats => Map.unmodifiable(_stats);

  @override
  KanaStat statFor(Kana kana) => _stats[kana.id] ?? const KanaStat();

  @override
  int get seenCount => allKana.where((k) => statFor(k).isSeen).length;

  @override
  int get totalCount => allKana.length;

  @override
  int countWithStatus(KanaStatus status) =>
      allKana.where((k) => statFor(k).status == status).length;

  @override
  Future<void> recordAnswer(
    Kana kana, {
    required bool correct,
    required DateTime at,
    int? latencyMs,
    bool listening = false,
  }) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    final scale = kConfusableChars.contains(kana.character) ? 0.5 : 1.0;
    _stats[kana.id] = statFor(kana).recordAnswer(
      correct: correct,
      at: at,
      latencyMs: latencyMs,
      intervalScale: scale,
      listening: listening,
    );
    _dirty = true;
    notifyListeners();
    return _serialized(_flush);
  }

  @override
  Future<void> recordPromptedPractice(Kana kana, {required DateTime at}) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _stats[kana.id] = statFor(kana).recordPromptedPractice(at: at);
    _dirty = true;
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
      ..addAll(_durableStats);
    _learnedUnits
      ..clear()
      ..addAll(_durableLearned);
    _seenUnlocks
      ..clear()
      ..addAll(_durableUnlocks);
    _dirty = false;
    notifyListeners();
  }

  @override
  void replaceFromRestore({
    required Map<String, KanaStat> stats,
    required Set<String> learnedUnits,
    required Set<String> seenUnlocks,
  }) {
    _stats
      ..clear()
      ..addAll(stats);
    _learnedUnits
      ..clear()
      ..addAll(learnedUnits);
    _seenUnlocks
      ..clear()
      ..addAll(seenUnlocks);
    _commitDurable();
    _dirty = false;
    notifyListeners();
  }

  @override
  Future<void> reset() {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _stats.clear();
    _learnedUnits.clear();
    _seenUnlocks.clear();
    _dirty = true;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Joins the serialized persist queue without applying a domain mutation.
  /// Refuses while a restore is in flight or the journal still blocks
  /// writes — the same gates [LocalKanaProgressRepository] uses.
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
    if (!_dirty) return;
    final gate = writeGate;
    if (gate != null) await gate.pass();
    if (failWrites) {
      throw const StoreWriteFailure(ProgressStoreKeys.kanaStats);
    }
    _commitDurable();
    _dirty = false;
  }

  void _commitDurable() {
    _durableStats
      ..clear()
      ..addAll(_stats);
    _durableLearned
      ..clear()
      ..addAll(_learnedUnits);
    _durableUnlocks
      ..clear()
      ..addAll(_seenUnlocks);
  }
}
