// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Append-only JSONL log on disk. On Android it lives in the app's external
/// files dir (`/sdcard/Android/data/<pkg>/files/`), which `adb pull` can read
/// without root — so the learning data can be pulled and analysed later.
class FileAnalyticsLog implements AnalyticsLog {
  /// Points a log at an explicit file — lets tests exercise the real JSONL
  /// read/write path against a temp dir, without `path_provider`.
  @visibleForTesting
  factory FileAnalyticsLog.forFile(File file) => FileAnalyticsLog._(file);
  FileAnalyticsLog._(this._file);

  final File _file;

  static const String _fileName = 'kana_analytics.jsonl';

  static Future<FileAnalyticsLog> open() async {
    final dir = await _directory();
    final file = File(p.join(dir.path, _fileName));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return FileAnalyticsLog._(file);
  }

  static Future<Directory> _directory() async {
    // Prefer the adb-pullable external app dir on Android.
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<void> record(Attempt attempt) async {
    await _file.writeAsString(
      '${jsonEncode(attempt.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<List<Attempt>> all() async {
    if (!await _file.exists()) return const [];
    final lines = await _file.readAsLines();
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          Attempt.fromJson(jsonDecode(line) as Map<String, Object?>),
    ];
  }

  @override
  Future<int> count() async => (await all()).length;
}
