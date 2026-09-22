// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/widgets/japanese_written_form.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';
import 'listening_screen_test.dart' show pumpListening;
import 'word_written_form_flow_test.dart' show pumpPage, tap;

Phrase phrase(String kana) => kPhrases.singleWhere((p) => p.kana == kana);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final kana in [
    'えきは どこ',
    'カードは つかえません',
    'よやくが あります',
    'この バスは くうこうに いきますか',
  ]) {
    testWidgets(
      'reading reveals $kana at 320px / 2x without renaming progress',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final item = phrase(kana);
        final words = await WordProgressRepository.load();
        await words.introduce(item.progressId, at: DateTime(2026, 9));
        final before = words.statForItem(item.progressId).srsLevel;
        final speech = ScriptedSpeechService(const [
          SpeechPlaybackResult.played,
        ]);
        await pumpPage(
          tester,
          ReadingScreen(
            items: [item, phrase('ただいま')],
            title: AppStrings.sentenceTitle,
          ),
          words,
          speech,
        );
        expect(find.text(item.kana), findsOneWidget);
        expect(find.text(item.writtenForm!), findsNothing);
        expect(find.byType(JapaneseWrittenForm), findsNothing);
        await tap(tester, AppStrings.recallHint);
        await tester.ensureVisible(find.text(item.writtenForm!));
        await tester.pumpAndSettle();
        expect(find.text(item.writtenForm!).hitTestable(), findsOneWidget);
        expect(find.text(item.meaning), findsOneWidget);
        expect(words.statForItem(item.progressId).srsLevel, before);
        await tap(tester, AppStrings.iReadAfterHint);
        expect(find.byType(JapaneseWrittenForm), findsNothing);
        expect(find.text(item.writtenForm!), findsNothing);
        expect(speech.spoken, [item.kana.replaceAll(' ', '')]);
        await words.flushPending();
        final restored = await WordProgressRepository.load();
        expect(restored.statForItem(item.progressId).srsLevel, before);
        expect(
          restored.statForItem('phrase:${item.writtenForm}').isSeen,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'travel listening reveals orthography only after hearing; next resets',
    (tester) async {
      final item = phrase('ひこうきに のります');
      final speech = ScriptedSpeechService(const [SpeechPlaybackResult.played]);
      final words = await WordProgressRepository.load();
      await pumpListening(
        tester,
        speech: speech,
        items: [item, phrase('よやくが あります')],
        wordRepo: words,
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(find.text(item.writtenForm!), findsNothing);
      expect(find.text(item.kana), findsNothing);
      await tap(tester, AppStrings.listeningReveal);
      expect(find.text('飛行機に乗ります'), findsOneWidget);
      await tap(tester, AppStrings.listeningHeard);
      expect(find.byType(JapaneseWrittenForm), findsNothing);
      expect(words.statForItem(item.progressId).isSeen, isTrue);
      expect(words.statForItem('sentence:飛行機に乗ります').isSeen, isFalse);
      expect(speech.spoken.first, 'ひこうきにのります');
      await tap(tester, AppStrings.listeningReveal);
      expect(find.text('予約があります'), findsOneWidget);
      await tap(tester, AppStrings.listeningHeard);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('naturally kana-only phrase retains its ordinary spelling', (
    tester,
  ) async {
    final words = await WordProgressRepository.load();
    await pumpPage(
      tester,
      ReadingScreen(items: [phrase('ただいま')], title: AppStrings.sentenceTitle),
      words,
      const SilentSpeechService(),
    );
    await tap(tester, AppStrings.recallHint);
    expect(
      find.descendant(
        of: find.byType(JapaneseWrittenForm),
        matching: find.text('ただいま'),
      ),
      findsOneWidget,
    );
    await tap(tester, AppStrings.iReadAfterHint);
    expect(tester.takeException(), isNull);
  });
}
