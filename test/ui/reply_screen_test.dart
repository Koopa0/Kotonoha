// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/reply_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/reply/reply_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

final _ekiAsk = kReplyDrills.firstWhere((d) => d.id == 'reply:eki-wa-doko');
final _whereGo = kReplyDrills.firstWhere((d) => d.id == 'reply:doko-e-iku');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({
      WordProgressRepository words,
      InMemoryAnalyticsLog analytics,
      SpeechService speech,
    })
  >
  pumpReply(
    WidgetTester tester, {
    required List<ReplyDrill> drills,
    SpeechService? speech,
  }) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    final spoken =
        speech ??
        ScriptedSpeechService(const [
          SpeechPlaybackResult.played,
          SpeechPlaybackResult.played,
          SpeechPlaybackResult.played,
          SpeechPlaybackResult.played,
          SpeechPlaybackResult.played,
          SpeechPlaybackResult.played,
        ]);
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: spoken),
          Provider<AnalyticsLog>.value(value: analytics),
        ],
        child: MaterialApp(
          home: ReplyScreen(
            drills: drills,
            clock: () => DateTime(2026, 9, 11, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return (words: words, analytics: analytics, speech: spoken);
  }

  testWidgets('independent hear → intent → reply does not write SRS', (
    tester,
  ) async {
    final env = await pumpReply(tester, drills: [_ekiAsk]);
    expect(find.text(AppStrings.replyIntentPrompt), findsOneWidget);
    expect(find.text('えきは どこ'), findsNothing);
    expect(find.text('車站在哪裡'), findsNothing);

    await tester.tap(find.text('問車站在哪裡'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reply-to-answer')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.replyReplyPrompt), findsWidgets);
    await tester.tap(find.text('みぎです'));
    await tester.pumpAndSettle();
    expect(find.text('在右邊'), findsOneWidget);

    final logged = await env.analytics.all();
    expect(logged, hasLength(2));
    expect(logged.every((a) => a.mode == PracticeMode.reply.name), isTrue);
    expect(logged[0].meta[AttemptMeta.beat], ReplyEvidence.intent);
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.independent);
    expect(logged[0].meta[AttemptMeta.heard], isTrue);
    expect(logged[0].correct, isTrue);
    expect(logged[1].meta[AttemptMeta.beat], ReplyEvidence.reply);
    expect(logged[1].meta[AttemptMeta.evidence], ReplyEvidence.independent);
    expect(env.words.statForItem('phrase:えきは どこ').srsLevel, 0);
    expect(env.words.statForItem('phrase:えきは どこ').isSeen, isFalse);
  });

  testWidgets('seeing Japanese is peeked, not independent', (tester) async {
    final env = await pumpReply(tester, drills: [_whereGo]);
    await tester.tap(find.byKey(const ValueKey<String>('reply-show-text')));
    await tester.pumpAndSettle();
    expect(find.text('どこへ いく'), findsOneWidget);
    await tester.tap(find.text('問你要去哪裡'));
    await tester.pumpAndSettle();
    final logged = await env.analytics.all();
    expect(logged.single.meta[AttemptMeta.evidence], ReplyEvidence.peeked);
    expect(logged.single.meta[AttemptMeta.prompted], isTrue);
    expect(logged.single.correct, isTrue);
  });

  testWidgets('meaning hint is hinted evidence, not a self-grade', (
    tester,
  ) async {
    final env = await pumpReply(tester, drills: [_whereGo]);
    await tester.tap(find.byKey(const ValueKey<String>('reply-hint')));
    await tester.pumpAndSettle();
    expect(find.text('要去哪裡'), findsOneWidget);
    await tester.tap(find.text('問你要去哪裡'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reply-to-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('きょうとです'));
    await tester.pumpAndSettle();
    final logged = await env.analytics.all();
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.hinted);
    expect(logged[0].meta[AttemptMeta.hinted], isTrue);
    expect(logged[1].meta[AttemptMeta.evidence], ReplyEvidence.hinted);
    expect(logged[1].correct, isTrue);
  });

  testWidgets('unavailable play cannot score a heard success', (tester) async {
    final env = await pumpReply(
      tester,
      drills: [_ekiAsk],
      speech: const SilentSpeechService(),
    );
    expect(find.text(AppStrings.listeningUnavailable), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('reply-skip')));
    await tester.pumpAndSettle();
    final logged = await env.analytics.all();
    expect(logged.single.meta[AttemptMeta.evidence], ReplyEvidence.unheard);
    expect(logged.single.meta[AttemptMeta.scored], isFalse);
    expect(logged.single.correct, isFalse);
    expect(find.text(AppStrings.replyClose), findsOneWidget);
  });

  testWidgets('leaving the route stops leftover playback', (tester) async {
    final speech = HangingSpeechService();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: kanji.flushPending,
              wordFlush: words.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: speech),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  ReplyScreen.route([_ekiAsk]),
                ),
                child: const Text('open-reply'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(speech.spoken, ['えきはどこ']);
    expect(speech.stopCount, 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(speech.stopCount, 1);
    expect(speech.isCompleted, isTrue);
  });

  testWidgets('320×640 / 2x keeps the ask readable without leaking kana', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await pumpReply(tester, drills: [_ekiAsk]);
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.replyIntentPrompt), findsOneWidget);
    expect(find.text('問車站在哪裡'), findsOneWidget);
    expect(find.text('えきは どこ'), findsNothing);
  });
}
