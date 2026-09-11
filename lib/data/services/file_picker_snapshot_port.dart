// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:kotonoha/data/services/android_saf_snapshot_port.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';

Future<Uri?> defaultSnapshotPickerSave({
  required String fileName,
  required Uint8List bytes,
}) {
  return FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/json',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
}

/// System save-as. Darwin / desktop / web keep [FilePicker.saveFile] (those
/// hosts already confirm the write). Android does **not** — locked
/// `android_file_picker` 1.1.1 returns a URI after `openOutputStream` is
/// null, so a URI is not a completed write. Android goes through
/// [AndroidSafSnapshotPort] instead (SAF, no extra storage permission).
class FilePickerSnapshotPort implements SnapshotFilePort {
  FilePickerSnapshotPort({
    SnapshotFilePort? android,
    Future<Uri?> Function({required String fileName, required Uint8List bytes})?
    saveWithPicker,
    this._preferAndroidSaf,
  }) : _android = android ?? AndroidSafSnapshotPort(),
       _saveWithPicker = saveWithPicker ?? defaultSnapshotPickerSave;

  final SnapshotFilePort _android;
  final Future<Uri?> Function({
    required String fileName,
    required Uint8List bytes,
  })
  _saveWithPicker;
  final bool? _preferAndroidSaf;

  bool get _useAndroidSaf =>
      _preferAndroidSaf ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  }) async {
    if (_useAndroidSaf) {
      return _android.save(suggestedName: suggestedName, contents: contents);
    }
    try {
      final uri = await _saveWithPicker(
        fileName: suggestedName,
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );
      if (uri == null) return SnapshotSaveOutcome.cancelled;
      return SnapshotSaveOutcome.saved;
    } catch (_) {
      return SnapshotSaveOutcome.failed;
    }
  }
}
