// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:kotonoha/data/services/speech_service.dart';

/// Production-path TTS double. [FlutterTtsSpeechService] interprets these
/// outcomes the same way it interprets flutter_tts — this is not
/// [SilentSpeechService].
class FakeTtsClient implements TtsClient {
  FakeTtsClient({this.speakResult = 1, this.speakError, this.holdSpeak});

  Object? speakResult;
  Object? speakError;
  Completer<Object?>? holdSpeak;

  final List<String> spoken = <String>[];
  int stopCount = 0;
  Completer<Object?>? _inFlight;

  @override
  Future<Object?> speak(String text) async {
    spoken.add(text);
    _inFlight = holdSpeak;
    try {
      if (_inFlight != null) return await _inFlight!.future;
      if (speakError != null) throw speakError!;
      return speakResult;
    } finally {
      _inFlight = null;
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    final held = _inFlight;
    if (held != null && !held.isCompleted) {
      held.completeError(StateError('stopped'));
    }
  }
}

/// Scripted listen-first service for widget tests. Each [play] consumes the
/// next result; [SilentSpeechService] must not be used as audio success.
class ScriptedSpeechService implements SpeechService {
  ScriptedSpeechService(this._results);

  final List<SpeechPlaybackResult> _results;
  final List<String> spoken = <String>[];
  int stopCount = 0;
  int _index = 0;

  @override
  Future<void> speak(String text) async {
    await play(text);
  }

  @override
  Future<SpeechPlaybackResult> play(String text) async {
    spoken.add(text);
    if (_results.isEmpty) return SpeechPlaybackResult.unavailable;
    final i = _index < _results.length ? _index : _results.length - 1;
    _index++;
    return _results[i];
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

/// A play that stays open until [stop] or [complete].
class HangingSpeechService implements SpeechService {
  final Completer<SpeechPlaybackResult> _completer =
      Completer<SpeechPlaybackResult>();
  final List<String> spoken = <String>[];
  int stopCount = 0;

  bool get isCompleted => _completer.isCompleted;

  void complete(SpeechPlaybackResult result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }

  @override
  Future<void> speak(String text) async {
    await play(text);
  }

  @override
  Future<SpeechPlaybackResult> play(String text) {
    spoken.add(text);
    return _completer.future;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    complete(SpeechPlaybackResult.interrupted);
  }
}
