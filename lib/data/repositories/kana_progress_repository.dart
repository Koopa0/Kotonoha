// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// Source of truth for per-kana practice stats. The only stateful unit in the
/// app; quiz session state lives in [QuizViewModel]. Persists through
/// [RecoverableStore] slots (data-loss firewall) over [PreferencesService].
class KanaProgressRepository extends ChangeNotifier {
  KanaProgressRepository._(
    this._prefs,
    this._statsStore,
    this._learnedStore,
    this._unlocksStore,
    StoreLoad<Map<String, KanaStat>> stats,
    StoreLoad<Set<String>> learned,
    StoreLoad<Set<String>> unlocks,
  ) : _stats = stats.value,
      statsHealth = stats.health,
      _learnedUnits = learned.value,
      learnedUnitsHealth = learned.health,
      _seenUnlocks = unlocks.value,
      seenUnlocksHealth = unlocks.health;

  static const String _storageKey = 'kana_stats_v1';
  static const String _statsLastGoodKey = 'kana_stats_last_good_v1';
  static const String _statsQuarantineKey = 'kana_stats_quarantine_v1';
  static const String _learnedKey = 'learned_units_v1';
  static const String _learnedLastGoodKey = 'learned_units_last_good_v1';
  static const String _learnedQuarantineKey = 'learned_units_quarantine_v1';
  static const String _seenUnlocksKey = 'seen_unlocks_v1';
  static const String _seenUnlocksLastGoodKey = 'seen_unlocks_last_good_v1';
  static const String _seenUnlocksQuarantineKey = 'seen_unlocks_quarantine_v1';

  /// Kept for [PreferencesService.reload] — the only trustworthy read path
  /// after a failed platform write/remove (legacy cache divergence).
  final PreferencesService _prefs;

  final RecoverableStore<Map<String, KanaStat>> _statsStore;
  final RecoverableStore<Set<String>> _learnedStore;
  final RecoverableStore<Set<String>> _unlocksStore;

  final Map<String, KanaStat> _stats;

  /// Ids of lessons (or future units) the user has passed. See [Lesson.id].
  final Set<String> _learnedUnits;

  /// Ids of one-time "unlocked" lines the user has already seen. See [Unlock.id].
  final Set<String> _seenUnlocks;

  /// How each persisted store came up at load. [StoreHealth.recoveryRequired]
  /// means the primary was unreadable with no usable last-known-good: the
  /// state starts empty, but the damaged payload still sits under its primary
  /// key (quarantined before the next write replaces it) — it was NOT
  /// mistaken for a legal fresh install. [StoreHealth.preservationPending]
  /// means a recovered value is in use but the damaged raw is not yet
  /// confirmed quarantined.
  final StoreHealth statsHealth;
  final StoreHealth learnedUnitsHealth;
  final StoreHealth seenUnlocksHealth;

  /// Tail of the mutation queue: every persisting mutation (recordAnswer,
  /// markUnitLearned, markUnlockSeen, reset) runs strictly after the previous
  /// one, so read-preserve-write rounds never interleave and lose updates.
  Future<void> _tail = Future<void>.value();

  /// Monotonic per-store versions: a store is dirty (holds unpersisted
  /// mutations) while its generation is ahead of its persisted generation.
  /// Every queued task flushes ALL dirty stores, so a mutation's future only
  /// succeeds once everything submitted before it — including earlier failed
  /// writes to OTHER stores — is truly on disk.
  int _statsGen = 0;
  int _statsPersistedGen = 0;
  int _learnedGen = 0;
  int _learnedPersistedGen = 0;
  int _unlocksGen = 0;
  int _unlocksPersistedGen = 0;

  /// Invalidates in-flight flushes when a restore transaction begins.
  int _restoreBarrier = 0;

  /// True while [prepareForRestore] holds the mutation queue for a restore.
  bool _restoreLocked = false;

  /// True when startup journal recovery could not finish — normal learning
  /// writes must stay refused until [reloadFromPlatform] clears this.
  bool _restoreJournalBlocksWrites = false;

