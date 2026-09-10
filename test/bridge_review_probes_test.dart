// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reviewer P2 probes: hinted recall must not renew, new-sentence intake
/// must persist, もう一回 must cover remaining words, confirm-after-commit,
/// and quiet transfer must not speak.
class _SpySpeechService implements SpeechService {
  final List<String> spoken = [];

  @override
  Future<void> speak(String text) async => spoken.add(text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);
  final e = kHiraganaGojuon.firstWhere((k) => k.character == 'え');

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  test(
    'P2-1 hinted recall on overdue え does not increment correct or renew due',
    () async {
      final due = now.subtract(const Duration(days: 10));
      SharedPreferences.setMockInitialValues({
        'kana_stats_v1': jsonEncode({
          'え': {
            's': 10,
            'c': 10,
            'sl': 6,
            'd': due.millisecondsSinceEpoch,
            'l': due.millisecondsSinceEpoch,
          },
        }),
      });
      final repo = await KanaProgressRepository.load();
      final before = repo.statFor(e);
      expect(before.correctCount, 10);
      expect(before.srsLevel, 6);
      expect(before.dueAt, due);
      expect(before.lastMistakeAt, isNull);

      final log = InMemoryAnalyticsLog();
      final vm = QuizViewModel(
        items: [
          SessionItem(
            question: QuizQuestion(
              target: e,
              direction: QuizDirection.kanaRecall,
              options: const [],
              correctIndex: 0,
            ),
            mode: PracticeMode.daily,
          ),
        ],
        repository: repo,
        persistence: owner(),
        analytics: log,
        clock: () => now,
      );
      vm.gradeRecall(correct: true, unprompted: false);

      final after = repo.statFor(e);
      expect(after.correctCount, 10);
      expect(after.srsLevel, 6);
      expect(after.dueAt, due);
      expect(after.lastMistakeAt, isNull);
      expect(after.seenCount, 11);
      final attempt = (await log.all()).single;
      expect(attempt.correct, isTrue);
      expect(attempt.meta[AttemptMeta.prompted], isTrue);
      vm.dispose();
    },
  );

