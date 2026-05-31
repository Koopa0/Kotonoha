// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';

/// Source of truth for per-kana practice stats. The only stateful unit in the
/// app; quiz session state lives in [QuizViewModel]. Persists through
/// [PreferencesService].
class KanaProgressRepository extends ChangeNotifier {
  KanaProgressRepository._(this._prefs, this._stats, this._learnedUnits);

  static const String _storageKey = 'kana_stats_v1';
  static const String _learnedKey = 'learned_units_v1';

  final PreferencesService _prefs;
  final Map<String, KanaStat> _stats;

  /// Ids of lessons (or future units) the user has passed. See [Lesson.id].
  final Set<String> _learnedUnits;

  /// Loads persisted stats + learned units (or starts empty).
  static Future<KanaProgressRepository> load([
    PreferencesService? prefs,
  ]) async {
    final service = prefs ?? await PreferencesService.create();
    return KanaProgressRepository._(
      service,
      _decode(service.readString(_storageKey)),
      _decodeLearned(service.readString(_learnedKey)),
    );
  }

  // --- Learned units (sequential lessons) ---

  bool isUnitLearned(String unitId) => _learnedUnits.contains(unitId);

  int get learnedUnitCount => _learnedUnits.length;

  /// Marks a lesson/unit as passed and persists. No-op if already learned.
  Future<void> markUnitLearned(String unitId) async {
    if (_learnedUnits.add(unitId)) {
      notifyListeners();
      await _prefs.writeString(_learnedKey, jsonEncode(_learnedUnits.toList()));
    }
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

  /// Overall accuracy across all answered questions, in [0, 1].
  double get overallAccuracy {
    var seen = 0;
    var correct = 0;
    for (final s in _stats.values) {
      seen += s.seenCount;
      correct += s.correctCount;
    }
    return seen == 0 ? 0 : correct / seen;
  }

  /// Records a single answer for [kana] and persists.
  Future<void> recordAnswer(
    Kana kana, {
    required bool correct,
    required DateTime at,
    int? latencyMs,
  }) async {
    final current = statFor(kana);
    final scale = kConfusableChars.contains(kana.character) ? 0.5 : 1.0;
    _stats[kana.id] = current.recordAnswer(
      correct: correct,
      at: at,
      latencyMs: latencyMs,
      intervalScale: scale,
    );
    notifyListeners();
    await _persist();
  }

  /// Clears all progress (used by tests and any future "reset" affordance).
  Future<void> reset() async {
    _stats.clear();
    _learnedUnits.clear();
    notifyListeners();
    await _prefs.remove(_storageKey);
    await _prefs.remove(_learnedKey);
  }

  Future<void> _persist() async {
    final map = _stats.map((k, v) => MapEntry(k, v.toJson()));
    await _prefs.writeString(_storageKey, jsonEncode(map));
  }

  static Map<String, KanaStat> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, KanaStat>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, KanaStat.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return <String, KanaStat>{};
    }
  }

  static Set<String> _decodeLearned(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
