// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/analytics_log_native.dart';

/// Opens the on-disk JSONL log (Android/iOS/macOS). Falls back to in-memory if
/// the platform storage isn't available.
Future<AnalyticsLog> openAnalyticsLog() async {
  try {
    return await FileAnalyticsLog.open();
  } catch (_) {
    return InMemoryAnalyticsLog();
  }
}