  /// Whether an unfinished restore journal still blocks learning writes.
  bool get isRestoreJournalBlocked => _restoreJournalBlocksWrites;

  /// Loads persisted stats + learned units (or starts empty).
  static Future<KanaProgressRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    final statsStore = RecoverableStore<Map<String, KanaStat>>(
      prefs: service,
      primaryKey: _storageKey,
      lastGoodKey: _statsLastGoodKey,
      quarantineKey: _statsQuarantineKey,
      empty: () => <String, KanaStat>{},
      decode: _decodeStats,
    );
    final learnedStore = RecoverableStore<Set<String>>(
      prefs: service,
      primaryKey: _learnedKey,
      lastGoodKey: _learnedLastGoodKey,
      quarantineKey: _learnedQuarantineKey,
      empty: () => <String>{},
      decode: _decodeIdSet,
    );
    final unlocksStore = RecoverableStore<Set<String>>(
      prefs: service,
      primaryKey: _seenUnlocksKey,
      lastGoodKey: _seenUnlocksLastGoodKey,
      quarantineKey: _seenUnlocksQuarantineKey,
      empty: () => <String>{},
      decode: _decodeIdSet,
    );
    return KanaProgressRepository._(
      service,
      statsStore,
      learnedStore,
      unlocksStore,
      await statsStore.load(),
      await learnedStore.load(),
      await unlocksStore.load(),
    );
  }

  // --- Learned units (sequential lessons) ---

  bool isUnitLearned(String unitId) => _learnedUnits.contains(unitId);

  int get learnedUnitCount => _learnedUnits.length;

  /// Read-only view of learned unit ids for a portable snapshot export
  /// (consistent with [stats] / [seenUnlocks]). It is the raw set — unknown or
  /// retired ids are preserved, never re-derived from the current lesson
  /// dataset — so a snapshot never silently drops progress on content that has
  /// since been renamed or removed.
  Set<String> get learnedUnits => Set.unmodifiable(_learnedUnits);

  /// Marks a lesson/unit as passed and persists. The returned future
  /// completes with an error if persisting failed — the in-memory state
  /// keeps the unit and the next mutation retries the write. A call whose id
  /// is already present still joins the queue: the id may exist only in
  /// memory after an earlier failed write, so success is only reported once
  /// every pending store is really flushed.
  Future<void> markUnitLearned(String unitId) {
    if (_learnedUnits.add(unitId)) {
      _learnedGen++;
      notifyListeners();
    }
    return _serialized(_flushAll);
  }

  // --- Seen unlock lines (the one-time "feature opened" moments) ---

  bool isUnlockSeen(String id) => _seenUnlocks.contains(id);

  /// Read-only view for the pure use_case (consistent with [stats]).
  Set<String> get seenUnlocks => Set.unmodifiable(_seenUnlocks);

  /// Marks an unlock line as seen and persists. The guarded add →
  /// conditional notify is what lets tap-to-dismiss settle instead of
  /// re-triggering the home's listener every frame; an already-seen id still
  /// joins the queue so a pending earlier write is flushed, never faked.
  Future<void> markUnlockSeen(String id) {
    if (_seenUnlocks.add(id)) {
      _unlocksGen++;
      notifyListeners();
    }
    return _serialized(_flushAll);
  }

  /// Every kana the app knows (hiragana + katakana).
  List<Kana> get allKana => kAllKana;

  /// Kana belonging to a given script.
  List<Kana> kanaForScript(KanaScript script) =>
      allKana.where((k) => k.script == script).toList();

  /// Base gojūon kana of a script (the only ones the 11×5 grid can render).
  List<Kana> gojuonForScript(KanaScript script) =>
      kanaForScript(script).where((k) => k.isGojuon).toList();

  /// Non-gojūon kana of a script (dakuten/handakuten/yoon).
  List<Kana> extendedForScript(KanaScript script) =>
      kanaForScript(script).where((k) => !k.isGojuon).toList();

  /// All base gojūon kana (hira + kata, 92) — the home ring's study set so the
  /// 116 extended kana don't dilute the core five-fifty achievement.
  List<Kana> get gojuonKana => allKana.where((k) => k.isGojuon).toList();

  /// Count of kana in [set] the user has seen.
  int seenInSet(List<Kana> set) => set.where((k) => statFor(k).isSeen).length;

  /// Read-only view of every recorded stat, keyed by kana id.
  Map<String, KanaStat> get stats => Map.unmodifiable(_stats);

  /// The stat for [kana], or an empty stat if never practiced.
  KanaStat statFor(Kana kana) => _stats[kana.id] ?? const KanaStat();

  // --- Aggregate views for the home / progress screens ---

  int get seenCount => allKana.where((k) => statFor(k).isSeen).length;

  int get totalCount => allKana.length;

  /// Count of kana currently classified [status].
  int countWithStatus(KanaStatus status) =>
      allKana.where((k) => statFor(k).status == status).length;

  /// Records a single answer for [kana] and persists. The returned future
  /// completes with an error if persisting failed — the in-memory state keeps
  /// the answer and the next mutation retries the write.
  ///
  /// [listening] is true only for a scored sound-to-kana trial with valid
  /// audio. Visual answers and the #49 diagnostic keep the default so
  /// listen fields stay unknown.
  Future<void> recordAnswer(
    Kana kana, {
    required bool correct,
    required DateTime at,
    int? latencyMs,
    bool listening = false,
  }) {
    final current = statFor(kana);
    final scale = kConfusableChars.contains(kana.character) ? 0.5 : 1.0;
    _stats[kana.id] = current.recordAnswer(
      correct: correct,
      at: at,
      latencyMs: latencyMs,
      intervalScale: scale,
      listening: listening,
    );
    _statsGen++;
    notifyListeners();
    return _serialized(_flushAll);
  }

  /// Persists hinted-recall exposure without treating it as a successful
  /// recall or renewing the schedule. See [KanaStat.recordPromptedPractice].
  Future<void> recordPromptedPractice(Kana kana, {required DateTime at}) {
    _stats[kana.id] = statFor(kana).recordPromptedPractice(at: at);
    _statsGen++;
    notifyListeners();
    return _serialized(_flushAll);
  }

  /// Flushes any store still holding unpersisted mutations to disk WITHOUT
  /// applying a new domain mutation — the app-scoped persistence owner calls
  /// this to retry a write that failed after the screen that caused it moved
  /// on. It joins the same serialized queue (never interleaving with an
  /// in-flight write), is a safe no-op when every store is clean, and rethrows
  /// [StoreWriteFailure] like a mutation so the owner can observe the outcome.
  /// It advances no generation itself: [_flushAll] moves persistedGen only on a
  /// confirmed write, exactly as a mutation's flush does.
  Future<void> flushPending() => _serialized(_flushAll);

  /// Invalidates in-flight flushes and refuses new mutations while a restore
  /// transaction writes primaries. Does not await [_tail] — a flush parked on
  /// a platform gate must not block restore, and the barrier prevents it from
  /// writing once it resumes.
  Future<void> prepareForRestore() async {
    _restoreBarrier++;
    _restoreLocked = true;
    _prefs.invalidateInFlightWrites();
  }

  /// Releases the restore lock after [prepareForRestore].
  void finishRestore() {
    _restoreLocked = false;
  }

  /// Blocks or unblocks learning writes while a restore journal needs recovery.
  void setRestoreJournalBlocked(bool blocked) {
    if (_restoreJournalBlocksWrites == blocked) return;
    _restoreJournalBlocksWrites = blocked;
    notifyListeners();
  }

  /// Reloads all three bodies from durable primaries after journal recovery.
  Future<void> reloadFromPlatform() async {
    await _prefs.reload();
    final stats = await _statsStore.load();
    final learned = await _learnedStore.load();
    final unlocks = await _unlocksStore.load();
    _stats
      ..clear()
      ..addAll(stats.value);
    _learnedUnits
      ..clear()
      ..addAll(learned.value);
    _seenUnlocks
      ..clear()
      ..addAll(unlocks.value);
    _statsGen++;
    _learnedGen++;
    _unlocksGen++;
    _statsPersistedGen = _statsGen;
    _learnedPersistedGen = _learnedGen;
    _unlocksPersistedGen = _unlocksGen;
    notifyListeners();
  }

  /// Replaces the three in-memory bodies after a successful restore
  /// transaction. Primaries are already on disk; generations are marked clean.
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
    _statsGen++;
    _learnedGen++;
    _unlocksGen++;
    _statsPersistedGen = _statsGen;
    _learnedPersistedGen = _learnedGen;
    _unlocksPersistedGen = _unlocksGen;
    notifyListeners();
  }

  /// Clears all progress (used by tests and any future "reset" affordance).
  /// Removes exactly the keys this repository owns — primaries plus their
  /// last-known-good and quarantine copies — never a blanket clear. When a
  /// removal fails, in-memory state is reconciled against a FRESH platform
  /// read ([PreferencesService.reload] first — the legacy plugin cache
  /// already mutated before the refused verdict, so it is not disk), with
  /// full [RecoverableStore] recovery semantics, skipping stores a
  /// later-submitted mutation already touched. If even the fresh read
  /// fails, the pre-reset snapshot is restored conservatively and the store
  /// stays dirty — an unknown state is never marked persisted.
  Future<void> reset() {
    final statsBefore = Map<String, KanaStat>.of(_stats);
    final learnedBefore = Set<String>.of(_learnedUnits);
    final unlocksBefore = Set<String>.of(_seenUnlocks);
    _stats.clear();
    _learnedUnits.clear();
    _seenUnlocks.clear();
    _statsGen++;
    _learnedGen++;
    _unlocksGen++;
    final statsGen = _statsGen;
    final learnedGen = _learnedGen;
    final unlocksGen = _unlocksGen;
    // Register the reset action on the queue BEFORE notifying. A listener
    // that submits a mutation during this notification must chain AFTER the
    // removal, not before it — otherwise its flush lands first, the removal
    // then deletes the just-written data, and memory keeps it marked clean,
    // losing it on a fresh restart.
    final run = _serialized(() async {
      var statsRemoved = false;
      var learnedRemoved = false;
      try {
        await _statsStore.removeAll();
        statsRemoved = true;
        if (_statsGen == statsGen) {
          _statsPersistedGen = statsGen;
        } else {
          // A later mutation owns this store now. The successful removal
          // invalidated any prior flush acknowledgement — an earlier queued
          // flush may have written the later state and advanced the persisted
          // generation to it, then this removal erased that durable data. Mint
          // a NEW dirty generation so the later mutation's flush truly
          // rewrites; never inherit an acknowledgement across a destructive
          // removal. persistedGen never regresses.
          _statsGen++;
        }
        await _learnedStore.removeAll();
        learnedRemoved = true;
        if (_learnedGen == learnedGen) {
          _learnedPersistedGen = learnedGen;
        } else {
          _learnedGen++;
        }
        await _unlocksStore.removeAll();
        if (_unlocksGen == unlocksGen) {
          _unlocksPersistedGen = unlocksGen;
        } else {
          _unlocksGen++;
        }
      } catch (_) {
        var reloaded = true;
        try {
          await _prefs.reload();
        } catch (_) {
          reloaded = false;
        }
        // Re-check every generation AFTER the await: a later-submitted
        // mutation owns its store now and must never be overwritten.
        if (!statsRemoved) {
          if (_statsGen == statsGen) {
            _stats
              ..clear()
              ..addAll(reloaded ? _statsStore.recoverCurrent() : statsBefore);
            if (reloaded) {
              // A confirmed fresh durable view — memory matches it.
              _statsPersistedGen = statsGen;
            } else {
              // The snapshot is unverified: mint a NEW dirty generation. An
              // earlier queued flush may have persisted the post-reset empty
              // state and caught persistedGen up to this very generation, so
              // merely "not advancing" it would leave the restored data
              // marked clean and never flushed. persistedGen never regresses.
              _statsGen++;
            }
          } else {
            // A later mutation owns this store's memory, and the removeAll
            // threw — its outcome is UNKNOWN (the primary may already have
            // been removed natively before the reply failed). Don't overwrite
            // the newer memory and don't inherit the pre-remove
            // acknowledgement: mint a new dirty generation so the later queued
            // flush truly rewrites. Redundant if the removal never landed,
            // never a silent loss.
            _statsGen++;
          }
        }
        if (!learnedRemoved) {
          if (_learnedGen == learnedGen) {
            _learnedUnits
              ..clear()
              ..addAll(
                reloaded ? _learnedStore.recoverCurrent() : learnedBefore,
              );
            if (reloaded) {
              _learnedPersistedGen = learnedGen;
            } else {
              _learnedGen++; // unverified snapshot — new dirty generation
            }
          } else {
            _learnedGen++; // later mutation owns memory, removal unknown
          }
        }
        // Unlocks removal runs last: reaching this handler means it did
        // not complete.
        if (_unlocksGen == unlocksGen) {
          _seenUnlocks
            ..clear()
            ..addAll(reloaded ? _unlocksStore.recoverCurrent() : unlocksBefore);
          if (reloaded) {
            _unlocksPersistedGen = unlocksGen;
          } else {
            _unlocksGen++; // unverified snapshot — new dirty generation
          }
        } else {
          _unlocksGen++; // later mutation owns memory, removal unknown
        }
        notifyListeners();
        rethrow;
      }
    });
    notifyListeners();
    return run;
  }

  /// Runs [action] after every previously queued mutation, returning its
  /// future to the caller (so failures surface) while keeping the queue
  /// alive past a failed write.
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

  /// Flushes every dirty store from its CURRENT in-memory state (never a
  /// stale snapshot, so a mutation submitted while an older flush was in
  /// flight is included by its own later flush, not overwritten). Throws on
  /// the first failure so the awaiting mutation reports honestly; whatever
  /// stayed dirty is retried by the next mutation's flush.
  Future<void> _flushAll() async {
    final barrier = _restoreBarrier;
    if (_statsGen != _statsPersistedGen) {
      final gen = _statsGen;
      if (_restoreBarrier != barrier) return;
      await _statsStore.write(
        _encodeStats(),
        commitGuard: () => _restoreBarrier == barrier,
      );
      if (_restoreBarrier != barrier) return;
      _statsPersistedGen = gen;
    }
    if (_learnedGen != _learnedPersistedGen) {
      final gen = _learnedGen;
      if (_restoreBarrier != barrier) return;
      await _learnedStore.write(
        jsonEncode(_learnedUnits.toList()),
        commitGuard: () => _restoreBarrier == barrier,
      );
      if (_restoreBarrier != barrier) return;
      _learnedPersistedGen = gen;
    }
    if (_unlocksGen != _unlocksPersistedGen) {
      final gen = _unlocksGen;
      if (_restoreBarrier != barrier) return;
      await _unlocksStore.write(
        jsonEncode(_seenUnlocks.toList()),
        commitGuard: () => _restoreBarrier == barrier,
      );
      if (_restoreBarrier != barrier) return;
      _unlocksPersistedGen = gen;
    }
  }

  String _encodeStats() =>
      jsonEncode(_stats.map((k, v) => MapEntry(k, v.toJson())));

  static DecodeResult<Map<String, KanaStat>> _decodeStats(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const DecodeCorrupt();
    }
    if (decoded is! Map<String, dynamic>) return const DecodeCorrupt();
    final stats = <String, KanaStat>{};
    var dropped = 0;
    decoded.forEach((key, value) {
      try {
        stats[key] = KanaStat.fromJson(value as Map<String, dynamic>);
      } catch (_) {
        dropped++; // one bad entry must not wipe the rest
      }
    });
    return DecodeOk(stats, dropped: dropped);
  }

  static DecodeResult<Set<String>> _decodeIdSet(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const DecodeCorrupt();
    }
    if (decoded is! List<dynamic>) return const DecodeCorrupt();
    final ids = <String>{};
    var dropped = 0;
    for (final element in decoded) {
      if (element is String) {
        ids.add(element);
      } else {
        dropped++; // one bad element must not wipe the rest
      }
    }
    return DecodeOk(ids, dropped: dropped);
  }
}
