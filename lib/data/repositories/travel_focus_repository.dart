// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';

/// Source of truth for the learner's retained travel focuses and the quiet
/// daily cursor. Formal ViewModels and the app-scoped persistence owner
/// depend on this contract, not on a particular store;
/// [LocalTravelFocusRepository] is the production owner and a test fake may
/// replace it when it keeps the same notify and save / retry rules.
///
/// Not a mastery store: saving, switching, or clearing a plan never writes
/// kana or 詞と句 stats. Those stay on their own repositories.
abstract class TravelFocusRepository extends ChangeNotifier {
  /// Loads the production owner. Tests that need a substitute construct a
  /// fake; they do not go through this factory.
  static Future<TravelFocusRepository> load([PreferencesService? prefs]) =>
      LocalTravelFocusRepository.load(prefs);

  /// Startup health of the backing store, surfaced as a recovery notice.
  StoreHealth get health;

  /// The current plan. [TravelFocusPlan] is immutable and hands out
  /// unmodifiable collections, so a reader cannot write through this.
  TravelFocusPlan get plan;

  /// Replaces the in-memory plan and persists it. A failed write keeps the
  /// memory value; the next save retries. Never touches mastery stores.
  Future<void> save(TravelFocusPlan plan);

  /// Retries a pending write without applying a new mutation. A clean owner
  /// is a no-op: this must not mark the owner dirty just to join the queue.
  Future<void> flushPending();

  // The commands below are derived from [plan] and [save] and are defined
  // once, here, rather than on each implementation. Clearing when the last
  // focus is removed is a rule, not plumbing; an implementation that
  // restated it could drift from production while its tests stayed green.

  /// Retains [focuses]. Removing the last one clears the plan rather than
  /// storing an inactive one.
  Future<void> saveFocuses(Iterable<TravelFocus> focuses) {
    final next = plan.withFocuses(focuses);
    if (!next.isActive) return clear();
    return save(next);
  }

  Future<void> markKanaBoost(DateTime now) => save(plan.markKanaBoost(now));

  Future<void> markServed(TravelSceneId scene, DateTime now) =>
      save(plan.markServed(scene, now));

  Future<void> clear() => save(TravelFocusPlan.empty);
}

/// Production owner of [TravelFocusRepository]. Persists through a
/// [RecoverableStore] slot (data-loss firewall) over [PreferencesService].
class LocalTravelFocusRepository extends TravelFocusRepository {
  LocalTravelFocusRepository._(this._store, StoreLoad<TravelFocusPlan> loaded)
    : _plan = loaded.value,
      health = loaded.health;

  static const String _storageKey = 'travel_focus_v1';
  static const String _lastGoodKey = 'travel_focus_last_good_v1';
  static const String _quarantineKey = 'travel_focus_quarantine_v1';

  final RecoverableStore<TravelFocusPlan> _store;
  TravelFocusPlan _plan;
  @override
  final StoreHealth health;

  Future<void> _tail = Future<void>.value();
  int _gen = 0;
  int _persistedGen = 0;

  static Future<LocalTravelFocusRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    final store = RecoverableStore<TravelFocusPlan>(
      prefs: service,
      primaryKey: _storageKey,
      lastGoodKey: _lastGoodKey,
      quarantineKey: _quarantineKey,
      empty: () => TravelFocusPlan.empty,
      decode: _decode,
    );
    return LocalTravelFocusRepository._(store, await store.load());
  }

  @override
  TravelFocusPlan get plan => _plan;

  @override
  Future<void> save(TravelFocusPlan plan) {
    _plan = plan;
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  @override
  Future<void> flushPending() => _serialized(_flush);

  Future<void> _serialized(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _flush() async {
    if (_gen == _persistedGen) return;
    final gen = _gen;
    await _store.write(jsonEncode(_plan.toJson()));
    _persistedGen = gen;
  }

  static DecodeResult<TravelFocusPlan> _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const DecodeCorrupt();
    }
    if (decoded is! Map<String, dynamic>) return const DecodeCorrupt();
    try {
      return DecodeOk(TravelFocusPlan.fromJson(decoded));
    } catch (_) {
      return const DecodeCorrupt();
    }
  }
}
