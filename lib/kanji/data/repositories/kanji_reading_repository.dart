// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// Source of truth for per-UNIT kanji stats — a unit being a written run and
/// the sound it makes there ('unit:学校#がっこう'), because a reading belongs to
/// the word, not the character. Mirrors [KanaProgressRepository] but persisted
/// separately under `kanji_units_v1` — kana and kanji progress never collide (ADR). Persists
/// through a [RecoverableStore] slot (data-loss firewall).
class KanjiReadingRepository extends ChangeNotifier {
  KanjiReadingRepository._(
    this._prefs,
    this._store,
    StoreLoad<Map<String, ReadingStat>> stats,
  ) : _stats = stats.value,
      statsHealth = stats.health;

  static const String _storageKey = 'kanji_units_v1';
  static const String _lastGoodKey = 'kanji_units_last_good_v1';
  static const String _quarantineKey = 'kanji_units_quarantine_v1';

  /// Kept for [PreferencesService.reload] — the only trustworthy read path
  /// after a failed platform write/remove (legacy cache divergence).
  final PreferencesService _prefs;

  final RecoverableStore<Map<String, ReadingStat>> _store;
  final Map<String, ReadingStat> _stats;

  /// How the persisted store came up at load. [StoreHealth.recoveryRequired]
  /// means the primary was unreadable with no usable last-known-good: the
  /// state starts empty, but the damaged payload still sits under its primary
  /// key (quarantined before the next write replaces it) — it was NOT
  /// mistaken for a legal fresh install. [StoreHealth.preservationPending]
  /// means a recovered value is in use but the damaged raw is not yet
  /// confirmed quarantined.
  final StoreHealth statsHealth;

  /// Tail of the mutation queue: every persisting mutation (recordAnswer,
  /// reset) runs strictly after the previous one, so read-preserve-write
  /// rounds never interleave and lose updates.
  Future<void> _tail = Future<void>.value();

  /// Monotonic store version: the store is dirty (holds unpersisted
  /// mutations) while [_statsGen] is ahead of [_statsPersistedGen]. Every
  /// queued task flushes the pending state, so a mutation's future only
  /// succeeds once everything submitted before it is truly on disk.
  int _statsGen = 0;
  int _statsPersistedGen = 0;

