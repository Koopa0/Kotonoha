// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_tts/flutter_tts.dart';

/// Speaks Japanese text aloud. Abstract so tests (and unsupported platforms)
/// can swap in a no-op implementation.
abstract class SpeechService {
  Future<void> speak(String text);
}

/// Default implementation backed by the platform's TTS engine (Google TTS on
/// Android, system voices on macOS, SpeechSynthesis on web), set to Japanese.
class FlutterTtsSpeechService implements SpeechService {
  FlutterTtsSpeechService(this._tts);

  final FlutterTts _tts;

  static Future<FlutterTtsSpeechService> create() async {
    final tts = FlutterTts();
    try {
      // On Android, prefer Google's engine — it has the best ja-JP voice.
      try {
        final engines = (await tts.getEngines) as List?;
        if (engines != null && engines.contains('com.google.android.tts')) {
          await tts.setEngine('com.google.android.tts');
        }
      } catch (_) {
        // getEngines/setEngine unsupported on this platform — ignore.
      }
      await tts.setLanguage('ja-JP');
      await tts.setSpeechRate(0.5); // natural pace
      await tts.setPitch(1.0);
    } catch (_) {
      // Engine not ready/installed — speak() will simply no-op.
    }
    return FlutterTtsSpeechService(tts);
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // TTS unavailable — fail silently rather than break the UI.
    }
  }
}

/// A no-op speech service for tests and environments without TTS.
class SilentSpeechService implements SpeechService {
  const SilentSpeechService();

  @override
  Future<void> speak(String text) async {}
}
