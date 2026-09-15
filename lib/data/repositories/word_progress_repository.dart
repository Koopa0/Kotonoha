// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/progress_store_keys.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/word_stat.dart';

/// Source of truth for per-item 詞と句 stats. Formal ViewModels, the
/// app-scoped persistence owner, and restore use cases depend on this
/// contract — not on a particular store. [LocalWordProgressRepository] is
/// the production owner. A test fake may replace it when it keeps the same
/// notify, save / retry, and snapshot-ownership rules.
///
/// Mirrors [KanjiReadingRepository] but keyed by progress id (`word:いぬ` /
/// `phrase:そらが あおい` — namespaced so a word and a same-written phrase can
/// never collide) and persisted separately under `word_stats_v1` — the three
/// tracks' progress never mixes (ADR). [WordStat] stays a distinct value type
/// from KanaStat / ReadingStat; this is not a generic SRS engine.
///
/// Mode authority: 渡し舟 INTRODUCES an item ([introduce] — first meeting
/// only, a no-op once seen), while the colder retrieval modes (文字起こし's
/// objective assembly, 黙読's cold self-graded read, 聞き取り after confirmed
/// playback) own the schedule via [recordAnswer].
abstract class WordProgressRepository extends ChangeNotifier {
  /// Loads the production owner. Tests that need a substitute construct a
  /// fake; they do not go through this factory.
  static Future<WordProgressRepository> load([PreferencesService? prefs]) =>
      LocalWordProgressRepository.load(prefs);

  StoreHealth get statsHealth;

  bool get isRestoreJournalBlocked;

  Map<String, WordStat> get stats;
  WordStat statForItem(String progressId);
  int get seenItemCount;

  Future<void> introduce(String progressId, {required DateTime at});
  Future<void> markIntroduced(String progressId, {required DateTime at});
  Future<void> recordAnswer(
    String progressId, {
    required bool correct,
    required DateTime at,
  });

  Future<void> flushPending();
  List<String> dueItemIds(DateTime now);

  Future<void> prepareForRestore();
  void finishRestore();
  void setRestoreJournalBlocked(bool blocked);
  Future<void> reloadFromPlatform();
  void replaceFromRestore({required Map<String, WordStat> stats});
  Future<void> reset();
}

/// Production owner of [WordProgressRepository]. Persists through a
/// [RecoverableStore] slot (data-loss firewall) over [PreferencesService].
class LocalWordProgressRepository extends WordProgressRepository {
  LocalWordProgressRepository._(
    this._prefs,
    this._store,
    StoreLoad<Map<String, WordStat>> stats,
  ) : _stats = stats.value,
      statsHealth = stats.health;

  static const String _storageKey = ProgressStoreKeys.wordStats;
  static const String _lastGoodKey = ProgressStoreKeys.wordStatsLastGood;
  static const String _quarantineKey = ProgressStoreKeys.wordStatsQuarantine;

  /// Kept for [PreferencesService.reload] — the only trustworthy read path
  /// after a failed platform write/remove (legacy cache divergence).
  final PreferencesService _prefs;

  final RecoverableStore<Map<String, WordStat>> _store;
  final Map<String, WordStat> _stats;

  /// How the persisted store came up at load (see [KanjiReadingRepository]
  /// for the full health semantics).
  @override
  final StoreHealth statsHealth;

  /// Tail of the mutation queue: every persisting mutation runs strictly
  /// after the previous one, so read-preserve-write rounds never interleave.
  Future<void> _tail = Future<void>.value();

  /// Monotonic store version: dirty while [_statsGen] is ahead of
  /// [_statsPersistedGen]; see [KanjiReadingRepository] for the contract.
  int _statsGen = 0;
  int _statsPersistedGen = 0;

  int _restoreBarrier = 0;
  bool _restoreLocked = false;
  bool _restoreJournalBlocksWrites = false;

  /// Whether an unfinished restore journal still blocks learning writes.
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

