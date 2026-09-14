// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_restore_placement_discard.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/placement_check.dart';

/// Persists an explicit prior-range check so leaving mid-way can resume
/// unanswered kana without inventing grades. Not a second ability store:
/// per-kana SRS still lives on [KanaProgressRepository].
class PlacementCheckRepository extends ChangeNotifier {
  PlacementCheckRepository._(this._store, StoreLoad<PlacementDraft> loaded)
    : _draft = loaded.value,
      health = loaded.health;

  static const String storageKey = ProgressStoreKeys.placementCheck;
  static const String lastGoodKey = ProgressStoreKeys.placementCheckLastGood;
  static const String quarantineKey =
      ProgressStoreKeys.placementCheckQuarantine;

  static const List<String> durableKeys = ProgressStoreKeys.placementDurable;

  final RecoverableStore<PlacementDraft> _store;
  PlacementDraft _draft;
  final StoreHealth health;

  Future<void> _tail = Future<void>.value();
  int _gen = 0;
  int _persistedGen = 0;
  int _restoreBarrier = 0;
  bool _restoreLocked = false;

  Future<void>? _blockedWriteFuture() {
    if (_restoreLocked) {
      return Future<void>.error(const ProgressRestoreInProgress());
    }
    return null;
  }

  static Future<PlacementCheckRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    final store = RecoverableStore<PlacementDraft>(
      prefs: service,
      primaryKey: storageKey,
      lastGoodKey: lastGoodKey,
      quarantineKey: quarantineKey,
      empty: () => PlacementDraft.empty,
      decode: _decode,
    );
    final loaded = await store.load();
    final draft = ProgressRestorePlacementDiscard.isPending(service)
        ? PlacementDraft.empty
        : loaded.value;
    return PlacementCheckRepository._(store, StoreLoad(loaded.health, draft));
  }

  PlacementDraft get draft => _draft;

  /// Replaces the in-memory draft and persists. A failed write keeps the
  /// memory value; the next save retries. Never invents missing answers.
  Future<void> save(PlacementDraft draft) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _draft = draft;
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  Future<void> clear() => save(PlacementDraft.empty);

  /// Refuses new mutations, drains every queued persistence future, then bumps
  /// the restore barrier so no stale flush can land after the drain completes.
  Future<void> prepareForRestore() async {
    _restoreLocked = true;
    await _tail;
    _restoreBarrier++;
  }

  /// Releases the restore lock after [prepareForRestore].
  void finishRestore() {
    _restoreLocked = false;
  }

  /// Drops any placement draft during a progress restore, before the journal
  /// commits. The snapshot's five portable bodies are authoritative; a draft
  /// from before restore must not re-apply learned rows on the results screen.
  Future<void> discardForRestore() => _discardForRestore();

  /// Re-reads the draft from durable storage after a restore rollback.
  Future<void> reloadFromPlatform() => _reloadFromPlatform();

  /// Hides a stale draft in memory when durable discard is still pending.
  /// Does not touch disk — bootstrap recovery will finish removal.
  void hideDraftWhileDiscardPending() {
    if (!_draft.hasProgress) return;
    _draft = PlacementDraft.empty;
    _gen++;
    notifyListeners();
  }

  Future<void> flushPending() {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    return _serialized(_flush);
  }

  Future<void> _discardForRestore() async {
    await _store.removeAll();
    _draft = PlacementDraft.empty;
    _gen++;
    _persistedGen = _gen;
    notifyListeners();
  }

  Future<void> _reloadFromPlatform() async {
    final loaded = await _store.load();
    _draft = loaded.value;
    _gen = _persistedGen = 0;
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
    final gen = _gen;
    final barrier = _restoreBarrier;
    if (_restoreBarrier != barrier) return;
    await _store.write(
      jsonEncode(_draft.toJson()),
      commitGuard: () => _restoreBarrier == barrier,
    );
    if (_restoreBarrier != barrier) return;
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
