// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/attempt.dart';

/// Append-only log of practice attempts, for learning analytics. Abstract so
/// web/tests can use an in-memory implementation while devices persist to a
/// JSONL file.
abstract class AnalyticsLog {
  Future<void> record(Attempt attempt);
  Future<List<Attempt>> all();
  Future<int> count();
}

/// In-memory log for web, tests, and as a safe fallback.
class InMemoryAnalyticsLog implements AnalyticsLog {
  final List<Attempt> _items = [];

  @override
  Future<void> record(Attempt attempt) async => _items.add(attempt);

  @override
  Future<List<Attempt>> all() async => List.unmodifiable(_items);

  @override
  Future<int> count() async => _items.length;
}
