// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_restore_repository.dart';
import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';

/// What happened when the learner asked to restore from a snapshot file.
enum SnapshotRestoreStatus {
  /// Every primary was replaced and memory updated.
  restored,

  /// The picker was dismissed before reading.
  cancelled,

  /// The file could not be read or failed strict Snapshot v2 validation.
  invalid,

  /// An unfinished restore journal is still on disk.
  blocked,

  /// A write failed after validation; primaries were rolled back.
  failed,
}

/// Typed result of [ProgressSnapshotRestorer.restore].
class SnapshotRestoreResult {
  const SnapshotRestoreResult(this.status, {this.preview, this.detail});

  final SnapshotRestoreStatus status;
  final ProgressRestorePreview? preview;
  final String? detail;
}

/// Picks a file, previews it, and — after explicit confirmation — applies the
/// five portable bodies through [ProgressSnapshotRestoreRepository].
class ProgressSnapshotRestorer {
  ProgressSnapshotRestorer({
    required this._snapshots,
    required this._restore,
    required this._files,
    this._recovery,
  });

  final ProgressSnapshotRepository _snapshots;
  final ProgressSnapshotRestoreRepository _restore;
  final SnapshotFilePort _files;
  final ProgressRestoreRecoveryController? _recovery;

  /// Stores that block restore (unfinished journal only — recoveryRequired may
  /// be fixed by a successful restore).
  List<String> get blockedStores => _snapshots.blockedStores
      .where((s) => s == ProgressRestoreJournal.journalKey)
      .toList(growable: false);

  bool get isBlocked => blockedStores.isNotEmpty;

  /// Pick → validate → [confirm] → transactional apply. Validation failure and
  /// cancellation perform zero writes.
  Future<SnapshotRestoreResult> restore({
    required Future<bool> Function(ProgressRestorePreview preview) confirm,
  }) async {
    if (isBlocked) {
      return SnapshotRestoreResult(
        SnapshotRestoreStatus.blocked,
        detail: blockedStores.join(', '),
      );
    }

    final pick = await _files.pick();
    switch (pick.outcome) {
      case SnapshotPickOutcome.cancelled:
        return const SnapshotRestoreResult(SnapshotRestoreStatus.cancelled);
      case SnapshotPickOutcome.failed:
        return const SnapshotRestoreResult(SnapshotRestoreStatus.failed);
      case SnapshotPickOutcome.picked:
        break;
    }

    final preview = _restore.previewEncoded(pick.contents!);
    if (preview == null) {
      return const SnapshotRestoreResult(SnapshotRestoreStatus.invalid);
    }

    if (!await confirm(preview)) {
      return SnapshotRestoreResult(
        SnapshotRestoreStatus.cancelled,
        preview: preview,
      );
    }

    Object? applyError;
    try {
      await _restore.apply(preview.snapshot);
    } catch (error) {
      applyError = error;
    }
    await _recovery?.syncFromPlatform();
    if (applyError != null) {
      return SnapshotRestoreResult(
        SnapshotRestoreStatus.failed,
        preview: preview,
        detail: applyError is RestoreJournalWriteFailure
            ? applyError.key
            : applyError.toString(),
      );
    }
    return SnapshotRestoreResult(
      SnapshotRestoreStatus.restored,
      preview: preview,
    );
  }
}