  static Future<KanjiReadingRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    final store = RecoverableStore<Map<String, ReadingStat>>(
      prefs: service,
      primaryKey: _storageKey,
      lastGoodKey: _lastGoodKey,
      quarantineKey: _quarantineKey,
      empty: () => <String, ReadingStat>{},
      decode: _decodeStats,
    );
    return KanjiReadingRepository._(service, store, await store.load());
  }

  /// Every kanji the module knows.
  List<KanjiEntry> get allKanji => kKanji;

  /// Read-only view of every recorded reading stat, keyed by reading id.
  Map<String, ReadingStat> get stats => Map.unmodifiable(_stats);

  /// The stat for a unit id, or an empty stat if never practised.
  ReadingStat statForUnit(String unitId) =>
      _stats[unitId] ?? const ReadingStat();

  /// Count of units the learner has practised at least once.
  int get seenUnitCount => _stats.values.where((s) => s.isSeen).length;

  /// Records one self-graded answer for a reading and persists. The returned
  /// future completes with an error if persisting failed — the in-memory
  /// state keeps the answer and the next mutation retries the write.
  Future<void> recordAnswer(
    String unitId, {
    required bool correct,
    required DateTime at,
  }) {
    _stats[unitId] = statForUnit(unitId).recordAnswer(correct: correct, at: at);
    _statsGen++;
    notifyListeners();
    return _serialized(_flush);
  }

  /// Flushes the store to disk WITHOUT applying a new domain mutation — the
  /// app-scoped persistence owner calls this to retry a write that failed after
  /// the screen that caused it moved on. It joins the same serialized queue,
  /// is a safe no-op when clean, and rethrows [StoreWriteFailure] like a
  /// mutation so the owner can observe the outcome. It advances no generation
  /// itself ([_flush] moves persistedGen only on a confirmed write).
  Future<void> flushPending() => _serialized(_flush);

  /// Unit ids due for review now (dueAt ≤ now), earliest first.
  List<String> dueUnitIds(DateTime now) {
    final due =
        _stats.entries
            .where((e) => e.value.dueAt != null && !e.value.dueAt!.isAfter(now))
            .toList()
          ..sort((a, b) => a.value.dueAt!.compareTo(b.value.dueAt!));
    return [for (final e in due) e.key];
  }

  /// Clears all kanji progress (tests + any future reset affordance).
  /// Removes exactly the keys this repository owns — the primary plus its
  /// last-known-good and quarantine copies — never a blanket clear. When a
  /// removal fails, in-memory state is reconciled against a FRESH platform
  /// read ([PreferencesService.reload] first — the legacy plugin cache
  /// already mutated before the refused verdict, so it is not disk), with
  /// full [RecoverableStore] recovery semantics, unless a later-submitted
  /// mutation already touched the store. If even the fresh read fails, the
  /// pre-reset snapshot is restored conservatively and the store stays
  /// dirty — an unknown state is never marked persisted.
  Future<void> reset() {
    final before = Map<String, ReadingStat>.of(_stats);
    _stats.clear();
    _statsGen++;
    final gen = _statsGen;
    // Register the reset action on the queue BEFORE notifying. A listener
    // that submits a mutation during this notification must chain AFTER the
    // removal, not before it — otherwise its flush lands first, the removal
    // then deletes the just-written data, and memory keeps it marked clean,
    // losing it on a fresh restart.
    final run = _serialized(() async {
      try {
        await _store.removeAll();
        if (_statsGen == gen) {
          _statsPersistedGen = gen;
        } else {
          // A later mutation owns the store now. The successful removal
          // invalidated any prior flush acknowledgement — an earlier queued
          // flush may have written the later state and advanced the persisted
          // generation to it, then this removal erased that durable data. Mint
          // a NEW dirty generation so the later mutation's flush truly
          // rewrites; never inherit an acknowledgement across a destructive
          // removal. persistedGen never regresses.
          _statsGen++;
        }
      } catch (_) {
        var reloaded = true;
        try {
          await _prefs.reload();
        } catch (_) {
          reloaded = false;
        }
        // Re-check the generation AFTER the await: a later-submitted
        // mutation owns the store now and must never be overwritten.
        if (_statsGen == gen) {
          _stats
            ..clear()
            ..addAll(reloaded ? _store.recoverCurrent() : before);
          if (reloaded) {
            // A confirmed fresh durable view — memory matches it.
            _statsPersistedGen = gen;
          } else {
            // The snapshot is unverified: mint a NEW dirty generation so an
            // earlier queued flush that caught persistedGen up to this
            // generation cannot leave the restored data marked clean.
            // persistedGen never regresses.
            _statsGen++;
          }
          notifyListeners();
        } else {
          // A later mutation owns the store's memory, and the removeAll threw
          // — its outcome is UNKNOWN (the primary may already have been
          // removed natively before the reply failed). Don't overwrite the
          // newer memory and don't inherit the pre-remove acknowledgement:
          // mint a new dirty generation so the later queued flush truly
          // rewrites. Redundant if the removal never landed, never a silent
          // loss.
          _statsGen++;
        }
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
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Flushes the store from its CURRENT in-memory state when dirty (never a
  /// stale snapshot). Throws on failure so the awaiting mutation reports
  /// honestly; the state stays dirty and the next mutation retries.
  Future<void> _flush() async {
    if (_statsGen == _statsPersistedGen) return;
    final gen = _statsGen;
    await _store.write(_encodeStats());
    _statsPersistedGen = gen;
  }

  String _encodeStats() =>
      jsonEncode(_stats.map((k, v) => MapEntry(k, v.toJson())));

  static DecodeResult<Map<String, ReadingStat>> _decodeStats(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const DecodeCorrupt();
    }
    if (decoded is! Map<String, dynamic>) return const DecodeCorrupt();
    final stats = <String, ReadingStat>{};
    var dropped = 0;
    decoded.forEach((key, value) {
      try {
        stats[key] = ReadingStat.fromJson(value as Map<String, dynamic>);
      } catch (_) {
        dropped++; // one bad entry must not wipe the rest
      }
    });
    return DecodeOk(stats, dropped: dropped);
  }
}
