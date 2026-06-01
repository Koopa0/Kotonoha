// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:kotonoha/ui/insights/insights_screen.dart';
import 'package:kotonoha/ui/learn/learn_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/writing/writing_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appTitle)),
      body: SafeArea(
        child: Consumer<KanaProgressRepository>(
          builder: (context, store, _) {
            // Ring tracks the 92 base gojūon (five-fifty); the 116 dakuten/
            // yoon don't dilute the core achievement.
            final gojuon = store.gojuonKana;
            final gojuonSeen = store.seenInSet(gojuon);
            // Words readable with the learner's unlocked kana (feature honesty:
            // the reading entry only appears when something is actually readable).
            final learnedChars = StudySet.learned(
              store,
            ).map((k) => k.character).toSet();
            final readableWords = ReadingSet.readable(kWords, learnedChars);
            final readablePhrases = ReadingSet.readable(kPhrases, learnedChars);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                const SizedBox(height: 8),
                // A quiet wordmark — the name and its meaning, 言の葉 — under a
                // thread of warm light (komorebi).
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '言の葉',
                        style: TextStyle(
                          fontSize: 15,
                          letterSpacing: 6,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 34,
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.komorebi,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: ProgressRing(
                    value: gojuon.isEmpty ? 0 : gojuonSeen / gojuon.length,
                    centerLabel: '$gojuonSeen/${gojuon.length}',
                    caption: AppStrings.practiced,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    store.seenCount == 0
                        ? AppStrings.startFirstReview
                        : AppStrings.overallAccuracy(
                            (store.overallAccuracy * 100).round(),
                          ),
                    style: const TextStyle(color: AppColors.inkMuted),
                  ),
                ),
                const SizedBox(height: 28),
                if (store.learnedUnitCount > 0) ...[
                  FilledButton(
                    onPressed: () => _startDaily(context),
                    child: const Text(AppStrings.dailySession),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: AppColors.hairline),
                      foregroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.of(context).push(LessonsScreen.route()),
                    child: const Text(AppStrings.continueLearning),
                  ),
                ] else
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).push(LessonsScreen.route()),
                    child: const Text(AppStrings.continueLearning),
                  ),
                const SizedBox(height: 20),
                _NavCard(
                  icon: Icons.edit_note_rounded,
                  label: AppStrings.writingEntry,
                  subtitle: AppStrings.writingSubtitle,
                  onTap: () => _startWriting(context),
                ),
                if (readableWords.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _NavCard(
                    icon: Icons.menu_book_rounded,
                    label: AppStrings.readingEntry,
                    subtitle: AppStrings.readingSubtitle,
                    onTap: () => _startReading(context, readableWords),
                  ),
                ],
                if (readablePhrases.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _NavCard(
                    icon: Icons.subject_rounded,
                    label: AppStrings.sentenceEntry,
                    subtitle: AppStrings.sentenceSubtitle,
                    onTap: () => _startSentence(context, readablePhrases),
                  ),
                ],
                const SizedBox(height: 12),
                _NavCard(
                  icon: Icons.grid_view_rounded,
                  label: AppStrings.learnHiragana,
                  subtitle: AppStrings.learnHiraganaSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LearnScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _NavCard(
                  icon: Icons.translate_rounded,
                  label: AppStrings.kanjiEntry,
                  subtitle: AppStrings.kanjiSubtitle,
                  onTap: () => _startKanji(context),
                ),
                // The confusable drill targets look-alike kana specifically —
                // the one review mode the adaptive daily session can't replace.
                if (store.learnedUnitCount > 0) ...[
                  const SizedBox(height: 12),
                  _NavCard(
                    icon: Icons.compare_arrows_rounded,
                    label: AppStrings.confusableEntry,
                    subtitle: AppStrings.confusableSubtitle,
                    onTap: () => _startConfusable(context),
                  ),
                ],
                const SizedBox(height: 12),
                _NavCard(
                  icon: Icons.insights_outlined,
                  label: AppStrings.progress,
                  subtitle: AppStrings.progressSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProgressScreen(),
                    ),
                  ),
                ),
                if (store.seenCount > 0) ...[
                  const SizedBox(height: 12),
                  _NavCard(
                    icon: Icons.query_stats_rounded,
                    label: AppStrings.insightsEntry,
                    subtitle: AppStrings.insightsSubtitle,
                    onTap: () =>
                        Navigator.of(context).push(InsightsScreen.route()),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// The next unlearned lesson's kana, for the "new" slot of a daily session.
  List<Kana> _nextLessonKana(KanaProgressRepository store) {
    final next = Lessons.fromKana(
      store.allKana,
    ).where((l) => !store.isUnitLearned(l.id)).toList();
    return next.isEmpty ? const [] : next.first.kana;
  }

  void _startDaily(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final items = DailySession.compose(
      pool: StudySet.reviewPool(store),
      stats: store.stats,
      newCandidates: _nextLessonKana(store),
      now: DateTime.now(),
      rng: Random(),
    );
    if (items.isEmpty) {
      // Nothing learned/due yet — go learn instead (feature honesty).
      Navigator.of(context).push(LessonsScreen.route());
      return;
    }
    Navigator.of(
      context,
    ).push(QuizScreen.routeItems(items: items, title: AppStrings.dailySession));
  }

  void _startWriting(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final pool = List<Kana>.of(StudySet.reviewPool(store))..shuffle();
    Navigator.of(context).push(
      WritingScreen.route(pool.take(12).toList(), AppStrings.writingTitle),
    );
  }

  void _startReading(BuildContext context, List<Word> readable) {
    // [readable] is already gated to the learner's unlocked kana by the caller.
    final picked = (List<Word>.of(readable)..shuffle()).take(10).toList();
    Navigator.of(
      context,
    ).push(ReadingScreen.route(picked, AppStrings.readingTitle));
  }

  void _startSentence(BuildContext context, List<Phrase> readable) {
    final picked = (List<Phrase>.of(readable)..shuffle()).take(8).toList();
    Navigator.of(
      context,
    ).push(ReadingScreen.route(picked, AppStrings.sentenceTitle));
  }

  void _startKanji(BuildContext context) {
    final repo = context.read<KanjiReadingRepository>();
    final prompts = KanjiSession.compose(
      entries: repo.allKanji,
      stats: repo.stats,
      now: DateTime.now(),
      rng: Random(),
    );
    Navigator.of(
      context,
    ).push(KanjiQuizScreen.route(prompts, AppStrings.kanjiTitle));
  }

  void _startConfusable(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final questions = Confusable.session(
      allKana: store.gojuonForScript(KanaScript.hiragana),
      length: 12,
      engine: const QuizEngine(),
      rng: Random(),
    );
    Navigator.of(context).push(
      QuizScreen.route(
        questions: questions,
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.accentSoft,
          foregroundColor: AppColors.accent,
          child: Icon(icon),
        ),
        title: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: onTap,
      ),
    );
  }
}
