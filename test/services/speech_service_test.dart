// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/speech_service.dart';

import '../helpers/fake_tts_client.dart';

void main() {
  test(
    'SilentSpeechService.play is unavailable — not audio evidence',
    () async {
      const silent = SilentSpeechService();
      expect(await silent.play('えき'), SpeechPlaybackResult.unavailable);
      await silent.speak('えき');
      await silent.stop();
    },
  );

  test(
    'unready production service reports unavailable and never speaks',
    () async {
      final client = FakeTtsClient();
      final speech = FlutterTtsSpeechService(client: client, ready: false);
      expect(await speech.play('えきはどこ'), SpeechPlaybackResult.unavailable);
      expect(client.spoken, isEmpty);
    },
  );

  test('empty text is failed, not played', () async {
    final client = FakeTtsClient();
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    expect(await speech.play(''), SpeechPlaybackResult.failed);
    expect(client.spoken, isEmpty);
  });

  test('platform 1 / true is played', () async {
    final ones = FakeTtsClient();
    expect(
      await FlutterTtsSpeechService(client: ones, ready: true).play('えき'),
      SpeechPlaybackResult.played,
    );
    expect(ones.spoken, ['えき']);

    final truthy = FakeTtsClient(speakResult: true);
    expect(
      await FlutterTtsSpeechService(client: truthy, ready: true).play('ここ'),
      SpeechPlaybackResult.played,
    );
  });

  test('platform 0 / false is failed — production failure injection', () async {
    final zero = FakeTtsClient(speakResult: 0);
    expect(
      await FlutterTtsSpeechService(client: zero, ready: true).play('えき'),
      SpeechPlaybackResult.failed,
    );
    expect(zero.spoken, ['えき']);

    final falsy = FakeTtsClient(speakResult: false);
    expect(
      await FlutterTtsSpeechService(client: falsy, ready: true).play('えき'),
      SpeechPlaybackResult.failed,
    );
  });

  test('engine throw is failed', () async {
    final client = FakeTtsClient(speakError: Exception('no voice'));
    expect(
      await FlutterTtsSpeechService(client: client, ready: true).play('えき'),
      SpeechPlaybackResult.failed,
    );
  });

  test('stop interrupts an in-flight production play', () async {
    final held = Completer<Object?>();
    final client = FakeTtsClient(holdSpeak: held);
    final speech = FlutterTtsSpeechService(client: client, ready: true);

    final pending = speech.play('もういちどいってください');
    await Future<void>.delayed(Duration.zero);
    expect(client.spoken, ['もういちどいってください']);

    await speech.stop();
    expect(await pending, SpeechPlaybackResult.interrupted);
    expect(client.stopCount, greaterThanOrEqualTo(1));
  });

  test('a newer play interrupts the previous one', () async {
    final held = Completer<Object?>();
    final client = FakeTtsClient(holdSpeak: held);
    final speech = FlutterTtsSpeechService(client: client, ready: true);

    final first = speech.play('えき');
    await Future<void>.delayed(Duration.zero);
    client.holdSpeak = null;
    client.speakResult = 1;
    final second = speech.play('きっぷ');
    expect(await first, SpeechPlaybackResult.interrupted);
    expect(await second, SpeechPlaybackResult.played);
    expect(client.spoken, ['えき', 'きっぷ']);
  });

  test('speak still completes when play fails', () async {
    final client = FakeTtsClient(speakResult: 0);
    final speech = FlutterTtsSpeechService(client: client, ready: true);
    await speech.speak('えき');
    expect(client.spoken, ['えき']);
  });
}
