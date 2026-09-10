// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'app manifest declares TTS_SERVICE without widening package visibility',
    () {
      final source = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(source, contains('android.intent.action.PROCESS_TEXT'));
      expect(source, contains('android.intent.action.TTS_SERVICE'));
      expect(source, isNot(contains('QUERY_ALL_PACKAGES')));
      expect(source.contains('<queries>'), isTrue);
    },
  );
}
