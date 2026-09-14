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

  @override
  Future<Object?> speak(String text) async {
    spoken.add(text);
    if (holdSpeak != null) return holdSpeak!.future;
    if (speakError != null) throw speakError!;
    return speakResult;
  }

  /// iOS/macOS flutter_tts: stop returns, but the pending speak future
  /// is not completed. Tests must not assume stop throws or settles speak.
  @override
  Future<void> stop() async {
    stopCount++;
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
  int _generation = 0;

  @override
  Future<void> speak(String text) async {
    await play(text);
  }

  @override
  Future<SpeechPlaybackResult> play(String text) async {
    spoken.add(text);
    _generation++;
    if (_results.isEmpty) return SpeechPlaybackResult.unavailable;
    final i = _index < _results.length ? _index : _results.length - 1;
    _index++;
    return _results[i];
  }

  @override
  int get generation => _generation;

  @override
  Future<void> stop({int? generation}) async {
    if (generation != null && generation != _generation) return;
    _generation++;
    stopCount++;
  }
}

/// Each [play] waits until [complete] or [stop]. Unlike
/// [HangingSpeechService], a later play can wait again — needed when a
/// background interrupt settles the first utterance and the learner
/// replays.
class ControllableSpeechService implements SpeechService {
  Completer<SpeechPlaybackResult>? _pending;
  final List<String> spoken = <String>[];
  int stopCount = 0;
  int _generation = 0;

  bool get isPending => _pending != null && !(_pending?.isCompleted ?? true);

  void complete(SpeechPlaybackResult result) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('no pending play');
    }
    pending.complete(result);
    _pending = null;
  }

  @override
  Future<void> speak(String text) async {
    await play(text);
  }

  @override
  Future<SpeechPlaybackResult> play(String text) {
    spoken.add(text);
    _generation++;
    _pending = Completer<SpeechPlaybackResult>();
    return _pending!.future;
  }

  @override
  int get generation => _generation;

  @override
  Future<void> stop({int? generation}) async {
    if (generation != null && generation != _generation) return;
    _generation++;
    stopCount++;
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete(SpeechPlaybackResult.interrupted);
      _pending = null;
    }
  }
}

/// A play that stays open until [stop] or [complete].
class HangingSpeechService implements SpeechService {
  final Completer<SpeechPlaybackResult> _completer =
      Completer<SpeechPlaybackResult>();
  final List<String> spoken = <String>[];
  int stopCount = 0;
  int _generation = 0;

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
    _generation++;
    return _completer.future;
  }

  @override
  int get generation => _generation;

  @override
  Future<void> stop({int? generation}) async {
    if (generation != null && generation != _generation) return;
    _generation++;
    stopCount++;
    complete(SpeechPlaybackResult.interrupted);
  }
}
