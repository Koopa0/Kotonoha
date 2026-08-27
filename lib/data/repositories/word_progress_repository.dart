// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/domain/models/word_stat.dart';

/// Source of truth for per-item 詞と句 stats. Mirrors [KanjiReadingRepository]
/// but keyed by progress id (`word:いぬ` / `phrase:そらが あおい` — namespaced so
/// a word and a same-written phrase can never collide) and persisted separately
/// under `word_stats_v1` — the three tracks' progress never mixes (ADR).
/// Persists through a [RecoverableStore] slot (data-loss firewall).
///
/// Mode authority: 渡し舟 INTRODUCES an item ([introduce] — first meeting only,
/// a no-op once seen), while the colder retrieval modes (文字起こし's objective
/// assembly, 黙読's cold self-graded read) own the schedule via [recordAnswer].
class WordProgressRepository extends ChangeNotifier {
  WordProgressRepository._(
    this._prefs,
    this._store,
    StoreLoad<Map<String, WordStat>> stats,
  ) : _stats = stats.value,
      statsHealth = stats.health;

  static const String _storageKey = 'word_stats_v1';
  static const String _lastGoodKey = 'word_stats_last_good_v1';
  static const String _quarantineKey = 'word_stats_quarantine_v1';

  /// Kept for [PreferencesService.reload] — the only trustworthy read path
  /// after a failed platform write/remove (legacy cache divergence).
  final PreferencesService _prefs;

  final RecoverableStore<Map<String, WordStat>> _store;
  final Map<String, WordStat> _stats;

  /// How the persisted store came up at load (see [KanjiReadingRepository]
  /// for the full health semantics).
  final StoreHealth statsHealth;

  /// Tail of the mutation queue: every persisting mutation runs strictly
  /// after the previous one, so read-preserve-write rounds never interleave.
  Future<void> _tail = Future<void>.value();

  /// Monotonic store version: dirty while [_statsGen] is ahead of
  /// [_statsPersistedGen]; see [KanjiReadingRepository] for the contract.
  int _statsGen = 0;
  int _statsPersistedGen = 0;

  static Future<WordProgressRepository> load([
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
    return WordProgressRepository._(service, store, await store.load());
  }

  /// Read-only view of every recorded stat, keyed by progress id.
  Map<String, WordStat> get stats => Map.unmodifiable(_stats);

  /// The stat for a progress id, or an empty stat if never practised.
  WordStat statForItem(String progressId) =>
      _stats[progressId] ?? const WordStat();

  /// Count of items the learner has met at least once.
  int get seenItemCount => _stats.values.where((s) => s.isSeen).length;

  /// First meeting of an item (渡し舟's encode beat): counts as one correct
  /// untimed answer so the item enters the schedule (level 0 → 1) — but ONLY
  /// the first time. Re-ferrying a seen item is exposure, not schedule: a
  /// no-op here (the analytics log still records the attempt).
  Future<void> introduce(String progressId, {required DateTime at}) {
    if (statForItem(progressId).isSeen) return Future<void>.value();
    return recordAnswer(progressId, correct: true, at: at);
  }

  /// Records one graded answer for an item and persists. The returned future
  /// completes with an error if persisting failed — the in-memory state keeps
  /// the answer and the next mutation retries the write.
  Future<void> recordAnswer(
    String progressId, {
    required bool correct,
    required DateTime at,
  }) {
    _stats[progressId] = statForItem(progressId)
        .recordAnswer(correct: correct, at: at);
    _statsGen++;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Flushes the store to disk WITHOUT applying a new domain mutation (the
  /// app-scoped persistence owner's retry path). Safe no-op when clean.
  Future<void> flushPending() => _serialized(_flush);

  /// Progress ids due for review now (dueAt ≤ now), earliest first.
  List<String> dueItemIds(DateTime now) {
    final due =
        _stats.entries
            .where((e) => e.value.dueAt != null && !e.value.dueAt!.isAfter(now))
            .toList()
          ..sort((a, b) => a.value.dueAt!.compareTo(b.value.dueAt!));
    return [for (final e in due) e.key];
  }

  /// Clears all 詞と句 progress. Removes exactly the keys this repository
  /// owns; on a failed removal, reconciles against a fresh platform read with
  /// full [RecoverableStore] recovery semantics (see [KanjiReadingRepository]
  /// — the generation rules are identical).
  Future<void> reset() {
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
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _flush() async {
    if (_statsGen == _statsPersistedGen) return;
    final gen = _statsGen;
    await _store.write(_encodeStats());
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
