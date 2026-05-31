// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/analytics_log.dart';

/// Web has no file system access here — keep attempts in memory.
Future<AnalyticsLog> openAnalyticsLog() async => InMemoryAnalyticsLog();
