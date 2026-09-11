// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';

/// System save-as via the platform document picker (SAF on Android,
/// UIDocumentPicker on iOS). Not a share sheet — the file stays where the
/// learner put it, and we never upload or post the bytes.
class FilePickerSnapshotPort implements SnapshotFilePort {
  const FilePickerSnapshotPort();

  @override
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  }) async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: suggestedName,
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (uri == null) return SnapshotSaveOutcome.cancelled;
      return SnapshotSaveOutcome.saved;
    } catch (_) {
      return SnapshotSaveOutcome.failed;
    }
  }
}
