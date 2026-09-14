// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_recovery.dart';

/// App-scoped, observable owner of restore-journal recovery as the UI sees
/// it: whether a blocking journal remains ([needsRecovery]) and whether a
/// [retry] is in flight. The cross-owner work — re-reading the journal,
/// reloading the three progress repositories, refusing learning writes — is
/// [ProgressRestoreRecovery]'s; this only records the outcome and notifies.
///
/// Lifetime above any route, so the banner and the placement screens read one
/// truth. [syncFromPlatform] is how the view that ran an in-session restore
/// hands the outcome back.
class ProgressRestoreRecoveryController extends ChangeNotifier {
  ProgressRestoreRecoveryController({
    required this._recovery,
    required bool needsRecovery,
  }) : _needsRecovery = needsRecovery {
    _recovery.applyBlocking(needsRecovery);
  }

  final ProgressRestoreRecovery _recovery;

  bool _needsRecovery;
  bool _retrying = false;

  /// True when a blocking restore journal remains after startup recovery.
  bool get needsRecovery => _needsRecovery;

  bool get isRetrying => _retrying;

  /// Re-reads the journal from durable storage and applies blocking when an
  /// in-session restore leaves progress in a mixed or unfinished state.
  Future<void> syncFromPlatform() async {
    final needs = await _recovery.syncFromPlatform();
    if (needs == _needsRecovery) return;
    _needsRecovery = needs;
    notifyListeners();
  }

  Future<void> retry() async {
    if (_retrying) return;
    _retrying = true;
    notifyListeners();
    try {
      final needs = await _recovery.recover();
      if (!needs) _needsRecovery = false;
    } finally {
      _retrying = false;
      notifyListeners();
    }
  }
}
