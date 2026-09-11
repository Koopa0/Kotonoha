// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/snapshot_file_port.dart';

/// Records the last offered file. [next] is the outcome the next [save]
/// returns — tests never pretend a platform write succeeded.
class FakeSnapshotFilePort implements SnapshotFilePort {
  SnapshotSaveOutcome next = SnapshotSaveOutcome.saved;
  SnapshotPickOutcome nextPick = SnapshotPickOutcome.picked;
  String? lastName;
  String? lastContents;
  String? pickContents;
  int saveCalls = 0;
  int pickCalls = 0;

  @override
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  }) async {
    saveCalls++;
    lastName = suggestedName;
    lastContents = contents;
    return next;
  }

  @override
  Future<SnapshotPickResult> pick() async {
    pickCalls++;
    return switch (nextPick) {
      SnapshotPickOutcome.picked => SnapshotPickResult(
        SnapshotPickOutcome.picked,
        contents: pickContents,
      ),
      SnapshotPickOutcome.cancelled => const SnapshotPickResult(
        SnapshotPickOutcome.cancelled,
      ),
      SnapshotPickOutcome.failed => const SnapshotPickResult(
        SnapshotPickOutcome.failed,
      ),
    };
  }
}
