// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm') // dart:io file I/O — not the web build
library;

import 'dart:convert';
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

  test('a record after a read stays in sync without re-reading disk', () async {
    final log = FileAnalyticsLog.forFile(file);
    await log.record(attempt('あ'));
    expect((await log.all()).map((a) => a.itemId), ['あ']); // loads the cache
    await log.record(attempt('か')); // must reach the in-memory cache too
    expect((await log.all()).map((a) => a.itemId), ['あ', 'か']);
    expect(await log.count(), 2);
  });

  test('skips a corrupt line instead of losing the whole log', () async {
    // A line truncated by a crash mid-append, then a good record after it.
    await file.writeAsString('{"ts":1,"itemId":"x"  <- truncated\n');
    final log = FileAnalyticsLog.forFile(file);
    await log.record(attempt('す'));
    final all = await log.all();
    expect(all.map((a) => a.itemId), ['す']); // good rows survive
    expect(await log.count(), 1);
  });

  test('a runtime write failure keeps the attempt in memory and does not '
      'claim the line landed on disk', () async {
    final log = FileAnalyticsLog.forFile(file);
    await log.all(); // warm cache — startup already succeeded
    await dir.delete(recursive: true);

    await expectLater(
      log.record(attempt('あ')),
      throwsA(isA<FileSystemException>()),
    );
    expect(await log.count(), 1);
    expect((await log.all()).single.itemId, 'あ');
    expect(log.unpersistedCount, 1);
    expect(await file.exists(), isFalse);
  });

  test(
    'flushPending after the path returns writes each attempt once',
    () async {
      final log = FileAnalyticsLog.forFile(file);
      await log.all();
      await dir.delete(recursive: true);

      await expectLater(
        log.record(attempt('あ')),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        log.record(attempt('か')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await log.count(), 2);
      expect(log.unpersistedCount, 2);

      await dir.create(recursive: true);
      await log.flushPending();

      expect(log.unpersistedCount, 0);
      expect(await log.count(), 2);
      final lines = await file.readAsLines();
      expect(lines.where((l) => l.trim().isNotEmpty).length, 2);
      final reopened = FileAnalyticsLog.forFile(file);
      expect((await reopened.all()).map((a) => a.itemId), ['あ', 'か']);
    },
  );

  test(
    'a partial append is truncated and retried without losing the attempt',
    () async {
      final log = FileAnalyticsLog.forFile(file);
      await log.all();
      await file.create();
      var failOnce = true;
      log.debugAppend = (f, line) async {
        if (failOnce) {
          failOnce = false;
          final raw = utf8.encode(line);
          expect(raw.length, greaterThan(40));
          await f.writeAsBytes(raw.sublist(0, 40), flush: true);
          throw const FileSystemException('injected partial append');
        }
        await f.writeAsString(line, mode: FileMode.append, flush: true);
      };

      await expectLater(
        log.record(attempt('a')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await log.count(), 1);
      expect(log.unpersistedCount, 1);
      expect(await file.length(), 0);

      await log.record(attempt('b'));
      await log.flushPending();

      expect(log.unpersistedCount, 0);
      expect((await log.all()).map((a) => a.itemId), ['a', 'b']);
      final reopened = FileAnalyticsLog.forFile(file);
      expect((await reopened.all()).map((a) => a.itemId), ['a', 'b']);
      final lines = await file.readAsLines();
      expect(lines.where((l) => l.trim().isNotEmpty).length, 2);
    },
  );

  test(
    'a complete line whose flush reported failure is not rewritten',
    () async {
      final log = FileAnalyticsLog.forFile(file);
      await log.all();
      await file.create();
      var failOnce = true;
      log.debugAppend = (f, line) async {
        await f.writeAsString(line, mode: FileMode.append, flush: true);
        if (failOnce) {
          failOnce = false;
          throw const FileSystemException('injected flush failure');
        }
      };

      await log.record(attempt('a'));
      expect(log.unpersistedCount, 0);
      expect(await file.readAsLines(), hasLength(1));

      await log.record(attempt('b'));
      await log.flushPending();

      expect(log.unpersistedCount, 0);
      expect((await log.all()).map((a) => a.itemId), ['a', 'b']);
      final reopened = FileAnalyticsLog.forFile(file);
      expect((await reopened.all()).map((a) => a.itemId), ['a', 'b']);
      final lines = await file.readAsLines();
      expect(lines.where((l) => l.trim().isNotEmpty).length, 2);
    },
  );
}