  static Future<LocalWordProgressRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    final store = RecoverableStore<Map<String, WordStat>>(
      prefs: service,
      primaryKey: _storageKey,
      lastGoodKey: _lastGoodKey,
      quarantineKey: _quarantineKey,
      empty: () => <String, WordStat>{},
      decode: _decodeStats,
    );
    return LocalWordProgressRepository._(service, store, await store.load());
  }

  /// Read-only view of every recorded stat, keyed by progress id.
  @override
  Map<String, WordStat> get stats => Map.unmodifiable(_stats);

  /// The stat for a progress id, or an empty stat if never practised.
  @override
  WordStat statForItem(String progressId) =>
      _stats[progressId] ?? const WordStat();

  /// Count of items the learner has met at least once.
  @override
  int get seenItemCount => _stats.values.where((s) => s.isSeen).length;

  /// First meeting of an item (渡し舟's encode beat): counts as one correct
  /// untimed answer so the item enters the schedule (level 0 → 1) — but ONLY
  /// the first time. Re-ferrying a seen item is exposure, not schedule: the
  /// analytics log still records the attempt, and domain counts / SRS stay
  /// put. The returned future still follows the persistence owner's contract:
  /// success means every dirty store is on disk. A clean seen item is an
  /// honest no-op; a pending failed write is flushed (never a fake success).
  @override
  Future<void> introduce(String progressId, {required DateTime at}) {
    if (statForItem(progressId).isSeen) return flushPending();
    return recordAnswer(progressId, correct: true, at: at);
  }

  /// 黙読 / transfer intake: the learner met the item (often after a hint)
  /// but this is not an unprompted recall. First meeting only; seen items
  /// are an honest no-op that still flushes a pending write.
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

  /// Records one graded answer for an item and persists. The returned future
  /// completes with an error if persisting failed — the in-memory state keeps
  /// the answer and the next mutation retries the write.
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

  /// Flushes the store to disk WITHOUT applying a new domain mutation (the
  /// app-scoped persistence owner's retry path). Safe no-op when clean.
  @override
  Future<void> flushPending() => _serialized(_flush);

  /// Progress ids due for review now (dueAt ≤ now), earliest first.
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
    _restoreBarrier++;
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
    await _prefs.reload();
    final loaded = await _store.load();
    _stats
      ..clear()
      ..addAll(loaded.value);
    _statsGen++;
    _statsPersistedGen = _statsGen;
    notifyListeners();
  }

  /// Replaces in-memory stats after a successful restore transaction.
  @override
  void replaceFromRestore({required Map<String, WordStat> stats}) {
    _stats
      ..clear()
      ..addAll(stats);
    _statsGen++;
    _statsPersistedGen = _statsGen;
    notifyListeners();
  }

  /// Clears all 詞と句 progress. Removes exactly the keys this repository
  /// owns; on a failed removal, reconciles against a fresh platform read with
  /// full [RecoverableStore] recovery semantics (see [KanjiReadingRepository]
  /// — the generation rules are identical).
  @override
  Future<void> reset() {
    final blocked = _blockedWriteFuture();
    if (blocked != null) return blocked;
    final before = Map<String, WordStat>.of(_stats);
    _stats.clear();
    _statsGen++;
    final gen = _statsGen;
    final run = _serialized(() async {
      try {
        await _store.removeAll();
        if (_statsGen == gen) {
          _statsPersistedGen = gen;
        } else {
          _statsGen++;
        }
      } catch (_) {
        var reloaded = true;
        try {
          await _prefs.reload();
        } catch (_) {
          reloaded = false;
        }
        if (_statsGen == gen) {
          _stats
            ..clear()
            ..addAll(reloaded ? _store.recoverCurrent() : before);
          if (reloaded) {
            _statsPersistedGen = gen;
          } else {
            _statsGen++;
          }
          notifyListeners();
        } else {
          _statsGen++;
        }
        rethrow;
      }
    });
    notifyListeners();
    return run;
  }

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
    final barrier = _restoreBarrier;
    final gen = _statsGen;
    if (_restoreBarrier != barrier) return;
    await _store.write(
      _encodeStats(),
      commitGuard: () => _restoreBarrier == barrier,
    );
    if (_restoreBarrier != barrier) return;
    _statsPersistedGen = gen;
  }

  String _encodeStats() =>
      jsonEncode(_stats.map((k, v) => MapEntry(k, v.toJson())));

  static DecodeResult<Map<String, WordStat>> _decodeStats(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const DecodeCorrupt();
    }
    if (decoded is! Map<String, dynamic>) return const DecodeCorrupt();
    final stats = <String, WordStat>{};
    var dropped = 0;
    decoded.forEach((key, value) {
      try {
        stats[key] = WordStat.fromJson(value as Map<String, dynamic>);
      } catch (_) {
        dropped++; // one bad entry must not wipe the rest
      }
    });
    return DecodeOk(stats, dropped: dropped);
  }
}
