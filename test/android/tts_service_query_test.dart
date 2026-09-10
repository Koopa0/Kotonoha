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

  test('locked flutter_tts 4.2.5 plugin manifest still has no TTS_SERVICE', () {
    final pubCache =
        Platform.environment['PUB_CACHE'] ??
        '${Platform.environment['HOME']}/.pub-cache';
    final plugin = File(
      '$pubCache/hosted/pub.dev/flutter_tts-4.2.5/android/src/main/AndroidManifest.xml',
    );
    if (!plugin.existsSync()) {
      // Host without the cached plugin: the app-level query is the merge input.
      return;
    }
    final source = plugin.readAsStringSync();
    expect(source, isNot(contains('TTS_SERVICE')));
    expect(source, isNot(contains('QUERY_ALL_PACKAGES')));
  });
}
