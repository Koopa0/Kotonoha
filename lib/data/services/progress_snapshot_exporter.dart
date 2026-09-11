// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/progress_snapshot_repository.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';

/// What happened when the learner asked to keep a snapshot file.
enum SnapshotExportStatus {
  /// The system picker confirmed a write of a self-importable Snapshot v2.
  saved,

  /// The picker was dismissed. No file, no store writes.
  cancelled,

  /// A canonical store still needs recovery — emitting bytes would dress
  /// unresolved loss as a complete backup.
  blocked,

  /// In-memory progress violates the portable contract; encode refused
  /// rather than write a self-rejecting file.
  unimportable,

  /// The picker or the file write failed after encode. Stores untouched.
  failed,
}

/// Typed result of [ProgressSnapshotExporter.export]. [stores] is set only
/// for [SnapshotExportStatus.blocked]; [detail] only for unimportable encode.
class SnapshotExportResult {
  const SnapshotExportResult(this.status, {this.stores, this.detail});

  final SnapshotExportStatus status;
  final List<String>? stores;
  final String? detail;
}

/// Captures via the existing snapshot repository, then offers the encoded
/// bytes to a [SnapshotFilePort]. It never writes a progress store, never
/// flushes, and never applies a snapshot — restore is a later PR.
class ProgressSnapshotExporter {
  ProgressSnapshotExporter({
    required this._snapshots,
    required this._files,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ProgressSnapshotRepository _snapshots;
  final SnapshotFilePort _files;
  final DateTime Function() _now;

  /// Stores that would make [export] refuse. Same set [capture] checks.
  List<String> get blockedStores => _snapshots.blockedStores;

  bool get isBlocked => blockedStores.isNotEmpty;

  /// Suggested on-disk name. UTC, second precision, `.json` — the kind and
  /// schema live inside the file, not the extension.
  static String suggestedFileName(DateTime createdAt) {
    final utc = createdAt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'kotonoha-progress-${utc.year}'
        '${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z.json';
  }

  /// Encodes the current in-memory five bodies and offers them to the
  /// picker. A blocked / unimportable capture never reaches the port.
  Future<SnapshotExportResult> export() async {
    final createdAt = _now().toUtc();
    final String encoded;
    try {
      encoded = _snapshots.exportEncoded(createdAt: createdAt);
    } on SnapshotExportBlocked catch (error) {
      return SnapshotExportResult(
        SnapshotExportStatus.blocked,
        stores: error.stores,
      );
    } on SnapshotEncodeException catch (error) {
      return SnapshotExportResult(
        SnapshotExportStatus.unimportable,
        detail: error.detail,
      );
    }

    final outcome = await _files.save(
      suggestedName: suggestedFileName(createdAt),
      contents: encoded,
    );
    return SnapshotExportResult(switch (outcome) {
      SnapshotSaveOutcome.saved => SnapshotExportStatus.saved,
      SnapshotSaveOutcome.cancelled => SnapshotExportStatus.cancelled,
      SnapshotSaveOutcome.failed => SnapshotExportStatus.failed,
    });
  }
}
