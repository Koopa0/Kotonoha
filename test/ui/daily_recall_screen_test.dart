// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final kana = kHiraganaGojuon.first;

  SessionItem recallItem() => SessionItem(
    question: QuizQuestion(
      target: kana,
      direction: QuizDirection.kanaRecall,
      options: const [],
      correctIndex: 0,
    ),
    mode: PracticeMode.daily,
  );

  Future<void> pumpRecall(
    WidgetTester tester, {
    List<Word> transfer = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: repo),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: repo.flushPending,
              kanjiFlush: () async {},
              wordFlush: words.flushPending,
            ),
          ),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        ],
        child: MaterialApp(
          home: QuizScreen(
            items: [recallItem()],
            title: AppStrings.dailySession,
            transferItems: transfer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone recall: glyph shown, reading hidden, no option grid', (
    tester,
  ) async {
    await pumpRecall(tester);
    expect(find.text(kana.character), findsOneWidget);
    expect(find.text(AppStrings.readPrompt), findsOneWidget);
    expect(find.text(kana.romaji), findsNothing);
    expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);
    expect(find.text(AppStrings.recallHint), findsOneWidget);
    expect(find.text(AppStrings.chooseKana), findsNothing);
  });

  testWidgets('unprompted 讀得出來 reveals for confirm and does not write yet', (
    tester,
  ) async {
    await pumpRecall(tester);
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pump();
    expect(find.text(kana.romaji), findsOneWidget);
    expect(find.text(AppStrings.iReadIt), findsOneWidget);
    expect(find.text(AppStrings.seeResults), findsNothing);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pump();
    expect(find.text(AppStrings.seeResults), findsOneWidget);
  });

  testWidgets('hinted recall shows romaji then does not count as unprompted', (
    tester,
  ) async {
    await pumpRecall(tester);
    await tester.tap(find.text(AppStrings.recallHint));
    await tester.pumpAndSettle();
    expect(find.text(kana.romaji), findsOneWidget);
    await tester.tap(find.text(AppStrings.iReadAfterHint));
    await tester.pump();
    expect(find.text(AppStrings.seeResults), findsOneWidget);
  });

  testWidgets('after the kana run, transfer opens 黙読-style reading', (
    tester,
  ) async {
    await pumpRecall(
      tester,
      transfer: const [Word(kana: 'ホテル', romaji: 'hoteru', meaning: '飯店')],
    );
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pump();
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pump(); // grade
    await tester.pump(const Duration(milliseconds: 800)); // auto-advance
    await tester.pumpAndSettle();
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.text('ホテル'), findsOneWidget);
    expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);
  });
}
