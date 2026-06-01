// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// Source of truth for per-reading kanji stats. Mirrors [KanaProgressRepository]
/// but keyed by reading id ('reading:漢字#ヨミ') and persisted separately under
/// `kanji_stats_v1` — kana and kanji progress never collide (ADR).
class KanjiReadingRepository extends ChangeNotifier {
  KanjiReadingRepository._(this._prefs, this._stats);

  static const String _storageKey = 'kanji_stats_v1';

  final PreferencesService _prefs;
  final Map<String, ReadingStat> _stats;

  static Future<KanjiReadingRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    return KanjiReadingRepository._(
      service,
      _decode(service.readString(_storageKey)),
    );
  }

  /// Every kanji the module knows.
  List<KanjiEntry> get allKanji => kKanji;

  /// Read-only view of every recorded reading stat, keyed by reading id.
  Map<String, ReadingStat> get stats => Map.unmodifiable(_stats);

  /// The stat for a reading id, or an empty stat if never practised.
  ReadingStat statForReading(String readingId) =>
      _stats[readingId] ?? const ReadingStat();

  /// Count of readings the learner has practised at least once.
  int get seenReadingCount => _stats.values.where((s) => s.isSeen).length;

  /// Records one self-graded answer for a reading and persists.
  Future<void> recordAnswer(
    String readingId, {
    required bool correct,
    required DateTime at,
    int? latencyMs,
  }) async {
    _stats[readingId] = statForReading(
      readingId,
    ).recordAnswer(correct: correct, at: at, latencyMs: latencyMs);
    notifyListeners();
    await _persist();
  }

  /// Reading ids due for review now (dueAt ≤ now), earliest first.
  List<String> dueReadingIds(DateTime now) {
    final due =
        _stats.entries
            .where((e) => e.value.dueAt != null && !e.value.dueAt!.isAfter(now))
            .toList()
          ..sort((a, b) => a.value.dueAt!.compareTo(b.value.dueAt!));
    return [for (final e in due) e.key];
  }

  /// Clears all kanji progress (tests + any future reset affordance).
  Future<void> reset() async {
    _stats.clear();
    notifyListeners();
    await _prefs.remove(_storageKey);
  }

  Future<void> _persist() async {
    final map = _stats.map((k, v) => MapEntry(k, v.toJson()));
    await _prefs.writeString(_storageKey, jsonEncode(map));
  }

  static Map<String, ReadingStat> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, ReadingStat>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, ReadingStat.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return <String, ReadingStat>{};
    }
  }
}
