// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';

/// Restore-journal recovery across the three progress owners.
///
/// The journal itself is a low-level service over raw preferences; this is
/// the one place that turns its verdict into repository state: while a
/// blocking journal remains, kana, kanji and 詞と句 refuse normal learning
/// writes, and once recovery lands, all three reload from durable storage.
/// Startup runs [ProgressRestoreJournal.recoverIfNeeded] before the owners
/// exist; [recover] is the same recovery retried in-session.
///
/// Holds no observable state — the app-scoped UI owner records what the
/// banner shows and when a retry is in flight.
class ProgressRestoreRecovery {
  ProgressRestoreRecovery({
    required this.prefs,
    required this.kana,
    required this.kanji,
    required this.words,
  });

  final PreferencesService prefs;
  final KanaProgressRepository kana;
  final KanjiReadingRepository kanji;
  final WordProgressRepository words;

  /// Whether a blocking journal is on disk as currently cached — no
  /// platform read. [syncFromPlatform] re-reads first.
  bool get needsRecovery => ProgressRestoreJournal.needsRecovery(prefs);

  /// Re-reads durable storage and re-applies write blocking to the three
  /// owners. Returns whether a blocking journal remains — an in-session
  /// restore that aborted mid-way leaves one behind.
  Future<bool> syncFromPlatform() async {
    await prefs.reload();
    final needs = needsRecovery;
    applyBlocking(needs);
    return needs;
  }

  /// Retries startup recovery. On success the three owners reload what is
  /// now on disk and learning writes are allowed again. Returns whether a
  /// blocking journal still remains.
  Future<bool> recover() async {
    final result = await ProgressRestoreJournal.recoverIfNeeded(prefs);
    if (result.needsRecovery) return true;
    await Future.wait([
      kana.reloadFromPlatform(),
      kanji.reloadFromPlatform(),
      words.reloadFromPlatform(),
    ]);
    applyBlocking(false);
    return false;
  }

  /// Refuses (or allows) normal learning writes on all three owners.
  void applyBlocking(bool blocked) {
    kana.setRestoreJournalBlocked(blocked);
    kanji.setRestoreJournalBlocked(blocked);
    words.setRestoreJournalBlocked(blocked);
  }
}
