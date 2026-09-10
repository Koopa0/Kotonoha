// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
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

  /// Parsed attempts, loaded from disk once then kept in sync by [record].
  /// Holding them in memory keeps [all]/[count] off the disk + JSON-parse path,
  /// so navigations that read recency (the home's reading composers) never
  /// stall on the ever-growing append-only log. Null until first loaded.
  /// The app provides ONE instance (a Provider singleton) on Dart's single
  /// isolate, so this needs no locking; sharing a file across instances is not
  /// supported.
  List<Attempt>? _cache;

  /// Attempts accepted into [_cache] whose JSONL line is not yet confirmed
  /// on disk. A failed append leaves them here so a later write can retry
  /// without duplicating the in-memory view.
  final List<Attempt> _unpersisted = [];

  /// Serializes appends so two overlapping [record]s cannot write the same
  /// pending line twice. The chain itself is kept successful so a later
  /// flush can retry after a failure.
  Future<void> _writeChain = Future<void>.value();

  /// Test-only append. The production path uses [File.writeAsString];
  /// tests install a hook to inject a partial write or a flush-reported
  /// failure against the real [File] — not a fake filesystem.
  Future<void> Function(File file, String line)? _debugAppend;

  static const String _fileName = 'kana_analytics.jsonl';

  static Future<FileAnalyticsLog> open() async {
    final dir = await _directory();
    final file = File(p.join(dir.path, _fileName));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    final log = FileAnalyticsLog._(file);
    // Warm the cache at startup — bootstrap already awaits this, off the tap
    // path — so even the first navigation is instant.
    await log._ensureLoaded();
    return log;
  }

  static Future<Directory> _directory() async {
    // Prefer the adb-pullable external app dir on Android.
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Parses the JSONL file into [_cache] once; a no-op once loaded. A single
  /// corrupt line (e.g. a last write truncated by a crash) is skipped rather
  /// than discarding the whole history — the export contract values the good
  /// rows over strictness.
  Future<void> _ensureLoaded() async {
    if (_cache != null) return;
    if (!await _file.exists()) {
      _cache = [];
      return;
    }
    final lines = await _file.readAsLines();
    final parsed = <Attempt>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        parsed.add(Attempt.fromJson(jsonDecode(line) as Map<String, Object?>));
      } catch (_) {
        // Skip a malformed/partial line; keep every other attempt.
      }
    }
    _cache = parsed;
  }

  @override
  int get unpersistedCount => _unpersisted.length;

  @override
  Future<void> record(Attempt attempt) async {
    await _ensureLoaded();
    // Retain first: a filesystem fault must not drop the attempt from the
    // in-memory log, and must not claim the line has landed on disk.
    _cache!.add(attempt);
    _unpersisted.add(attempt);
    await flushPending();
  }

  @override
  Future<void> flushPending() {
    final result = _writeChain.then(
      (_) => _appendUnpersisted(),
      onError: (Object _) => _appendUnpersisted(),
    );
    _writeChain = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Installs a test append hook. Production code never calls this.
  @visibleForTesting
  set debugAppend(Future<void> Function(File file, String line)? hook) {
    _debugAppend = hook;
  }

  Future<void> _appendUnpersisted() async {
    while (_unpersisted.isNotEmpty) {
      final next = _unpersisted.first;
      final line = '${jsonEncode(next.toJson())}\n';
      final start = await _lengthOrZero();
      try {
        await _writeLine(line);
      } catch (_) {
        // writeAsString / the OS may have mutated the tail before
        // throwing. Pending stays until a complete line is confirmed
        // at [start]; a partial tail is truncated back so a retry
        // cannot glue a new JSON object onto a broken prefix.
        if (!await _confirmOrRestoreTail(start, line)) rethrow;
        _unpersisted.removeAt(0);
        continue;
      }
      if (!await _confirmOrRestoreTail(start, line)) {
        throw FileSystemException(
          'analytics append was not retained as a complete JSONL line',
          _file.path,
        );
      }
      _unpersisted.removeAt(0);
    }
  }

  Future<void> _writeLine(String line) async {
    final hook = _debugAppend;
    if (hook != null) {
      await hook(_file, line);
      return;
    }
    await _file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  Future<int> _lengthOrZero() async {
    if (!await _file.exists()) return 0;
    return _file.length();
  }

  /// After an append attempt, the durable tail from [start] must be
  /// exactly [line] before pending may drop that attempt. Anything
  /// else (partial bytes, junk) is truncated back to [start].
  Future<bool> _confirmOrRestoreTail(int start, String line) async {
    if (!await _file.exists()) return false;
    final bytes = await _file.readAsBytes();
    if (bytes.length < start) return false;
    final tail = bytes.sublist(start);
    final expected = utf8.encode(line);
    if (_sameBytes(tail, expected)) return true;
    if (tail.isEmpty) return false;
    await _truncateTo(start);
    return false;
  }

  Future<void> _truncateTo(int start) async {
    if (!await _file.exists()) return;
    final raf = await _file.open(mode: FileMode.writeOnlyAppend);
    try {
      await raf.truncate(start);
      await raf.flush();
    } finally {
      await raf.close();
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<List<Attempt>> all() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache!);
  }

  @override
  Future<int> count() async {
    await _ensureLoaded();
    return _cache!.length;
  }
}
