// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Outcome of asking the user to keep a snapshot file. A cancelled pick is
/// not a failure — no bytes were written and progress stores were not touched.
enum SnapshotSaveOutcome {
  /// The chosen location acknowledged the write.
  saved,

  /// The user dismissed the system picker. Nothing was written.
  cancelled,

  /// The picker or the write threw / reported failure after we already had
  /// encoded bytes. Progress stores are still untouched.
  failed,
}

/// Native save-as (and, later, pick-file) seam. The UI never imports
/// `file_picker` / `dart:io`; tests inject a fake so export can be proven
/// without a platform dialog.
abstract class SnapshotFilePort {
  /// Offers [contents] to the system save dialog under [suggestedName].
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  });
}
