// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// The durable `shared_preferences` keys of every progress body, in one
/// place. A repository owns the *contents* under its keys; the restore
/// journal, the placement-discard marker and the restore transaction only
/// need the *names* to snapshot, stage, roll back and clear them. Keeping the
/// names here lets those low-level services stay independent of any
/// repository class — the names are the contract, the repositories are the
/// owners.
///
/// Changing a value is a storage-format change: every installed device keeps
/// its data under the old name.
abstract final class ProgressStoreKeys {
  static const String kanaStats = 'kana_stats_v1';
  static const String kanaStatsLastGood = 'kana_stats_last_good_v1';
  static const String kanaStatsQuarantine = 'kana_stats_quarantine_v1';
  static const String learnedUnits = 'learned_units_v1';
  static const String learnedUnitsLastGood = 'learned_units_last_good_v1';
  static const String learnedUnitsQuarantine = 'learned_units_quarantine_v1';
  static const String seenUnlocks = 'seen_unlocks_v1';
  static const String seenUnlocksLastGood = 'seen_unlocks_last_good_v1';
  static const String seenUnlocksQuarantine = 'seen_unlocks_quarantine_v1';
  static const String kanjiStats = 'kanji_units_v1';
  static const String kanjiStatsLastGood = 'kanji_units_last_good_v1';
  static const String kanjiStatsQuarantine = 'kanji_units_quarantine_v1';
  static const String wordStats = 'word_stats_v1';
  static const String wordStatsLastGood = 'word_stats_last_good_v1';
  static const String wordStatsQuarantine = 'word_stats_quarantine_v1';

  static const String placementCheck = 'placement_check_v1';
  static const String placementCheckLastGood = 'placement_check_last_good_v1';
  static const String placementCheckQuarantine =
      'placement_check_quarantine_v1';

  /// `progress_restore_journal_v1` — the in-flight restore transaction.
  static const String restoreJournal = 'progress_restore_journal_v1';

  /// `progress_restore_placement_discard_v1` — a committed restore still
  /// owes placement-draft cleanup.
  static const String placementDiscardPending =
      'progress_restore_placement_discard_v1';

  /// The five portable bodies a snapshot carries, in the order a restore
  /// stages, applies and rolls them back.
  static const List<String> portableBodies = <String>[
    kanaStats,
    learnedUnits,
    seenUnlocks,
    kanjiStats,
    wordStats,
  ];

  /// The last-known-good and quarantine slots beside each portable body. A
  /// restore clears them so a later load cannot resurrect pre-restore data.
  static const List<String> portableAuxiliary = <String>[
    kanaStatsLastGood,
    kanaStatsQuarantine,
    learnedUnitsLastGood,
    learnedUnitsQuarantine,
    seenUnlocksLastGood,
    seenUnlocksQuarantine,
    kanjiStatsLastGood,
    kanjiStatsQuarantine,
    wordStatsLastGood,
    wordStatsQuarantine,
  ];

  /// Every placement-draft key, primary first — the order the journal
  /// snapshots and rolls them back.
  static const List<String> placementDurable = <String>[
    placementCheck,
    placementCheckLastGood,
    placementCheckQuarantine,
  ];
}
