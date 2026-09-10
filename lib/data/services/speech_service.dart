// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Outcome of one playback attempt. A completed [SpeechService.speak] future
/// is not evidence — only [played] means Japanese audio finished.
enum SpeechPlaybackResult {
  /// The utterance ran to completion.
  played,

  /// Engine, language, or voice pack is not ready. Nothing was spoken.
  unavailable,

  /// The engine rejected or threw. Nothing trustworthy was spoken.
  failed,

  /// Stopped by a newer play, [SpeechService.stop], or leaving the route.
  interrupted,
}

/// Speaks Japanese text aloud. Abstract so tests (and unsupported platforms)
/// can swap in a no-op implementation.
///
/// [speak] stays fire-and-forget for existing screens. Listen-first evidence
/// must go through [play] and treat anything other than
/// [SpeechPlaybackResult.played] as "not heard".
abstract class SpeechService {
  Future<void> speak(String text);

  /// Result-aware playback. Callers must not treat a completed future as
  /// success — inspect the returned [SpeechPlaybackResult].
  Future<SpeechPlaybackResult> play(String text);

  /// Stops any in-flight utterance. In-flight [play] calls resolve
  /// [SpeechPlaybackResult.interrupted] without waiting for the engine's
  /// speak future (iOS/macOS may never settle that future after cancel).
  Future<void> stop();
}

/// Platform TTS operations the production service interprets. Tests inject
/// failures here — that is still the production [FlutterTtsSpeechService]
/// path, not [SilentSpeechService].
abstract class TtsClient {
  Future<Object?> speak(String text);
  Future<void> stop();
}

/// Default implementation backed by the platform's TTS engine (Google TTS on
/// Android, system voices on macOS, SpeechSynthesis on web), set to Japanese.
class FlutterTtsSpeechService implements SpeechService {
  FlutterTtsSpeechService({required this.client, required this.ready});

  final TtsClient client;
  final bool ready;
  int _token = 0;
  Completer<SpeechPlaybackResult>? _pending;

  static Future<FlutterTtsSpeechService> create() async {
    final tts = FlutterTts();
    var ready = false;
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
      final language = await tts.setLanguage('ja-JP');
      await tts.setSpeechRate(0.5); // natural pace
      await tts.setPitch(1.0);
      try {
        await tts.awaitSpeakCompletion(true);
      } catch (_) {
        // Some engines do not support completion awaiting.
      }
      ready = _acceptedLanguage(language);
    } catch (_) {
      ready = false;
    }
    return FlutterTtsSpeechService(client: FlutterTtsClient(tts), ready: ready);
  }

  @override
  Future<void> speak(String text) async {
    await play(text);
  }

  @override
  Future<SpeechPlaybackResult> play(String text) async {
    if (text.isEmpty) return SpeechPlaybackResult.failed;
    if (!ready) return SpeechPlaybackResult.unavailable;

    _settlePending(SpeechPlaybackResult.interrupted);
    final token = ++_token;
    final pending = Completer<SpeechPlaybackResult>();
    _pending = pending;

    try {
      await client.stop();
    } catch (_) {}
    if (token != _token) {
      _settle(pending, SpeechPlaybackResult.interrupted);
      return pending.future;
    }

    unawaited(_driveSpeak(token, text, pending));
    return pending.future;
  }

  Future<void> _driveSpeak(
    int token,
    String text,
    Completer<SpeechPlaybackResult> pending,
  ) async {
    try {
      final result = await client.speak(text);
      if (token != _token) {
        _settle(pending, SpeechPlaybackResult.interrupted);
        return;
      }
      _settle(
        pending,
        _acceptedSpeak(result)
            ? SpeechPlaybackResult.played
            : SpeechPlaybackResult.failed,
      );
    } catch (_) {
      if (token != _token) {
        _settle(pending, SpeechPlaybackResult.interrupted);
        return;
      }
      _settle(pending, SpeechPlaybackResult.failed);
    }
  }

  @override
  Future<void> stop() async {
    _token++;
    _settlePending(SpeechPlaybackResult.interrupted);
    try {
      await client.stop();
    } catch (_) {}
  }

  void _settlePending(SpeechPlaybackResult result) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(result);
    }
  }

  void _settle(
    Completer<SpeechPlaybackResult> pending,
    SpeechPlaybackResult result,
  ) {
    if (!pending.isCompleted) {
      pending.complete(result);
    }
    if (identical(_pending, pending)) {
      _pending = null;
    }
  }

  static bool _acceptedSpeak(Object? result) {
    if (result == null) return true;
    if (result == 1 || result == true) return true;
    return false;
  }

  static bool _acceptedLanguage(Object? result) {
    if (result == null) return true;
    if (result == 1 || result == true) return true;
    if (result == 0 || result == false) return false;
    if (result is String && result.toLowerCase().startsWith('ja')) {
      return true;
    }
    return false;
  }
}

/// flutter_tts adapter. UI must not import flutter_tts directly.
class FlutterTtsClient implements TtsClient {
  FlutterTtsClient(this._tts);

  final FlutterTts _tts;

  @override
  Future<Object?> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

/// A no-op speech service for tests and environments without TTS.
///
/// [speak] still completes so existing screens keep working. [play] reports
/// [SpeechPlaybackResult.unavailable] — widget greens here are not audio
/// evidence.
class SilentSpeechService implements SpeechService {
  const SilentSpeechService();

  @override
  Future<void> speak(String text) async {}

  @override
  Future<SpeechPlaybackResult> play(String text) async =>
      SpeechPlaybackResult.unavailable;

  @override
  Future<void> stop() async {}
}
