// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';

import 'fake_repository_write_gate.dart';

export 'fake_repository_write_gate.dart' show FakeRepositoryWriteGate;

/// In-memory [TravelFocusRepository] that keeps the production notify and
/// save / retry rules without touching `PreferencesService`.
///
/// It implements only what the contract leaves abstract — [health], [plan],
/// [save] and [flushPending]. The derived commands (`saveFocuses`,
/// `markServed`, `markKanaBoost`, `clear`) are inherited, so the rule that
/// removing the last focus clears the plan cannot differ here from
/// production.
///
/// [writeGate] parks a flush after the in-memory mutation has notified, so a
/// leave-page test can dispose a ViewModel while the write is genuinely in
/// flight. [failWrites] makes the next flush throw and stay dirty.
class FakeTravelFocusRepository extends TravelFocusRepository {
  FakeTravelFocusRepository({
    TravelFocusPlan? plan,
    this.health = StoreHealth.empty,
  }) : _plan = plan ?? TravelFocusPlan.empty {
    _durable = _plan;
  }

  @override
  final StoreHealth health;

  TravelFocusPlan _plan;

  /// What a successful flush has committed. [TravelFocusPlan] is immutable,
  /// so this is a value snapshot rather than a copied collection.
  late TravelFocusPlan _durable;

  Future<void> _tail = Future<void>.value();
  bool _dirty = false;

  /// Parks the next flush until released. The in-memory mutation has
  /// already notified by then.
  FakeRepositoryWriteGate? writeGate;

  /// When true, the next flush throws [StoreWriteFailure] and stays dirty.
  bool failWrites = false;

  /// The last plan a successful flush committed, for asserting that a failed
  /// write did not reach durable storage.
  TravelFocusPlan get durablePlan => _durable;

  @override
  TravelFocusPlan get plan => _plan;

  @override
  Future<void> save(TravelFocusPlan plan) {
    _plan = plan;
    _dirty = true;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Retries a dirty persist without applying a new mutation. Clean is a
  /// no-op — this must not mark the owner dirty just to join the queue.
  @override
  Future<void> flushPending() => _serialized(_flush);

  Future<void> _serialized(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    final gate = writeGate;
    if (gate != null) await gate.pass();
    if (failWrites) {
      throw const StoreWriteFailure('travel_focus_v1');
    }
    _durable = _plan;
    _dirty = false;
  }
}
