// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/progress_restore_journal.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';
import 'package:kotonoha/domain/use_cases/progress_restore_transaction.dart';
import 'package:kotonoha/domain/use_cases/progress_snapshot_capture.dart';

/// What happened when the learner asked to restore from a snapshot file.
enum SnapshotRestoreStatus {
  /// Every primary was replaced and memory updated.
  restored,

  /// Primaries were replaced but a pre-restore placement draft still needs
  /// durable cleanup — progress did change; bootstrap will retry discard.
  restoredPlacementDiscardPending,

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
/// five portable bodies through [ProgressRestoreTransaction].
///
/// The transaction leaves the progress owners consistent with durable storage
/// on every outcome. What the UI shows about a journal left behind is the
/// app-scoped recovery owner's; the view that issued the restore refreshes it
/// once this returns.
class ProgressSnapshotRestorer {
  ProgressSnapshotRestorer({
    required this._capture,
    required this._transaction,
    required this._files,
  });

  final ProgressSnapshotCapture _capture;
  final ProgressRestoreTransaction _transaction;
  final SnapshotFilePort _files;

  /// Stores that block restore (unfinished journal only — recoveryRequired may
  /// be fixed by a successful restore).
  List<String> get blockedStores => _capture.blockedStores
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

    final preview = _transaction.previewEncoded(pick.contents!);
    if (preview == null) {
      return const SnapshotRestoreResult(SnapshotRestoreStatus.invalid);
    }

    if (!await confirm(preview)) {
      return SnapshotRestoreResult(
        SnapshotRestoreStatus.cancelled,
        preview: preview,
      );
    }

    try {
      await _transaction.apply(preview.snapshot);
    } catch (error) {
      return SnapshotRestoreResult(
        SnapshotRestoreStatus.failed,
        preview: preview,
        detail: error is RestoreJournalWriteFailure
            ? error.key
            : error.toString(),
      );
    }
    final status = _transaction.placementDiscardPending
        ? SnapshotRestoreStatus.restoredPlacementDiscardPending
        : SnapshotRestoreStatus.restored;
    return SnapshotRestoreResult(status, preview: preview);
  }
}
