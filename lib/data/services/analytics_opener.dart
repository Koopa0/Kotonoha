// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Platform-agnostic entry point for opening the analytics log.
// Resolves to the native (file) opener, or the web (in-memory) opener.
export 'analytics_opener_native.dart'
    if (dart.library.html) 'analytics_opener_web.dart';
