// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:kotonoha/domain/models/attempt.dart';

/// Append-only log of practice attempts, for learning analytics. Abstract so
/// web/tests can use an in-memory implementation while devices persist to a
/// JSONL file.
///
/// Runtime write policy (open-time fallback is a different path): a failed
/// durable write keeps the attempt in memory, fails the [record] future
/// (never claims the line landed on disk), and retries those unpersisted
/// rows on the next [record] / [flushPending]. Callers must not drop the
/// future — use [recordObserved] so the failure cannot become an uncaught
/// async error. Formal progress repositories are a separate store.
abstract class AnalyticsLog {
  /// Appends [attempt]. Completes with an error if durable persistence
  /// failed; the attempt is still retained in memory (see
  /// [unpersistedCount]).
  Future<void> record(Attempt attempt);
  Future<List<Attempt>> all();
  Future<int> count();

  /// Attempts retained in memory that have not been confirmed on the
  /// durable store. Always 0 when memory is the store
  /// ([InMemoryAnalyticsLog]).
  int get unpersistedCount;

  /// Retries writing every unpersisted attempt. No-op when none are
  /// pending. Completes with an error if any remain unpersisted.
  Future<void> flushPending();
}

/// Observes [AnalyticsLog.record] so a runtime write failure cannot become
/// an uncaught async error. The attempt policy still lives on the log:
/// memory retains it, [AnalyticsLog.unpersistedCount] stays honest, and
/// the next write retries.
extension AnalyticsLogObserve on AnalyticsLog {
  void recordObserved(Attempt attempt) {
    unawaited(record(attempt).then<void>((_) {}, onError: _ignoreWriteError));
  }
}

void _ignoreWriteError(Object _, StackTrace _) {}

/// In-memory log for web, tests, and as a safe fallback.
class InMemoryAnalyticsLog implements AnalyticsLog {
  final List<Attempt> _items = [];

  @override
  Future<void> record(Attempt attempt) async => _items.add(attempt);

  @override
  Future<List<Attempt>> all() async => List.unmodifiable(_items);

  @override
  Future<int> count() async => _items.length;

  @override
  int get unpersistedCount => 0;

  @override
  Future<void> flushPending() async {}
}
