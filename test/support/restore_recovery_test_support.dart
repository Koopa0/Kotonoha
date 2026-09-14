// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_recovery.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';

import '../services/fake_preferences_service.dart';

/// Restore-recovery controller wired to the same repos a test already loaded.
ProgressRestoreRecoveryController recoveryForRepos({
  required PreferencesService prefs,
  required KanaProgressRepository kana,
  required KanjiReadingRepository kanji,
  required WordProgressRepository words,
  bool needsRecovery = false,
}) {
  return ProgressRestoreRecoveryController(
    recovery: ProgressRestoreRecovery(
      prefs: prefs,
      kana: kana,
      kanji: kanji,
      words: words,
    ),
    needsRecovery: needsRecovery,
  );
}

/// Idle restore-recovery controller for widget tests that mount
/// [PersistenceBanner] or [KanaLoopApp] without a blocking journal.
Future<ProgressRestoreRecoveryController> idleRestoreRecovery([
  PreferencesService? prefs,
]) async {
  final fake = prefs ?? FakePreferencesService();
  final kana = await KanaProgressRepository.load(fake);
  final kanji = await KanjiReadingRepository.load(fake);
  final words = await WordProgressRepository.load(fake);
  return recoveryForRepos(prefs: fake, kana: kana, kanji: kanji, words: words);
}
