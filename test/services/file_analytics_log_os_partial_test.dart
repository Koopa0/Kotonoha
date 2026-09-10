// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

@TestOn('vm') // dart:ffi + dart:io — not the web build
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';
import 'package:kotonoha/domain/models/attempt.dart';

/// Real OS RLIMIT_FSIZE probe. Process-wide, so it is opt-in
/// (`KOTONOHA_RUN_OS_PARTIAL=1 flutter test` this file alone) and must
/// not run beside other writers in the default suite.
final class RLimit extends Struct {
  @Uint64()
  external int current;
  @Uint64()
  external int maximum;
}

void main() {
  test(
    'actual OS partial append followed by retry preserves attempt',
    () async {
      final libc = DynamicLibrary.open(
        Platform.isMacOS ? '/usr/lib/libSystem.B.dylib' : 'libc.so.6',
      );
      final malloc = libc
          .lookupFunction<
            Pointer<Void> Function(IntPtr),
            Pointer<Void> Function(int)
          >('malloc');
      final free = libc
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free');
      final getLimit = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<RLimit>),
            int Function(int, Pointer<RLimit>)
          >('getrlimit');
      final setLimit = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<RLimit>),
            int Function(int, Pointer<RLimit>)
          >('setrlimit');
      final signal = libc
          .lookupFunction<
            Pointer<Void> Function(Int32, Pointer<Void>),
            Pointer<Void> Function(int, Pointer<Void>)
          >('signal');
      const rlimitFileSize = 1; // RLIMIT_FSIZE on Darwin and Linux.
      const sigxfsz = 25; // SIGXFSZ on Darwin and Linux.
      final limits = malloc(sizeOf<RLimit>()).cast<RLimit>();
      expect(getLimit(rlimitFileSize, limits), 0);
      final original = limits.ref.current;
      final dir = await Directory.systemTemp.createTemp('kotonoha-os-partial-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/log.jsonl');
      await file.create();
      final log = FileAnalyticsLog.forFile(file);
      await log.all();
      Attempt a(String id) => Attempt(
        ts: 1,
        itemId: id,
        mode: 'daily',
        correct: true,
        rtMs: 500,
        sessionId: 's',
      );
      Object? caught;
      final priorSignal = signal(sigxfsz, Pointer<Void>.fromAddress(1));
      try {
        limits.ref.current = 40;
        expect(setLimit(rlimitFileSize, limits), 0);
        try {
          await log.record(a('a'));
        } catch (e) {
          caught = e;
        }
      } finally {
        limits.ref.current = original;
        setLimit(rlimitFileSize, limits);
        signal(sigxfsz, priorSignal);
        free(limits.cast());
      }
      final size = await file.length();
      expect(caught, isA<FileSystemException>());
      expect(size, 0); // truncated back; the 40-byte prefix is not kept
      expect(log.unpersistedCount, 1);
      await log.record(a('b'));
      await log.flushPending();
      final memory = (await log.all()).map((x) => x.itemId).toList();
      final reopened = (await FileAnalyticsLog.forFile(
        file,
      ).all()).map((x) => x.itemId).toList();
      expect(memory, ['a', 'b']);
      expect(reopened, memory);
      expect(log.unpersistedCount, 0);
    },
    skip: !_runOsPartial,
  );
}

bool get _runOsPartial =>
    Platform.environment['KOTONOHA_RUN_OS_PARTIAL'] == '1' &&
    (Platform.isLinux || Platform.isMacOS);
