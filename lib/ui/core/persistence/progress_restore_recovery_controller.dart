// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';

/// App-scoped owner of restore-journal startup recovery. When
/// [ProgressRestoreJournal.recoverIfNeeded] cannot finish, the three progress
/// repositories refuse normal learning writes until [retry] succeeds.
class ProgressRestoreRecoveryController extends ChangeNotifier {
  ProgressRestoreRecoveryController({
    required this._prefs,
    required this._kana,
    required this._kanji,
    required this._words,
    required bool needsRecovery,
  }) : _needsRecovery = needsRecovery {
    _applyBlocking(needsRecovery);
  }

  final PreferencesService _prefs;
  final KanaProgressRepository _kana;
  final KanjiReadingRepository _kanji;
  final WordProgressRepository _words;

  bool _needsRecovery;
  bool _retrying = false;

  /// True when a blocking restore journal remains after startup recovery.
  bool get needsRecovery => _needsRecovery;

  bool get isRetrying => _retrying;

  /// Re-reads the journal from durable storage and applies blocking when an
  /// in-session restore leaves progress in a mixed or unfinished state.
  Future<void> syncFromPlatform() async {
    await _prefs.reload();
    final needs = ProgressRestoreJournal.needsRecovery(_prefs);
    _applyBlocking(needs);
    if (needs == _needsRecovery) return;
    _needsRecovery = needs;
    notifyListeners();
  }

  Future<void> retry() async {
    if (_retrying) return;
    _retrying = true;
    notifyListeners();
    try {
      final result = await ProgressRestoreJournal.recoverIfNeeded(_prefs);
      if (!result.needsRecovery) {
        await Future.wait([
          _kana.reloadFromPlatform(),
          _kanji.reloadFromPlatform(),
          _words.reloadFromPlatform(),
        ]);
        _needsRecovery = false;
        _applyBlocking(false);
      }
    } finally {
      _retrying = false;
      notifyListeners();
    }
  }

  void _applyBlocking(bool blocked) {
    _kana.setRestoreJournalBlocked(blocked);
    _kanji.setRestoreJournalBlocked(blocked);
    _words.setRestoreJournalBlocked(blocked);
  }
}
