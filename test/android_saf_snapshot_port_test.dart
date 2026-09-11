// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/android_saf_snapshot_port.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SnapshotSafWire.outcomeFor — URI is never implied success', () {
    test('explicit saved is saved', () {
      expect(
        SnapshotSafWire.outcomeFor(SnapshotSafWire.saved),
        SnapshotSaveOutcome.saved,
      );
    });

    test('explicit cancelled stays cancelled', () {
      expect(
        SnapshotSafWire.outcomeFor(SnapshotSafWire.cancelled),
        SnapshotSaveOutcome.cancelled,
      );
    });

    test('null stream / throw / missing reply are failed, not saved', () {
      expect(
        SnapshotSafWire.outcomeFor(SnapshotSafWire.failed),
        SnapshotSaveOutcome.failed,
      );
      expect(SnapshotSafWire.outcomeFor(null), SnapshotSaveOutcome.failed);
      expect(
        SnapshotSafWire.outcomeFor('content://downloads/kotonoha.json'),
        SnapshotSaveOutcome.failed,
      );
    });
  });

  group('AndroidSafSnapshotPort maps native write verdicts', () {
    test('null stream from the host is failed', () async {
      final port = AndroidSafSnapshotPort(
        invoke: (method, args) async => SnapshotSafWire.failed,
      );
      expect(
        await port.save(suggestedName: 'p.json', contents: '{}'),
        SnapshotSaveOutcome.failed,
      );
    });

    test('a thrown write is failed', () async {
      final port = AndroidSafSnapshotPort(
        invoke: (method, args) async =>
            throw PlatformException(code: 'write', message: 'IOException'),
      );
      expect(
        await port.save(suggestedName: 'p.json', contents: '{}'),
        SnapshotSaveOutcome.failed,
      );
    });

    test('a confirmed write is saved and forwards the bytes', () async {
      late Map<String, Object?> seen;
      final port = AndroidSafSnapshotPort(
        invoke: (method, args) async {
          seen = args;
          return SnapshotSafWire.saved;
        },
      );
      expect(
        await port.save(suggestedName: 'p.json', contents: '{"k":1}'),
        SnapshotSaveOutcome.saved,
      );
      expect(seen['suggestedName'], 'p.json');
      expect(seen['bytes'], utf8.encode('{"k":1}'));
    });

    test('picker dismiss is cancelled', () async {
      final port = AndroidSafSnapshotPort(
        invoke: (method, args) async => SnapshotSafWire.cancelled,
      );
      expect(
        await port.save(suggestedName: 'p.json', contents: '{}'),
        SnapshotSaveOutcome.cancelled,
      );
    });
  });
}
