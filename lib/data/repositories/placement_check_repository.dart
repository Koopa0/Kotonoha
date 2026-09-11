// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/placement_check.dart';

/// Persists an explicit prior-range check so leaving mid-way can resume
/// unanswered kana without inventing grades. Not a second ability store:
/// per-kana SRS still lives on [KanaProgressRepository].
class PlacementCheckRepository extends ChangeNotifier {
  PlacementCheckRepository._(this._store, StoreLoad<PlacementDraft> loaded)
    : _draft = loaded.value,
      health = loaded.health;

  static const String _storageKey = 'placement_check_v1';
  static const String _lastGoodKey = 'placement_check_last_good_v1';
  static const String _quarantineKey = 'placement_check_quarantine_v1';

  final RecoverableStore<PlacementDraft> _store;
  PlacementDraft _draft;
  final StoreHealth health;

  Future<void> _tail = Future<void>.value();
  int _gen = 0;
  int _persistedGen = 0;

  static Future<PlacementCheckRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    final store = RecoverableStore<PlacementDraft>(
      prefs: service,
      primaryKey: _storageKey,
      lastGoodKey: _lastGoodKey,
      quarantineKey: _quarantineKey,
      empty: () => PlacementDraft.empty,
      decode: _decode,
    );
    return PlacementCheckRepository._(store, await store.load());
  }

  PlacementDraft get draft => _draft;

  /// Replaces the in-memory draft and persists. A failed write keeps the
  /// memory value; the next save retries. Never invents missing answers.
  Future<void> save(PlacementDraft draft) {
    _draft = draft;
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  Future<void> clear() => save(PlacementDraft.empty);

  Future<void> flushPending() => _serialized(_flush);

  Future<void> _serialized(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _flush() async {
    if (_gen == _persistedGen) return;
    final gen = _gen;
    await _store.write(jsonEncode(_draft.toJson()));
    _persistedGen = gen;
  }

  static DecodeResult<PlacementDraft> _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const DecodeCorrupt();
    }
    if (decoded is! Map<String, dynamic>) return const DecodeCorrupt();
    try {
      return DecodeOk(PlacementDraft.fromJson(decoded));
    } catch (_) {
      return const DecodeCorrupt();
    }
  }
}