  testWidgets(
    'P2-2 prompted new sentences stay introduced; next ReadingSet is not the same intake',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      final learned = {for (final k in kAllKana) k.character};
      final first = ReadingSet.session(
        items: kPhrases,
        learnedChars: learned,
        rng: Random(1),
        now: now,
        stats: words.stats,
        length: 3,
      );
      expect(first.map((p) => p.kana).toSet(), {
        'そらが あおい',
        'なつの かぜ',
        'うみが みえる',
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
            ChangeNotifierProvider<WordProgressRepository>.value(value: words),
            ChangeNotifierProvider<ProgressPersistenceController>.value(
              value: ProgressPersistenceController(
                kanaFlush: kana.flushPending,
                kanjiFlush: () async {},
                wordFlush: words.flushPending,
              ),
            ),
            Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
            Provider<SpeechService>.value(value: const SilentSpeechService()),
          ],
          child: MaterialApp(
            home: ReadingScreen(items: first, title: AppStrings.sentenceTitle),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(AppStrings.recallHint));
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.iReadAfterHint));
        await tester.pumpAndSettle();
      }

      expect(words.seenItemCount, 3);
      for (final p in first) {
        final s = words.statForItem(p.progressId);
        expect(s.isSeen, isTrue);
        expect(s.correctCount, 0);
        expect(s.srsLevel, 0);
      }

      // Same clock as the screen: introduce parks due 10 minutes ahead, so
      // the next compose must treat them as seen — not a fresh intake batch.
      final second = ReadingSet.session(
        items: kPhrases,
        learnedChars: learned,
        rng: Random(1),
        now: DateTime.now(),
        stats: words.stats,
        length: 3,
      );
      expect(
        second.map((p) => p.kana).toSet().intersection({
          'そらが あおい',
          'なつの かぜ',
          'うみが みえる',
        }),
        isEmpty,
        reason: 'introduced sentences must leave the unseen intake queue',
      );
    },
  );

  test('P2-3 accumulated もう一回 covers ちかてつ and does not farm two travel words to level 6', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await WordProgressRepository.load();
    final pool = [
      kWords.firstWhere((w) => w.kana == 'いりぐち'),
      kWords.firstWhere((w) => w.kana == 'でぐち'),
      kWords.firstWhere((w) => w.kana == 'ちかてつ'),
    ];
    for (final w in pool) {
      await repo.markIntroduced(w.progressId, at: now);
    }
    final chi = kAllKana.firstWhere((k) => k.character == 'ち');
    final learned = {for (final w in pool) ...KanaTokenizer.tokenize(w.kana)};
    var exclude = <String>{};
    final shown = <String>[];
    for (var i = 0; i < 12; i++) {
      final items = DailyBridge.compose(
        sessionKana: [chi],
        words: pool,
        phrases: const [],
        learnedChars: learned,
        wordStats: repo.stats,
        now: now,
        rng: Random(i + 1),
        excludeProgressIds: exclude,
      );
      expect(items, isNotEmpty);
      for (final item in items.whereType<Word>()) {
        shown.add(item.kana);
        if (DailyBridge.shouldRenew(item.progressId, exclude)) {
          await repo.recordAnswer(item.progressId, correct: true, at: now);
        }
      }
      exclude = DailyBridge.nextExclude(previous: exclude, transfer: items);
    }
    expect(shown.toSet(), containsAll(['いりぐち', 'でぐち', 'ちかてつ']));
    expect(shown.where((k) => k == 'ちかてつ'), isNotEmpty);
    expect(repo.statForItem('word:いりぐち').srsLevel, lessThan(6));
    expect(repo.statForItem('word:でぐち').srsLevel, lessThan(6));
    expect(repo.statForItem('word:ちかてつ').srsLevel, lessThan(6));
    expect(repo.statForItem('word:ちかてつ').isSeen, isTrue);
  });

  testWidgets('P2-4 讀得出來 reveals the answer before any schedule write', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
          ChangeNotifierProvider<WordProgressRepository>.value(value: words),
          ChangeNotifierProvider<ProgressPersistenceController>.value(
            value: ProgressPersistenceController(
              kanaFlush: kana.flushPending,
              kanjiFlush: () async {},
              wordFlush: words.flushPending,
            ),
          ),
          Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
          Provider<SpeechService>.value(value: const SilentSpeechService()),
        ],
        child: const MaterialApp(
          home: ReadingScreen(
            items: [Word(kana: 'いぬ', romaji: 'inu', meaning: '狗')],
            title: AppStrings.sentenceTitle,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await tester.pumpAndSettle();
    expect(find.text('inu'), findsOneWidget);
    expect(words.statForItem('word:いぬ').correctCount, 0);
    expect(words.statForItem('word:いぬ').isSeen, isFalse);
    await tester.tap(find.text(AppStrings.iReadIt));
    await tester.pumpAndSettle();
    expect(words.statForItem('word:いぬ').correctCount, 1);
  });

  testWidgets('P2-5 quiet transfer reveal does not speak', (tester) async {
    final spoken = await _revealHotel(tester, quiet: true);
    expect(spoken, isEmpty);
  });

  testWidgets('P2-5 non-quiet transfer reveal still speaks', (tester) async {
    final spoken = await _revealHotel(tester, quiet: false);
    expect(spoken, ['ホテル']);
  });
}

Future<List<String>> _revealHotel(
  WidgetTester tester, {
  required bool quiet,
}) async {
  SharedPreferences.setMockInitialValues({});
  const hotel = Word(kana: 'ホテル', romaji: 'hoteru', meaning: '飯店');
  final spy = _SpySpeechService();
  final kana = await KanaProgressRepository.load();
  final words = await WordProgressRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            kanjiFlush: () async {},
            wordFlush: words.flushPending,
          ),
        ),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
        Provider<SpeechService>.value(value: spy),
      ],
      child: MaterialApp(
        home: ReadingScreen(
          items: const [hotel],
          title: AppStrings.dailySession,
          quiet: quiet,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.recallHint));
  await tester.pumpAndSettle();
  return List<String>.from(spy.spoken);
}
