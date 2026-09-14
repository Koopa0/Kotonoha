// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/preferences_service.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/ui/kanji_sentence_screen.dart';
import 'package:kotonoha/kanji/ui/ruby_text.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restore_recovery_test_support.dart';

const _yamaId = 'sentence:山を見る';

DateTime _noon() => DateTime(2026, 9, 11, 12);

Future<void> _learnAll(KanaProgressRepository kana) async {
  for (final lesson in Lessons.fromKana(kana.allKana)) {
    await kana.markUnitLearned(lesson.id);
  }
}

Future<void> _fadeReadings(
  KanjiReadingRepository kanji, {
  Iterable<String>? unitIds,
}) async {
  final now = _noon();
  final ids =
      unitIds ??
      {
        for (final phrase in kKanjiPhrases)
          for (final segment in phrase.segments)
            if (segment.unitId != null) segment.unitId!,
      };
  for (final id in ids) {
    for (var i = 0; i < ReadingStat.kFuriganaFadeLevel; i++) {
      await kanji.recordAnswer(id, correct: true, at: now);
    }
  }
}

Future<InMemoryAnalyticsLog> _pumpHome(
  WidgetTester tester, {
  required KanaProgressRepository kana,
  required WordProgressRepository words,
  KanjiReadingRepository? kanji,
}) async {
  kanji ??= await KanjiReadingRepository.load();
  final prefs = await PreferencesService.create();
  final recovery = recoveryForRepos(
    prefs: prefs,
    kana: kana,
    kanji: kanji,
    words: words,
  );
  final analytics = InMemoryAnalyticsLog();
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final travel = await TravelFocusRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TravelFocusRepository>.value(value: travel),
        ChangeNotifierProvider<KanaProgressRepository>.value(value: kana),
        ChangeNotifierProvider<KanjiReadingRepository>.value(value: kanji),
        ChangeNotifierProvider<WordProgressRepository>.value(value: words),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: kana.flushPending,
            kanjiFlush: kanji.flushPending,
            wordFlush: words.flushPending,
            health: [
              kana.statsHealth,
              kana.learnedUnitsHealth,
              kana.seenUnlocksHealth,
              kanji.statsHealth,
              words.statsHealth,
            ],
          ),
        ),
        ChangeNotifierProvider<ProgressRestoreRecoveryController>.value(
          value: recovery,
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: analytics),
      ],
      child: const MaterialApp(home: HomeScreen(clock: _noon)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return analytics;
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

String _shownId(WidgetTester tester) {
  return tester.widget<RubyText>(find.byType(RubyText)).phrase.progressId;
}

List<double> _rubyOpacities(WidgetTester tester, List<String> furigana) {
  return [
    for (final text in furigana)
      tester
          .widget<Opacity>(
            find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
          )
          .opacity,
  ];
}

Future<void> _reachPhrase(WidgetTester tester, String id) async {
  var steps = 0;
  while (_shownId(tester) != id) {
    expect(steps, lessThan(12), reason: 'never reached $id');
    await _confirmPrompted(tester);
    steps++;
  }
}

Future<String> _confirmUnprompted(WidgetTester tester) async {
  final shown = _shownId(tester);
  await tester.tap(find.text(AppStrings.iReadUnprompted));
  await _pumpFrame(tester);
  await tester.tap(find.text(AppStrings.iReadIt));
  await _pumpFrame(tester);
  return shown;
}

Future<String> _confirmPrompted(WidgetTester tester) async {
  final shown = _shownId(tester);
  await tester.tap(find.text(AppStrings.recallHint));
  await _pumpFrame(tester);
  await tester.tap(find.text(AppStrings.iReadAfterHint));
  await _pumpFrame(tester);
  return shown;
}

Future<void> _confirmUntilMore(
  WidgetTester tester, {
  required Future<void> Function() confirm,
}) async {
  var steps = 0;
  while (find.text(AppStrings.practiceAgain).evaluate().isEmpty) {
    expect(steps, lessThan(12), reason: 'session never reached もう一回');
    await confirm();
    steps++;
  }
}

int _dueDays(WordProgressRepository words, String id, DateTime now) {
  final due = words.statForItem(id).dueAt;
  expect(due, isNotNull);
  return due!.difference(now).inDays;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Home 漢字句 もう一回: formal More keeps [2, 2] after reload', (
    tester,
  ) async {
    final now = _noon();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await _learnAll(kana);
    await _fadeReadings(kanji);
    await words.introduce(_yamaId, at: now);
    expect(words.statForItem(_yamaId).srsLevel, 1);
    await _pumpHome(tester, kana: kana, words: words, kanji: kanji);

    await tester.ensureVisible(find.text(AppStrings.readKanjiSentencesAction));
    await tester.tap(find.text(AppStrings.readKanjiSentencesAction));
    await _pumpFrame(tester);
    var screen = tester.widget<KanjiSentenceScreen>(
      find.byType(KanjiSentenceScreen),
    );
    expect(screen.alreadyTransferredIds, isEmpty);
    expect(screen.phrases.map((p) => p.progressId), contains(_yamaId));
    final firstIds = {for (final phrase in screen.phrases) phrase.progressId};

    final levels = <int>[];
    await _confirmUntilMore(tester, confirm: () => _confirmUnprompted(tester));
    levels.add(words.statForItem(_yamaId).srsLevel);
    expect(find.text(AppStrings.practiceAgain), findsOneWidget);

    await tester.tap(find.text(AppStrings.practiceAgain));
    await _pumpFrame(tester);
    screen = tester.widget<KanjiSentenceScreen>(
      find.byType(KanjiSentenceScreen),
    );
    expect(screen.alreadyTransferredIds, firstIds);
    expect(screen.phrases.map((p) => p.progressId), contains(_yamaId));
    await _confirmUntilMore(tester, confirm: () => _confirmUnprompted(tester));
    levels.add(words.statForItem(_yamaId).srsLevel);

    expect(levels, [2, 2]);
    expect(words.statForItem(_yamaId).correctCount, 2);
    expect(_dueDays(words, _yamaId, now), 3);
    await words.flushPending();
    final reloaded = await WordProgressRepository.load();
    expect(reloaded.statForItem(_yamaId).srsLevel, 2);
    expect(reloaded.statForItem(_yamaId).dueAt!.difference(now).inDays, 3);
  });

  testWidgets('Home 漢字句もう一回: leftover new id still climbs; wrap id does not', (
    tester,
  ) async {
    final now = _noon();
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await _learnAll(kana);
    await _fadeReadings(kanji);
    await words.introduce(_yamaId, at: now);
    await _pumpHome(tester, kana: kana, words: words, kanji: kanji);

    await tester.ensureVisible(find.text(AppStrings.readKanjiSentencesAction));
    await tester.tap(find.text(AppStrings.readKanjiSentencesAction));
    await _pumpFrame(tester);
    await _confirmUntilMore(tester, confirm: () => _confirmUnprompted(tester));
    expect(words.statForItem(_yamaId).srsLevel, 2);

    await tester.tap(find.text(AppStrings.practiceAgain));
    await _pumpFrame(tester);
    final screen = tester.widget<KanjiSentenceScreen>(
      find.byType(KanjiSentenceScreen),
    );
    expect(screen.alreadyTransferredIds, contains(_yamaId));
    final fresh = screen.phrases
        .where(
          (phrase) => !screen.alreadyTransferredIds.contains(phrase.progressId),
        )
        .toList();
    expect(fresh, isNotEmpty);

    await _confirmUntilMore(tester, confirm: () => _confirmUnprompted(tester));
    expect(words.statForItem(_yamaId).srsLevel, 2);
    for (final phrase in fresh) {
      expect(words.statForItem(phrase.progressId).srsLevel, 1);
    }
  });

  testWidgets(
    'Home 漢字句: prompted confirm stays introduced; More leftover still climbs',
    (tester) async {
      final now = _noon();
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      final kanji = await KanjiReadingRepository.load();
      await _learnAll(kana);
      await _fadeReadings(kanji);
      await words.introduce(_yamaId, at: now);
      final analytics = await _pumpHome(
        tester,
        kana: kana,
        words: words,
        kanji: kanji,
      );

      await tester.ensureVisible(
        find.text(AppStrings.readKanjiSentencesAction),
      );
      await tester.tap(find.text(AppStrings.readKanjiSentencesAction));
      await _pumpFrame(tester);
      final first = tester.widget<KanjiSentenceScreen>(
        find.byType(KanjiSentenceScreen),
      );
      expect(first.alreadyTransferredIds, isEmpty);
      final firstIds = {for (final phrase in first.phrases) phrase.progressId};

      await _confirmUntilMore(tester, confirm: () => _confirmPrompted(tester));
      expect(words.statForItem(_yamaId).srsLevel, 1);
      expect(words.statForItem(_yamaId).correctCount, 1);
      for (final id in firstIds.where((id) => id != _yamaId)) {
        expect(words.statForItem(id).isSeen, isTrue);
        expect(words.statForItem(id).correctCount, 0);
        expect(words.statForItem(id).srsLevel, 0);
      }
      final prompted = await analytics.all();
      expect(prompted, isNotEmpty);
      expect(
        prompted.every((a) => a.meta[AttemptMeta.prompted] == true),
        isTrue,
      );

      await tester.tap(find.text(AppStrings.practiceAgain));
      await _pumpFrame(tester);
      final second = tester.widget<KanjiSentenceScreen>(
        find.byType(KanjiSentenceScreen),
      );
      expect(second.alreadyTransferredIds, firstIds);
      final leftover = second.phrases
          .where(
            (phrase) =>
                !second.alreadyTransferredIds.contains(phrase.progressId),
          )
          .toList();
      expect(leftover, isNotEmpty);

      await _confirmUntilMore(
        tester,
        confirm: () => _confirmUnprompted(tester),
      );
      expect(words.statForItem(_yamaId).srsLevel, 1);
      expect(words.statForItem(_yamaId).correctCount, 1);
      for (final phrase in leftover) {
        expect(words.statForItem(phrase.progressId).srsLevel, 1);
        expect(words.statForItem(phrase.progressId).correctCount, 1);
      }
    },
  );

  testWidgets('Home 漢字句: visible ruby on 山を見る is prompted, not independent', (
    tester,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    await _learnAll(kana);
    expect(words.statForItem(_yamaId).isSeen, isFalse);
    final analytics = await _pumpHome(tester, kana: kana, words: words);

    await tester.ensureVisible(find.text(AppStrings.readKanjiSentencesAction));
    await tester.tap(find.text(AppStrings.readKanjiSentencesAction));
    await _pumpFrame(tester);
    expect(
      tester
          .widget<KanjiSentenceScreen>(find.byType(KanjiSentenceScreen))
          .phrases
          .map((p) => p.progressId),
      contains(_yamaId),
    );
    await _reachPhrase(tester, _yamaId);
    expect(_rubyOpacities(tester, ['やま', 'み']), [1.0, 1.0]);

    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await _pumpFrame(tester);
    await tester.tap(find.text(AppStrings.iReadIt));
    await _pumpFrame(tester);

    expect(words.statForItem(_yamaId).isSeen, isTrue);
    expect(words.statForItem(_yamaId).correctCount, 0);
    expect(words.statForItem(_yamaId).srsLevel, 0);
    final yama = (await analytics.all()).where((a) => a.itemId == '山を見る');
    expect(yama, isNotEmpty);
    expect(yama.last.correct, isTrue);
    expect(yama.last.meta[AttemptMeta.prompted], isTrue);
  });

  testWidgets('Home 漢字句: hidden ruby on 山を見る keeps independent success', (
    tester,
  ) async {
    final kana = await KanaProgressRepository.load();
    final words = await WordProgressRepository.load();
    final kanji = await KanjiReadingRepository.load();
    await _learnAll(kana);
    await _fadeReadings(kanji, unitIds: const ['unit:山#やま', 'unit:見#み']);
    expect(words.statForItem(_yamaId).isSeen, isFalse);
    final analytics = await _pumpHome(
      tester,
      kana: kana,
      words: words,
      kanji: kanji,
    );

    await tester.ensureVisible(find.text(AppStrings.readKanjiSentencesAction));
    await tester.tap(find.text(AppStrings.readKanjiSentencesAction));
    await _pumpFrame(tester);
    await _reachPhrase(tester, _yamaId);
    expect(_rubyOpacities(tester, ['やま', 'み']), [0.0, 0.0]);

    await tester.tap(find.text(AppStrings.iReadUnprompted));
    await _pumpFrame(tester);
    await tester.tap(find.text(AppStrings.iReadIt));
    await _pumpFrame(tester);

    expect(words.statForItem(_yamaId).correctCount, 1);
    expect(words.statForItem(_yamaId).srsLevel, 1);
    final yama = (await analytics.all()).where((a) => a.itemId == '山を見る');
    expect(yama, isNotEmpty);
    expect(yama.last.correct, isTrue);
    expect(yama.last.meta[AttemptMeta.prompted], isFalse);
  });
}
