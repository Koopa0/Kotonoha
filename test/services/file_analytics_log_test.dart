// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm') // dart:io file I/O — not the web build
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:path/path.dart' as p;

/// Tests the real on-disk JSONL append/read path — the data-export contract the
/// whole analytics design rests on (the file must be adb-pullable and parseable
/// line-by-line). Uses a system temp dir, so no device/path_provider needed.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kana_analytics_test');
    file = File(p.join(dir.path, 'log.jsonl'));
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Attempt attempt(String id, {bool correct = true, int rt = 0}) => Attempt(
    ts: 1700000000000 + id.hashCode % 1000,
    itemId: id,
    mode: 'daily',
    correct: correct,
    rtMs: rt,
    sessionId: 's1',
    meta: const {AttemptMeta.direction: 'kanaToRomaji'},
  );

  test(
    'appends one JSON object per line and reads them back in order',
    () async {
      final log = FileAnalyticsLog.forFile(file);
      await log.record(attempt('あ', rt: 420));
      await log.record(attempt('か', correct: false));
      await log.record(attempt('き', rt: 900));

      // One line per record (JSONL), no trailing blank parsed.
      final rawLines = await file.readAsLines();
      expect(rawLines.where((l) => l.trim().isNotEmpty).length, 3);

      final all = await log.all();
      expect(all.map((a) => a.itemId), ['あ', 'か', 'き']);
      expect(all[0].rtMs, 420);
      expect(all[1].correct, isFalse);
      expect(all[0].direction, 'kanaToRomaji');
      expect(await log.count(), 3);
    },
  );

  test(
    'survives reopening the same file (persistence across sessions)',
    () async {
      await FileAnalyticsLog.forFile(file).record(attempt('さ'));
      final reopened = FileAnalyticsLog.forFile(file);
      await reopened.record(attempt('し'));
      expect((await reopened.all()).map((a) => a.itemId), ['さ', 'し']);
    },
  );

  test('a missing file reads as empty rather than throwing', () async {
    final log = FileAnalyticsLog.forFile(
      File(p.join(dir.path, 'absent.jsonl')),
    );
    expect(await log.all(), isEmpty);
    expect(await log.count(), 0);
  });

  test('tolerates blank lines in the log', () async {
    await file.writeAsString('\n\n');
    final log = FileAnalyticsLog.forFile(file);
    await log.record(attempt('す'));
    expect((await log.all()).single.itemId, 'す');
  });
}
