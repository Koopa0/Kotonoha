// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/placement_check.dart';

import 'fake_repository_write_gate.dart';

export 'fake_repository_write_gate.dart' show FakeRepositoryWriteGate;

/// In-memory [PlacementCheckRepository] that keeps the production notify and
/// save / retry rules without touching `PreferencesService`.
///
/// It implements only what the contract leaves abstract; `clear` is
/// inherited. [PlacementDraft] is immutable and copies its input collections,
/// so no defensive copying is needed here.
///
/// [writeGate] parks a flush after the in-memory mutation has notified, so a
/// leave-page test can dispose a ViewModel while the write is genuinely in
/// flight. [failWrites] makes the next flush throw and stay dirty.
class FakePlacementCheckRepository extends PlacementCheckRepository {
  FakePlacementCheckRepository({
    PlacementDraft? draft,
    this.health = StoreHealth.empty,
  }) : _draft = draft ?? PlacementDraft.empty {
    _durable = _draft;
  }

  @override
  final StoreHealth health;

  PlacementDraft _draft;

  /// What a successful flush has committed. [PlacementDraft] is immutable, so
  /// this is a value snapshot rather than a copied collection.
  late PlacementDraft _durable;

  Future<void> _tail = Future<void>.value();

  // Generation counters rather than a dirty flag, mirroring the local owner:
  // a flush commits the generation it started with, so a mutation arriving
  // while a write is parked stays pending instead of riding it.
  int _gen = 0;
  int _persistedGen = 0;

  bool _restoreLocked = false;

  /// Parks the next flush until released. The in-memory mutation has already
  /// notified by then.
  FakeRepositoryWriteGate? writeGate;

  /// When true, the next flush throws [StoreWriteFailure] and stays dirty.
  bool failWrites = false;

  /// The last draft a successful flush committed, for asserting that a failed
  /// write did not reach durable storage.
  PlacementDraft get durableDraft => _durable;

  @override
  PlacementDraft get draft => _draft;

  @override
  Future<void> save(PlacementDraft draft) {
    if (_restoreLocked) {
      return Future<void>.error(const ProgressRestoreInProgress());
    }
    _draft = draft;
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Retries a dirty persist without applying a new mutation. Clean is a
  /// no-op — this must not mark the owner dirty just to join the queue.
  @override
  Future<void> flushPending() {
    if (_restoreLocked) {
      return Future<void>.error(const ProgressRestoreInProgress());
    }
    return _serialized(_flush);
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
  Future<void> discardForRestore() async {
    _draft = PlacementDraft.empty;
    _durable = PlacementDraft.empty;
    _gen++;
    _persistedGen = _gen;
    notifyListeners();
  }

  @override
  Future<void> reloadFromPlatform() async {
    _draft = _durable;
    _gen = _persistedGen = 0;
    notifyListeners();
  }

  @override
  void hideDraftWhileDiscardPending() {
    if (!_draft.hasProgress) return;
    _draft = PlacementDraft.empty;
    _gen++;
    notifyListeners();
  }

  Future<void> _serialized(Future<void> Function() action) {
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
    // before awaiting the platform, so it persists the draft the write
    // started with; committing `_draft` after the await would fold in any
    // change made while the write was in flight.
    final gen = _gen;
    final pending = _draft;
    final gate = writeGate;
    if (gate != null) await gate.pass();
    if (failWrites) {
      throw const StoreWriteFailure('placement_check_v1');
    }
    _durable = pending;
    _persistedGen = gen;
  }
}
