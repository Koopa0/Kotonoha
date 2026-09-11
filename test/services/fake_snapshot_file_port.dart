// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/snapshot_file_port.dart';

/// Records the last offered file. [next] is the outcome the next [save]
/// returns — tests never pretend a platform write succeeded.
class FakeSnapshotFilePort implements SnapshotFilePort {
  SnapshotSaveOutcome next = SnapshotSaveOutcome.saved;
  String? lastName;
  String? lastContents;
  int calls = 0;

  @override
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  }) async {
    calls++;
    lastName = suggestedName;
    lastContents = contents;
    return next;
  }
}
