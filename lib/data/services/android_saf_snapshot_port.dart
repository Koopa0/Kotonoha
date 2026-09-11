// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:kotonoha/data/services/snapshot_file_port.dart';

/// Wire values from the Android SAF host. A missing / unknown reply is
/// [failed], never [saved] — a URI without a confirmed write is not success.
abstract final class SnapshotSafWire {
  static const String channel = 'kotonoha/snapshot_saf';
  static const String saved = 'saved';
  static const String cancelled = 'cancelled';
  static const String failed = 'failed';

  /// Maps the native write verdict. Only the explicit [saved] token is a
  /// completed write; [cancelled] is a dismissed picker; everything else
  /// (null stream, throw, missing reply) is [failed].
  static SnapshotSaveOutcome outcomeFor(String? reply) {
    return switch (reply) {
      saved => SnapshotSaveOutcome.saved,
      cancelled => SnapshotSaveOutcome.cancelled,
      _ => SnapshotSaveOutcome.failed,
    };
  }
}

Future<String?> invokeSnapshotSafChannel(
  String method,
  Map<String, Object?> args,
) {
  return const MethodChannel(SnapshotSafWire.channel)
      .invokeMethod<String>(method, args);
}

/// Android save-as that only reports [SnapshotSaveOutcome.saved] after the
/// native host confirmed a completed SAF write. It never treats a document
/// URI as proof the bytes landed.
class AndroidSafSnapshotPort implements SnapshotFilePort {
  AndroidSafSnapshotPort({
    Future<String?> Function(String method, Map<String, Object?> args)? invoke,
  }) : _invoke = invoke ?? invokeSnapshotSafChannel;

  final Future<String?> Function(String method, Map<String, Object?> args)
  _invoke;

  @override
  Future<SnapshotSaveOutcome> save({
    required String suggestedName,
    required String contents,
  }) async {
    try {
      final reply = await _invoke('save', {
        'suggestedName': suggestedName,
        'bytes': Uint8List.fromList(utf8.encode(contents)),
      });
      return SnapshotSafWire.outcomeFor(reply);
    } catch (_) {
      return SnapshotSaveOutcome.failed;
    }
  }
}
