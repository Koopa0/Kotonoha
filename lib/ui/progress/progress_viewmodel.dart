// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/use_cases/self_portrait.dart';

/// Owns the 歩み look-back: syllabary coverage, the present-tense status
/// counts, and the hard-gated notebook observations read from the analytics
/// stream. The screen renders the map; backup and restore keep their own
/// owners.
///
/// A map, not a scoreboard: no accuracy, no reaction time, no tally — those
/// stay private inputs to the silent scheduler. Coverage can only grow by
/// the honest act of meeting a kana.
///
/// Re-notifies on the kana owner so the map stays live. Pure of widgets.
class ProgressViewModel extends ChangeNotifier {
  ProgressViewModel({required this.kana, required this.analytics}) {
    kana.addListener(notifyListeners);
  }

  /// Owner of every kana's present-tense state.
  final KanaProgressRepository kana;
  final AnalyticsLog analytics;

  List<Observation> _observations = const [];
  bool _observed = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  int get seenCount => kana.seenCount;
  int get totalCount => kana.totalCount;

  /// How far the syllabary has been walked, 0..1.
  double get coverage => totalCount == 0 ? 0 : seenCount / totalCount;

  int countWithStatus(KanaStatus status) => kana.countWithStatus(status);

  /// The observations the stream currently supports (often none — the
  /// notebook says nothing rather than something flimsy).
  List<Observation> get observations => _observations;

  /// Whether the stream has been read at least once.
  bool get hasObserved => _observed;

  /// Reads the analytics stream and derives the observations.
  Future<void> observe() async {
    try {
      final events = await analytics.all();
      if (_disposed) return;
      _observations = SelfPortrait.observe(events);
      _observed = true;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    kana.removeListener(notifyListeners);
    super.dispose();
  }
}
