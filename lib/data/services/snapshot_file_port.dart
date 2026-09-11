// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Outcome of asking the user to keep a snapshot file. A cancelled pick is
/// not a failure — no bytes were written and progress stores were not touched.
enum SnapshotSaveOutcome {
  /// The host confirmed the bytes were written. A document URI alone is
  /// not this — Android's locked picker can return a URI after a null
  /// output stream.
  saved,

  /// The user dismissed the system picker. Nothing was written.
  cancelled,

  /// The picker or the write threw / reported failure after we already had
  /// encoded bytes. Progress stores are still untouched.
  failed,
}

/// Outcome of asking the user to open a snapshot file.
enum SnapshotPickOutcome {
  /// Bytes were read from the chosen file.
  picked,

  /// The user dismissed the picker. Nothing was read.
  cancelled,

  /// The picker or read threw / reported failure.
  failed,
}

/// Result of [SnapshotFilePort.pick]. [contents] is set only for
/// [SnapshotPickOutcome.picked].
class SnapshotPickResult {
  const SnapshotPickResult(this.outcome, {this.contents});

  final SnapshotPickOutcome outcome;
  final String? contents;
}

/// Native save-as / open-file seam. The UI never imports `file_picker` /
/// `dart:io`; tests inject a fake so export and restore can be proven without
/// a platform dialog.
abstract class SnapshotFilePort {
  /// Offers [contents] to the system save dialog under [suggestedName].
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  });

  /// Opens the system file picker for a Snapshot v2 `.json` file.
  Future<SnapshotPickResult> pick();
}
