// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/file_picker_snapshot_port.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';

import 'services/fake_snapshot_file_port.dart';

void main() {
  test('Android never treats a picker URI as a completed write', () async {
    final android = FakeSnapshotFilePort()..next = SnapshotSaveOutcome.failed;
    final port = FilePickerSnapshotPort(
      android: android,
      preferAndroidSaf: true,
      saveWithPicker: ({required fileName, required bytes}) async {
        fail('FilePicker.saveFile must not be the Android write proof');
      },
    );

    expect(
      await port.save(suggestedName: 'p.json', contents: '{}'),
      SnapshotSaveOutcome.failed,
    );
    expect(android.saveCalls, 1);
  });

  test('Android saved / cancelled follow the SAF host, not a URI', () async {
    final android = FakeSnapshotFilePort()..next = SnapshotSaveOutcome.saved;
    final port = FilePickerSnapshotPort(
      android: android,
      preferAndroidSaf: true,
    );
    expect(
      await port.save(suggestedName: 'p.json', contents: '{}'),
      SnapshotSaveOutcome.saved,
    );

    android.next = SnapshotSaveOutcome.cancelled;
    expect(
      await port.save(suggestedName: 'p.json', contents: '{}'),
      SnapshotSaveOutcome.cancelled,
    );
  });

  test('non-Android cancel is a null picker result', () async {
    final port = FilePickerSnapshotPort(
      preferAndroidSaf: false,
      saveWithPicker: ({required fileName, required bytes}) async => null,
    );
    expect(
      await port.save(suggestedName: 'p.json', contents: '{}'),
      SnapshotSaveOutcome.cancelled,
    );
  });

  test('non-Android picker throw is failed', () async {
    final port = FilePickerSnapshotPort(
      preferAndroidSaf: false,
      saveWithPicker: ({required fileName, required bytes}) async {
        throw StateError('picker crashed');
      },
    );
    expect(
      await port.save(suggestedName: 'p.json', contents: '{}'),
      SnapshotSaveOutcome.failed,
    );
  });

  test('non-Android confirmed picker URI is saved', () async {
    Uint8List? seen;
    final port = FilePickerSnapshotPort(
      preferAndroidSaf: false,
      saveWithPicker: ({required fileName, required bytes}) async {
        seen = bytes;
        return Uri.parse('file:///tmp/p.json');
      },
    );
    expect(
      await port.save(suggestedName: 'p.json', contents: 'abc'),
      SnapshotSaveOutcome.saved,
    );
    expect(seen, isNotNull);
  });
}
