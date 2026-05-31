// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for the screenshot capture run. Writes each screenshot the
/// integration test takes into `screenshots/<name>.png`. Run with:
///
/// ```sh
/// flutter drive \
///   --driver=test_driver/screenshot.dart \
///   --target=integration_test/screenshot_capture.dart \
///   -d emulator-5554
/// ```
Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? a]) async {
          final file = File('screenshots/$name.png');
          await file.writeAsBytes(bytes);
          return true;
        },
  );
}
