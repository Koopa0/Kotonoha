// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/ferry_session.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/kanji/ui/kanji_sentence_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:kotonoha/ui/core/widgets/pull_note.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
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
      // No app-bar title — the wordmark below is the sole brand mark, so the
      // name 「言の葉」 never appears twice (and never as bare romaji).
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
            // Kanji sentences are readable once their NON-kanji kana is known —
            // the kanji themselves come with (fading) furigana.
            final readableKanjiPhrases = kKanjiPhrases
                .where((p) => p.plainKana.every(learnedChars.contains))
                .toList();
            final step = Guidance.nextStep(store, now: DateTime.now());
            // A track that just opened borrows the next-step slot for one quiet
            // line until the learner acknowledges it (taps in, or 「知道了」).
            final pending = Unlocks.pending(
              wordsReadable: readableWords.isNotEmpty,
              phrasesReadable: readablePhrases.isNotEmpty,
              kanjiPhrasesReadable: readableKanjiPhrases.isNotEmpty,
              seenUnlocks: store.seenUnlocks,
            );
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
                          fontSize: 20,
                          letterSpacing: 5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 40,
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.komorebi,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(height: 7),
                      // The romaji only ever appears here — small, beneath the
                      // wordmark, as a quiet romanization. Never alone.
                      const Text(
                        'KOTONOHA',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 4,
                          color: AppColors.inkMuted,
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
                // A cold-start hand only. Once practice begins, the ring and the
                // next-step line carry the state — no accuracy score at the door.
                if (store.seenCount == 0)
                  const Center(
                    child: Text(
                      AppStrings.coldStartCaption,
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                const SizedBox(height: 16),
                if (pending != null)
                  _buildUnlock(
                    context,
                    store,
                    pending,
                    readablePhrases,
                    readableKanjiPhrases,
                  )
                else
                  _buildNextStep(
                    context,
                    step,
                    coldStart: store.learnedUnitCount == 0,
                  ),
                const SizedBox(height: 20),
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
                // The home is grouped into a quiet 目次 — 假名 → 詞と句 → 漢字 →
                // 回望. Each header appears only when its section has a card, so
                // an empty section shows no label (feature honesty). The 今日の稽古
                // / 手解き hero buttons above stay the single primary action,
                // governed by the next-step line — not folded under a header.
                ..._section(AppStrings.sectionKana, [
                  // 目利き — the look-alike drill the daily session can't replace.
                  if (store.learnedUnitCount > 0)
                    _NavCard(
                      icon: Icons.compare_arrows_rounded,
                      label: AppStrings.confusableEntry,
                      subtitle: AppStrings.confusableSubtitle,
                      onTap: () => _startConfusable(context),
                    ),
                  // 手習い draws the review pool — gated like 目利き so a brand-new
                  // learner is never asked to write kana they haven't met yet.
                  if (store.learnedUnitCount > 0)
                    _NavCard(
                      icon: Icons.edit_note_rounded,
                      label: AppStrings.writingEntry,
                      subtitle: AppStrings.writingSubtitle,
                      onTap: () => _startWriting(context),
                    ),
                  _NavCard(
                    icon: Icons.grid_view_rounded,
                    label: AppStrings.learnHiragana,
                    subtitle: AppStrings.learnHiraganaSubtitle,
                    onTap: () =>
                        Navigator.of(context).push(LearnScreen.route()),
                  ),
                ]),
                ..._section(AppStrings.sectionWords, [
                  if (readableWords.isNotEmpty)
                    _NavCard(
                      icon: Icons.sailing_rounded,
                      label: AppStrings.ferryEntry,
                      subtitle: AppStrings.ferrySubtitle,
                      onTap: () => _startFerry(context),
                    ),
                  if (readableWords.isNotEmpty)
                    _NavCard(
                      icon: Icons.keyboard_rounded,
                      label: AppStrings.dictationEntry,
                      subtitle: AppStrings.dictationSubtitle,
                      onTap: () => _startDictation(context),
                    ),
                  if (readablePhrases.isNotEmpty)
                    _NavCard(
                      icon: Icons.subject_rounded,
                      label: AppStrings.sentenceEntry,
                      subtitle: AppStrings.sentenceSubtitle,
                      onTap: () => _startSentence(context, readablePhrases),
                    ),
                ]),
                ..._section(AppStrings.sectionKanji, [
                  _NavCard(
                    icon: Icons.translate_rounded,
                    label: AppStrings.kanjiEntry,
                    subtitle: AppStrings.kanjiSubtitle,
                    onTap: () => _startKanji(context),
                  ),
                  if (readableKanjiPhrases.isNotEmpty)
                    _NavCard(
                      icon: Icons.auto_stories_rounded,
                      label: AppStrings.kanjiSentenceEntry,
                      subtitle: AppStrings.kanjiSentenceSubtitle,
                      onTap: () =>
                          _startKanjiSentence(context, readableKanjiPhrases),
                    ),
                ]),
                ..._section(AppStrings.sectionLookBack, [
                  _NavCard(
                    icon: Icons.insights_outlined,
                    label: AppStrings.progress,
                    subtitle: AppStrings.progressSubtitle,
                    onTap: () =>
                        Navigator.of(context).push(ProgressScreen.route()),
                  ),
                ]),
                // ④ A quiet, always-available "what is this / how do I learn"
                // at the foot of the path — pull, never pushed.
                const SizedBox(height: 28),
                const _AboutKotonoha(),
              ],
            );
          },
        ),
      ),
    );
  }

  List<SessionItem> _composeDaily(KanaProgressRepository store) =>
      DailySession.compose(
        pool: StudySet.reviewPool(store),
        stats: store.stats,
        // 今日の稽古 REVIEWS only kana the learner has already met — it never
        // introduces new ones (so it can never cold-test you). New kana are
        // learned in 手解き; the next-step line points there when it's time.
        newCandidates: const <Kana>[],
        now: DateTime.now(),
        rng: Random(),
      );

  void _startDaily(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final items = _composeDaily(store);
    if (items.isEmpty) {
      // Nothing learned/due yet — go learn instead (feature honesty).
      Navigator.of(context).push(LessonsScreen.route());
      return;
    }
    Navigator.of(context).push(
      QuizScreen.routeItems(
        items: items,
        title: AppStrings.dailySession,
        onAgain: () => _againDaily(context),
      ),
    );
  }

  /// "再来一回" for 今日の稽古: a fresh session in place of the result screen. If
  /// the pool has drained mid-grind, return home rather than an empty quiz.
  void _againDaily(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final items = _composeDaily(store);
    if (items.isEmpty) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).pushReplacement(
      QuizScreen.routeItems(
        items: items,
        title: AppStrings.dailySession,
        onAgain: () => _againDaily(context),
      ),
    );
  }

  /// Most-recent attempt timestamp per item id (displayText), folded from the
  /// analytics stream — the recency the reading composers use to float
  /// least-recently-seen items up. Never a count, never shown.
  Future<Map<String, int>> _lastSeen(BuildContext context) async {
    final attempts = await context.read<AnalyticsLog>().all();
    final m = <String, int>{};
    for (final a in attempts) {
      if (a.ts > (m[a.itemId] ?? 0)) m[a.itemId] = a.ts;
    }
    return m;
  }

  /// Wraps an opt-in "one more" so it's only offered in the DAY band — at night
  /// the close grants permission to stop, so もう一回 is suppressed.
  VoidCallback? _dayOnly(VoidCallback more) =>
      ClosingBand.forHour(DateTime.now().hour) == ClosingBand.day ? more : null;

  Future<void> _startFerry(BuildContext context, {bool replace = false}) async {
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(
      store,
    ).map((k) => k.character).toSet();
    final lastSeen = await _lastSeen(context);
    if (!context.mounted) return;
    final words = FerrySession.compose(
      words: kWords,
      learnedChars: learnedChars,
      rng: Random(),
      lastSeen: lastSeen,
    );
    final nav = Navigator.of(context);
    final route = FerryScreen.route(
      words,
      AppStrings.ferryTitle,
      onMore: _dayOnly(() => unawaited(_startFerry(context, replace: true))),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  Future<void> _startDictation(
    BuildContext context, {
    bool replace = false,
  }) async {
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(
      store,
    ).map((k) => k.character).toSet();
    final lastSeen = await _lastSeen(context);
    if (!context.mounted) return;
    final words = ReadingSet.session(
      items: kWords,
      learnedChars: learnedChars,
      rng: Random(),
      length: 8,
      lastSeen: lastSeen,
    );
    final nav = Navigator.of(context);
    final route = DictationScreen.route(
      words,
      AppStrings.dictationTitle,
      onMore: _dayOnly(
        () => unawaited(_startDictation(context, replace: true)),
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startWriting(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final pool = List<Kana>.of(StudySet.reviewPool(store))..shuffle();
    Navigator.of(context).push(
      WritingScreen.route(pool.take(12).toList(), AppStrings.writingTitle),
    );
  }

  Future<void> _startSentence(
    BuildContext context,
    List<Phrase> readable, {
    bool replace = false,
  }) async {
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(
      store,
    ).map((k) => k.character).toSet();
    final lastSeen = await _lastSeen(context);
    if (!context.mounted) return;
    final picked = ReadingSet.session(
      items: readable,
      learnedChars: learnedChars,
      rng: Random(),
      length: 8,
      season: Season.forMonth(DateTime.now().month),
      lastSeen: lastSeen,
    );
    final nav = Navigator.of(context);
    final route = ReadingScreen.route(
      picked,
      AppStrings.sentenceTitle,
      onMore: _dayOnly(
        () => unawaited(_startSentence(context, readable, replace: true)),
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
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

  void _startKanjiSentence(BuildContext context, List<KanjiPhrase> readable) {
    final picked = List<KanjiPhrase>.of(readable)..shuffle();
    Navigator.of(
      context,
    ).push(KanjiSentenceScreen.route(picked, AppStrings.kanjiSentenceTitle));
  }

  List<QuizQuestion> _composeConfusable(KanaProgressRepository store) {
    // Once the learner has met ANY katakana, 目利き quietly folds in the katakana
    // look-alikes too (each question stays single-script — never a mixed pair, no
    // new card, no toggle). Until then it is hiragana-only.
    final katakanaStarted =
        store.seenInSet(store.gojuonForScript(KanaScript.katakana)) > 0;
    final sets = katakanaStarted
        ? [...kConfusableSets, ...kKatakanaConfusableSets]
        : kConfusableSets;
    final pool = katakanaStarted
        ? store.gojuonKana
        : store.gojuonForScript(KanaScript.hiragana);
    return Confusable.session(
      allKana: pool,
      length: 12,
      engine: const QuizEngine(),
      rng: Random(),
      sets: sets,
    );
  }

  void _startConfusable(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    Navigator.of(context).push(
      QuizScreen.route(
        questions: _composeConfusable(store),
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
        onAgain: () => _againConfusable(context),
      ),
    );
  }

  /// "再来一回" for 目利き: the confusable pool is always composable, so this
  /// simply re-runs a fresh drill in place of the result screen.
  void _againConfusable(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    Navigator.of(context).pushReplacement(
      QuizScreen.route(
        questions: _composeConfusable(store),
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
        onAgain: () => _againConfusable(context),
      ),
    );
  }

  /// The ambient one-line "next step" — a hand on the shoulder, not a banner.
  /// It is tappable (routing to its target) in every state except
  /// [GuidanceTarget.rest], which is a calm closing line and stays inert so it
  /// never reads as a dead button.
  Widget _buildNextStep(
    BuildContext context,
    GuidanceStep step, {
    required bool coldStart,
  }) {
    final text = switch (step.target) {
      GuidanceTarget.lessons =>
        coldStart
            ? AppStrings.guidanceStartLessons
            : AppStrings.guidanceLearnMore,
      GuidanceTarget.daily => AppStrings.guidanceReview(step.dueCount),
      GuidanceTarget.rest => AppStrings.guidanceCaughtUp,
    };
    final line = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
    );
    if (step.target == GuidanceTarget.rest) {
      return Center(child: line);
    }
    final VoidCallback onTap;
    if (step.target == GuidanceTarget.daily) {
      onTap = () => _startDaily(context);
    } else {
      onTap = () => Navigator.of(context).push(LessonsScreen.route());
    }
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: line,
        ),
      ),
    );
  }

  /// The one-time "unlocked" line — the rare warm moment (a single komorebi
  /// thread), in the same quiet voice as the next-step line. Tapping it steps
  /// into the new track and marks it seen; 「知道了」 just clears it. Both are
  /// deliberate gestures (never a build side-effect), so marking-seen settles
  /// instead of looping the home's listener.
  Widget _buildUnlock(
    BuildContext context,
    KanaProgressRepository store,
    Unlock pending,
    List<Phrase> readablePhrases,
    List<KanjiPhrase> readableKanjiPhrases,
  ) {
    final text = switch (pending) {
      Unlock.words => AppStrings.unlockWords,
      Unlock.phrases => AppStrings.unlockPhrases,
      Unlock.kanjiPhrases => AppStrings.unlockKanjiPhrases,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _onUnlockTap(
            context,
            store,
            pending,
            readablePhrases,
            readableKanjiPhrases,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 7),
        // One thread of warm light — the same treatment as the wordmark — to
        // mark that something opened, without colouring the words.
        Container(
          width: 40,
          height: 2,
          decoration: BoxDecoration(
            color: AppColors.komorebi,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        TextButton(
          onPressed: () => store.markUnlockSeen(pending.id),
          style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
          child: const Text(AppStrings.unlockDismiss),
        ),
      ],
    );
  }

  /// Acts on an unlock: marks it seen, then opens the freshly-available track
  /// (the gentler ear-first 渡し舟 for the word pair).
  void _onUnlockTap(
    BuildContext context,
    KanaProgressRepository store,
    Unlock pending,
    List<Phrase> readablePhrases,
    List<KanjiPhrase> readableKanjiPhrases,
  ) {
    store.markUnlockSeen(pending.id);
    switch (pending) {
      case Unlock.words:
        _startFerry(context);
      case Unlock.phrases:
        _startSentence(context, readablePhrases);
      case Unlock.kanjiPhrases:
        _startKanjiSentence(context, readableKanjiPhrases);
    }
  }
}

/// A quiet 目次 header followed by its cards (12-spaced). Returns nothing when
/// the section has no card, so an empty section shows no label.
List<Widget> _section(String label, List<Widget> cards) {
  if (cards.isEmpty) return const [];
  return [
    _SectionHeader(label),
    for (var i = 0; i < cards.length; i++) ...[
      if (i > 0) const SizedBox(height: 12),
      cards[i],
    ],
  ];
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.inkMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// ④ The pull-not-push "これは?" — a permanently re-openable orientation line at
/// the foot of home: how to learn, then the name's meaning (the 仮名序 epigraph).
/// The shared [PullNote] fold; never auto-shown, never modal, no persistence.
class _AboutKotonoha extends StatelessWidget {
  const _AboutKotonoha();

  @override
  Widget build(BuildContext context) {
    return PullNote(
      trigger: AppStrings.aboutTrigger,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            // The practical note — how to learn.
            const Text(
              AppStrings.aboutBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 24),
            // One thread of warm light parts the practical note from the name's
            // meaning — the soul, woven in, not set apart.
            Container(
              width: 40,
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.komorebi,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              AppStrings.nameMeaningHeading,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            // The 仮名序 line — a quiet epigraph (public domain).
            const Text(
              AppStrings.nameMeaningLine,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink, height: 1.7, fontSize: 15),
            ),
            const SizedBox(height: 12),
            const Text(
              AppStrings.nameMeaningGloss,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted, height: 1.6),
            ),
            const SizedBox(height: 10),
            const Text(
              AppStrings.nameMeaningAttribution,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
          ],
        ),
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
