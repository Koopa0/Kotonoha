// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';

/// Persists the learner's retained travel focuses and the quiet daily cursor.
///
/// Not a mastery store: saving, switching, or clearing a plan never writes
/// kana or 詞と句 stats. Those stay on their own repositories.
class TravelFocusRepository extends ChangeNotifier {
  TravelFocusRepository._(this._store, StoreLoad<TravelFocusPlan> loaded)
    : _plan = loaded.value,
      health = loaded.health;

  static const String _storageKey = 'travel_focus_v1';
  static const String _lastGoodKey = 'travel_focus_last_good_v1';
  static const String _quarantineKey = 'travel_focus_quarantine_v1';

  final RecoverableStore<TravelFocusPlan> _store;
  TravelFocusPlan _plan;
  final StoreHealth health;

  Future<void> _tail = Future<void>.value();
  int _gen = 0;
  int _persistedGen = 0;

  static Future<TravelFocusRepository> load([PreferencesService? prefs]) async {
    final service = prefs ?? await PreferencesService.create();
    final store = RecoverableStore<TravelFocusPlan>(
      prefs: service,
      primaryKey: _storageKey,
      lastGoodKey: _lastGoodKey,
      quarantineKey: _quarantineKey,
      empty: () => TravelFocusPlan.empty,
      decode: _decode,
    );
    return TravelFocusRepository._(store, await store.load());
  }

  TravelFocusPlan get plan => _plan;

  /// Replaces the in-memory plan and persists. A failed write keeps the
  /// memory value; the next save retries. Never touches mastery stores.
  Future<void> save(TravelFocusPlan plan) {
    _plan = plan;
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  Future<void> saveFocuses(Iterable<TravelFocus> focuses) =>
      save(_plan.withFocuses(focuses));

  Future<void> markKanaBoost(DateTime now) => save(_plan.markKanaBoost(now));

  Future<void> markServed(TravelSceneId scene, DateTime now) =>
      save(_plan.markServed(scene, now));

  Future<void> clear() => save(TravelFocusPlan.empty);

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
