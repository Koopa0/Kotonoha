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

/// Source of truth for an explicit prior-range check, so leaving mid-way can
/// resume unanswered kana without inventing grades. Not a second ability
/// store: per-kana SRS still lives on [KanaProgressRepository].
///
/// Formal ViewModels and `bootstrap()` depend on this contract, not on a
/// particular store; [LocalPlacementCheckRepository] is the production owner
/// and a test fake may replace it when it keeps the same notify and
/// save / retry rules.
///
/// Storage keys deliberately do not appear here. They belong to the owner
/// that has storage; a substitute has none, and a contract that named them
/// would be describing one implementation.
abstract class PlacementCheckRepository extends ChangeNotifier {
  /// Loads the production owner. Tests that need a substitute construct a
  /// fake; they do not go through this factory.
  static Future<PlacementCheckRepository> load([PreferencesService? prefs]) =>
      LocalPlacementCheckRepository.load(prefs);

  /// Startup health of the backing store, surfaced as a recovery notice.
  StoreHealth get health;

  /// The current draft. [PlacementDraft] is immutable and hands out
  /// unmodifiable collections, so a reader cannot write through this.
  PlacementDraft get draft;

  /// Replaces the in-memory draft and persists it. A failed write keeps the
  /// memory value; the next save retries. Never invents missing answers.
  Future<void> save(PlacementDraft draft);

  /// Retries a pending write without applying a new mutation.
  Future<void> flushPending();

  /// Refuses new mutations and drains every queued persistence future, so no
  /// stale flush can land after a restore begins.
  Future<void> prepareForRestore();

  /// Releases the restore lock taken by [prepareForRestore].
  void finishRestore();

  /// Drops any draft during a progress restore, before the journal commits.
  /// The snapshot's portable bodies are authoritative; a draft from before
  /// the restore must not re-apply learned rows on the results screen.
  Future<void> discardForRestore();

  Future<void> reloadFromPlatform();

  /// Hides a stale draft in memory while a durable discard is still pending.
  /// Does not touch storage — bootstrap recovery finishes the removal.
  void hideDraftWhileDiscardPending();

  /// Clearing is saving the empty draft. Defined here rather than on each
  /// implementation so the two cannot disagree about what "cleared" means —
  /// though unlike travel focus, this one carries no rule of its own.
  Future<void> clear() => save(PlacementDraft.empty);
}

/// Production owner of [PlacementCheckRepository]. Persists through a
/// [RecoverableStore] slot (data-loss firewall) over [PreferencesService].
class LocalPlacementCheckRepository extends PlacementCheckRepository {
  LocalPlacementCheckRepository._(this._store, StoreLoad<PlacementDraft> loaded)
    : _draft = loaded.value,
      health = loaded.health;

  static const String storageKey = ProgressStoreKeys.placementCheck;
  static const String lastGoodKey = ProgressStoreKeys.placementCheckLastGood;
  static const String quarantineKey =
      ProgressStoreKeys.placementCheckQuarantine;

  static const List<String> durableKeys = ProgressStoreKeys.placementDurable;

  final RecoverableStore<PlacementDraft> _store;
  PlacementDraft _draft;
  @override
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

  static Future<LocalPlacementCheckRepository> load([
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
    return LocalPlacementCheckRepository._(
      store,
      StoreLoad(loaded.health, draft),
    );
  }

  @override
  PlacementDraft get draft => _draft;

  @override
  Future<void> save(PlacementDraft draft) {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    _draft = draft;
    _gen++;
    notifyListeners();
    return _serialized(_flush);
  }

  @override
  Future<void> prepareForRestore() async {
    _restoreLocked = true;
    await _tail;
    _restoreBarrier++;
  }

  @override
  void finishRestore() {
    _restoreLocked = false;
  }

  @override
  Future<void> discardForRestore() => _discardForRestore();

  /// Re-reads the draft from durable storage after a restore rollback.
  @override
  Future<void> reloadFromPlatform() => _reloadFromPlatform();

  @override
  void hideDraftWhileDiscardPending() {
    if (!_draft.hasProgress) return;
    _draft = PlacementDraft.empty;
    _gen++;
    notifyListeners();
  }

  @override
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
