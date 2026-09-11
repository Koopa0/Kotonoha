// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/info/info_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_tts_client.dart';

final _amount3k = kInfoDrills.firstWhere((d) => d.id == 'info:amount-3000');
final _amount5k = kInfoDrills.firstWhere((d) => d.id == 'info:amount-5000');
final _person3 = kInfoDrills.firstWhere((d) => d.id == 'info:person-3');
final _time330 = kInfoDrills.firstWhere((d) => d.id == 'info:time-330pm');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({InMemoryAnalyticsLog analytics})> pumpInfo(
    WidgetTester tester, {
    required List<InfoDrill> drills,
    Size surface = const Size(420, 1200),
  }) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    final analytics = InMemoryAnalyticsLog();
    final speech = ScriptedSpeechService(const [
      SpeechPlaybackResult.played,
      SpeechPlaybackResult.played,
      SpeechPlaybackResult.played,
    ]);
    await tester.binding.setSurfaceSize(surface);
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
          Provider<AnalyticsLog>.value(value: analytics),
        ],
        child: MaterialApp(
          home: InfoScreen(
            drills: drills,
            clock: () => DateTime(2026, 9, 11, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return (analytics: analytics);
  }

  Future<void> hearThenPick(WidgetTester tester, {required String answer}) async {
    await tester.ensureVisible(find.text(answer));
    await tester.tap(find.text(answer));
    await tester.pumpAndSettle();
  }

  testWidgets('amount 3000日圓 is independent without revealing kana first', (
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
    final env = await pumpInfo(
      tester,
      drills: [_amount3k],
      surface: const Size(320, 640),
    );
    expect(find.text('3000日圓'), findsOneWidget);
    expect(find.text('6000日圓'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('info-prompt-kana')), findsNothing);
    await hearThenPick(tester, answer: '3000日圓');
    final logged = await env.analytics.all();
    expect(logged, hasLength(1));
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.independent);
    expect(logged[0].meta[AttemptMeta.scored], isTrue);
    expect(logged[0].correct, isTrue);
  });

  testWidgets('wrong amount choice scores miss', (tester) async {
    final env = await pumpInfo(tester, drills: [_amount3k]);
    await hearThenPick(tester, answer: '6000日圓');
    final logged = await env.analytics.all();
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.miss);
    expect(logged[0].meta[AttemptMeta.scored], isTrue);
    expect(logged[0].correct, isFalse);
  });

  testWidgets('hinted time answer is not independent', (tester) async {
    final env = await pumpInfo(tester, drills: [_time330]);
    await tester.tap(find.byKey(const ValueKey<String>('info-hint')));
    await tester.pumpAndSettle();
    expect(find.text('（時間是）下午三點半'), findsOneWidget);
    await hearThenPick(tester, answer: '下午3點半');
    final logged = await env.analytics.all();
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.hinted);
    expect(logged[0].meta[AttemptMeta.hinted], isTrue);
    expect(logged[0].correct, isTrue);
  });

  testWidgets('migration amount-5000日圓 is independent at 320×640 / 2x', (
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
    final env = await pumpInfo(
      tester,
      drills: [_amount5k],
      surface: const Size(320, 640),
    );
    expect(find.text('5000日圓'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('info-prompt-kana')), findsNothing);
    await hearThenPick(tester, answer: '5000日圓');
    final logged = await env.analytics.all();
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.independent);
    expect(logged[0].correct, isTrue);
  });

  testWidgets('migration person-3位 scores miss on 2位', (tester) async {
    final env = await pumpInfo(tester, drills: [_person3]);
    await hearThenPick(tester, answer: '2位');
    final logged = await env.analytics.all();
    expect(logged[0].meta[AttemptMeta.evidence], ReplyEvidence.miss);
    expect(logged[0].correct, isFalse);
  });
}
