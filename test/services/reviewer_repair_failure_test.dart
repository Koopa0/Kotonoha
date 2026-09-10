// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/domain/models/attempt.dart';

/// Reviewer P2: a failed tail-read or truncate must not forget the
/// original append start. chmod 200/400 is a real OS EACCES on a
/// non-root process; root would bypass it, so those cases skip and
/// the portable hooks below cover the same boundary for CI.
final bool _isRoot = () {
  if (Platform.isWindows) return false;
  final r = Process.runSync('id', ['-u']);
  return r.exitCode == 0 && r.stdout.toString().trim() == '0';
}();

void main() {
  Attempt attempt(String id) => Attempt(
    ts: 1,
    itemId: id,
    mode: 'daily',
    correct: true,
    rtMs: 500,
    sessionId: 's',
  );

  for (final mode in ['200', '400']) {
    test(
      'retry remains safe when ${mode == '200' ? 'tail read' : 'truncate'} '
      'failed',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'kotonoha-repair-fail-',
        );
        final file = File('${dir.path}/log.jsonl');
        await file.create();
        addTearDown(() async {
          await Process.run('chmod', ['600', file.path]);
          await dir.delete(recursive: true);
        });
        final log = FileAnalyticsLog.forFile(file);
        await log.all();
        var initial = true;
        log.debugAppend = (f, line) async {
          if (initial) {
            initial = false;
            await f.writeAsBytes(
              utf8.encode(line).sublist(0, 40),
              mode: FileMode.append,
              flush: true,
            );
            expect((await Process.run('chmod', [mode, f.path])).exitCode, 0);
            throw const FileSystemException('injected initial partial append');
          }
          await f.writeAsString(line, mode: FileMode.append, flush: true);
        };
        Object? failure;
        try {
          await log.record(attempt('a'));
        } catch (e) {
          failure = e;
        }
        expect(failure, isA<FileSystemException>());
        expect(failure.toString(), contains('Permission denied'));
        expect(log.unpersistedCount, 1);
        expect((await Process.run('chmod', ['600', file.path])).exitCode, 0);
        await log.record(attempt('b'));
        await log.flushPending();
        final memory = (await log.all()).map((x) => x.itemId).toList();
        final reopened = (await FileAnalyticsLog.forFile(
          file,
        ).all()).map((x) => x.itemId).toList();
        expect(memory, ['a', 'b']);
        expect(log.unpersistedCount, 0);
        expect(
          reopened,
          memory,
          reason:
              'repair errors must preserve the original pending append '
              'boundary',
        );
      },
      skip: Platform.isWindows || _isRoot
          ? 'chmod EACCES needs a non-root Unix process'
          : false,
    );
  }

  test('retry remains safe when tail read failed (portable hook)', () async {
    await _portableRepair(
      attempt: attempt,
      denyRead: true,
      denyTruncate: false,
    );
  });

  test('retry remains safe when truncate failed (portable hook)', () async {
    await _portableRepair(
      attempt: attempt,
      denyRead: false,
      denyTruncate: true,
    );
  });
}

Future<List<int>> _readTail(File file, int start, int count) async {
  final raf = await file.open();
  try {
    await raf.setPosition(start);
    return await raf.read(count);
  } finally {
    await raf.close();
  }
}

Future<void> _truncateTo(File file, int start) async {
  final raf = await file.open(mode: FileMode.writeOnlyAppend);
  try {
    await raf.truncate(start);
    await raf.flush();
  } finally {
    await raf.close();
  }
}

Future<void> _portableRepair({
  required Attempt Function(String id) attempt,
  required bool denyRead,
  required bool denyTruncate,
}) async {
  final dir = await Directory.systemTemp.createTemp('kotonoha-repair-hook-');
  final file = File('${dir.path}/log.jsonl');
  await file.create();
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  final log = FileAnalyticsLog.forFile(file);
  await log.all();
  var initial = true;
  var deny = true;
  log.debugAppend = (f, line) async {
    if (initial) {
      initial = false;
      await f.writeAsBytes(
        utf8.encode(line).sublist(0, 40),
        mode: FileMode.append,
        flush: true,
      );
      throw const FileSystemException('injected initial partial append');
    }
    await f.writeAsString(line, mode: FileMode.append, flush: true);
  };
  log.debugReadTail = (f, start, count) async {
    if (deny && denyRead) {
      throw const FileSystemException('Permission denied');
    }
    return _readTail(f, start, count);
  };
  log.debugTruncate = (f, start) async {
    if (deny && denyTruncate) {
      throw const FileSystemException('Permission denied');
    }
    await _truncateTo(f, start);
  };

  Object? failure;
  try {
    await log.record(attempt('a'));
  } catch (e) {
    failure = e;
  }
  expect(failure, isA<FileSystemException>());
  expect(failure.toString(), contains('Permission denied'));
  expect(log.unpersistedCount, 1);
  expect(await file.length(), 40);

  deny = false;
  await log.record(attempt('b'));
  await log.flushPending();
  final memory = (await log.all()).map((x) => x.itemId).toList();
  final reopened = (await FileAnalyticsLog.forFile(
    file,
  ).all()).map((x) => x.itemId).toList();
  expect(memory, ['a', 'b']);
  expect(reopened, memory);
  expect(log.unpersistedCount, 0);
  final lines = await file.readAsLines();
  expect(lines.where((l) => l.trim().isNotEmpty).length, 2);
}
