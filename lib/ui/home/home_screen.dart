// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/ferry_session.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/listening_session.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_screen.dart';
import 'package:kotonoha/kanji/ui/kanji_sentence_screen.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:kotonoha/ui/core/widgets/pull_note.dart';
import 'package:kotonoha/ui/dictation/dictation_screen.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/learn/learn_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/progress/progress_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_screen.dart';
import 'package:kotonoha/ui/shift/shift_focus_screen.dart';
import 'package:kotonoha/ui/travel/travel_focus_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_screen.dart';
import 'package:kotonoha/ui/writing/writing_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({this.clock, super.key});

  /// Injectable clock so 凪「もう一回」 can be exercised in daytime in tests.
  final DateTime Function()? clock;

  bool _learningBlocked(BuildContext context) =>
      context.read<ProgressRestoreRecoveryController>().needsRecovery;

  void _guardLearning(BuildContext context, VoidCallback action) {
    if (_learningBlocked(context)) return;
    action();
  }

  void _openLessons(BuildContext context) {
    if (_learningBlocked(context)) return;
    Navigator.of(context).push(LessonsScreen.route());
  }

  void _openLearnGrid(BuildContext context) {
    if (_learningBlocked(context)) return;
    Navigator.of(context).push(LearnScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read): the dictation entry and the guidance line move
    // with 詞と句 progress — e.g. finishing a first ferry session must reveal
    // 文字起こし when the learner lands back here.
    final wordProgress = context.watch<WordProgressRepository>();
    final kanjiProgress = context.watch<KanjiReadingRepository>();
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
            final learnedKana = StudySet.learned(store);
            final learnedChars = learnedKana.map((k) => k.character).toSet();
            final confusableScope = Confusable.scope(learnedKana);
            final confusableReady = Confusable.isReady(
              confusableScope.pool,
              confusableScope.sets,
            );
            final readableWords = ReadingSet.readable(kWords, learnedChars);
            final readablePhrases = ReadingSet.readable(kPhrases, learnedChars);
            // Mixed-script sentences gate on their NON-kanji kana only — the
            // kanji come with furigana (see ReadingItem.gatingText).
            final readableKanjiPhrases = ReadingSet.readable(
              kKanjiPhrases,
              learnedChars,
            );
            final now = (clock ?? DateTime.now)();
            final travelRepo = _watchTravel(context);
            final travelPlan = travelRepo?.plan ?? TravelFocusPlan.empty;
            final travelViews = {
              for (final focus in travelPlan.focuses)
                focus.scene: TravelScene.inspect(
                  scene: focus.scene,
                  learnedChars: learnedChars,
                  stats: wordProgress.stats,
                  now: now,
                ),
            };
            // learnedUnitCount > 0 is not enough: a lone ん is learned but
            // cannot make an MCQ. A strong-fast singleton can still open
            // Daily as kanaRecall — match what compose will actually build.
            final dailyReady = DailySession.isReady(
              learnedKana,
              stats: store.stats,
              now: now,
            );
            final step = Guidance.nextStep(
              store,
              now: now,
              words: TrackDue.fromItems(readableWords, wordProgress.stats, now),
              sentences: TrackDue.fromItems(
                readablePhrases,
                wordProgress.stats,
                now,
              ),
              kanjiSentences: TrackDue.fromItems(
                readableKanjiPhrases,
                wordProgress.stats,
                now,
              ),
              kanji: _kanjiTrackDue(kanjiProgress, now),
              travelPlan: travelPlan,
              travelViews: travelViews,
            );
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
                        AppStrings.appTitle,
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
                    readablePhrases: readablePhrases,
                    readableKanjiPhrases: readableKanjiPhrases,
                    travelActive: travelPlan.isActive,
                  ),
                const SizedBox(height: 20),
                ..._buildHeroes(context, step, travelPlan, dailyReady),
                // The home is grouped into a quiet 目次 — 假名 → 詞と句 → 漢字 →
                // 回望. Each header appears only when its section has a card, so
                // an empty section shows no label (feature honesty). The 今日の稽古
                // / 手解き hero buttons above stay the single primary action,
                // governed by the next-step line — not folded under a header.
                ..._section(AppStrings.sectionKana, [
                  // 目利き — the look-alike drill the daily session can't replace.
                  if (store.learnedUnitCount > 0 && confusableReady)
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
                    onTap: () => _openLearnGrid(context),
                  ),
                ]),
                ..._section(AppStrings.sectionWords, [
                  if (readableWords.isNotEmpty)
                    _NavCard(
                      icon: Icons.sailing_rounded,
                      label: AppStrings.meetWordsAction,
                      productName: AppStrings.ferryEntry,
                      subtitle: AppStrings.ferrySubtitle,
                      onTap: () => _startFerry(context),
                    ),
                  // 文字起こし tests cold what the ferry introduced — it opens
                  // only once something has actually been met (feature honesty).
                  if (readableWords.any(
                    (w) => wordProgress.statForItem(w.progressId).isSeen,
                  ))
                    _NavCard(
                      icon: Icons.keyboard_rounded,
                      label: AppStrings.dictationAction,
                      productName: AppStrings.dictationEntry,
                      subtitle: AppStrings.dictationSubtitle,
                      onTap: () => _startDictation(context),
                    ),
                  // 聞き取り reviews already-met T01 station items only.
                  if (ListeningSession.hasReadyItems(
                    learnedChars: learnedChars,
                    stats: wordProgress.stats,
                  ))
                    _NavCard(
                      icon: Icons.hearing_rounded,
                      label: AppStrings.listenFirstAction,
                      productName: AppStrings.listeningEntry,
                      subtitle: AppStrings.listeningSubtitle,
                      onTap: () => _startListening(context),
                    ),
                  if (readablePhrases.isNotEmpty)
                    _NavCard(
                      icon: Icons.subject_rounded,
                      label: AppStrings.readPhrasesAction,
                      productName: AppStrings.sentenceEntry,
                      subtitle: AppStrings.sentenceSubtitle,
                      onTap: () => _startSentence(context, readablePhrases),
                    ),
                  // #48 owns this room. Isolated from travel-scene selection.
                  _NavCard(
                    icon: Icons.swap_horiz_rounded,
                    label: AppStrings.shiftAction,
                    productName: AppStrings.shiftEntry,
                    subtitle: AppStrings.shiftSubtitle,
                    onTap: () => _guardLearning(
                      context,
                      () => Navigator.of(context)
                          .push(ShiftFocusScreen.route(clock: clock)),
                    ),
                  ),
                  // Isolated travel-purpose picker. Does not change 渡し舟 /
                  // 黙読 / 聞き取り / 換句 contracts.
                  _NavCard(
                    icon: Icons.place_outlined,
                    label: AppStrings.travelSceneAction,
                    productName: AppStrings.travelSceneEntry,
                    subtitle: AppStrings.travelSceneSubtitle,
                    onTap: () => _guardLearning(
                      context,
                      () => Navigator.of(context)
                          .push(TravelSceneScreen.route()),
                    ),
                  ),
                  _NavCard(
                    icon: Icons.flag_outlined,
                    label: travelPlan.isActive
                        ? AppStrings.travelFocusEditAction
                        : AppStrings.travelFocusAction,
                    productName: AppStrings.travelFocusEntry,
                    subtitle: AppStrings.travelFocusSubtitle,
                    onTap: () => _guardLearning(
                      context,
                      () => Navigator.of(context)
                          .push(TravelFocusScreen.route(clock: clock)),
                    ),
                  ),
                  // Isolated from #47 scene membership and #9 聞き取り self-grade.
                  _NavCard(
                    icon: Icons.record_voice_over_outlined,
                    label: AppStrings.replyAction,
                    productName: AppStrings.replyEntry,
                    subtitle: AppStrings.replySubtitle,
                    onTap: () => _guardLearning(
                      context,
                      () => Navigator.of(context)
                          .push(ReplyHubScreen.route(clock: clock)),
                    ),
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
                      label: AppStrings.readKanjiSentencesAction,
                      productName: AppStrings.kanjiSentenceEntry,
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

  ({List<SessionItem> kana, List<ReadingItem> transfer}) _composeDaily(
    BuildContext context, {
    bool quiet = false,
    Set<String> excludeProgressIds = const {},
  }) {
    final store = context.read<KanaProgressRepository>();
    final wordProgress = context.read<WordProgressRepository>();
    final now = DateTime.now();
    final kana = DailySession.compose(
      pool: StudySet.reviewPool(store),
      stats: store.stats,
      // 今日の稽古 REVIEWS only kana the learner has already met — it never
      // introduces new ones (so it can never cold-test you). New kana are
      // learned in 手解き; the next-step line points there when it's time.
      newCandidates: const <Kana>[],
      now: now,
      rng: Random(),
      quiet: quiet,
    );
    final learnedChars = StudySet.learned(store)
        .map((k) => k.character)
        .toSet();
    final transfer = DailyBridge.compose(
      sessionKana: [for (final i in kana) i.question.target],
      words: kWords,
      phrases: kPhrases,
      learnedChars: learnedChars,
      wordStats: wordProgress.stats,
      kanaStats: store.stats,
      now: now,
      rng: Random(),
      excludeProgressIds: excludeProgressIds,
    );
    return (kana: kana, transfer: transfer);
  }

  void _startDaily(
    BuildContext context, {
    bool quiet = false,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_learningBlocked(context)) return;
    final practice = _composeDaily(
      context,
      quiet: quiet,
      excludeProgressIds: excludeProgressIds,
    );
    if (practice.kana.isEmpty) {
      // Nothing that can discriminate or recall — go learn instead.
      _openLessons(context);
      return;
    }
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: practice.transfer,
    );
    Navigator.of(context).push(
      QuizScreen.routeItems(
        items: practice.kana,
        title: AppStrings.dailySession,
        transferItems: practice.transfer,
        quiet: quiet,
        alreadyTransferredIds: excludeProgressIds,
        onAgain: () =>
            _againDaily(context, quiet: quiet, excludeProgressIds: nextExclude),
        onFinished: _travelBoostOnFinish(context),
      ),
    );
  }

  /// "再来一回" for 今日の稽古: a fresh session in place of the result screen. If
  /// the pool has drained mid-grind, return home rather than an empty quiz.
  /// [quiet] carries the silent-run choice across rounds. [excludeProgressIds]
  /// is the accumulated transfer history for this grind so later rounds cover
  /// remaining eligible items first.
  void _againDaily(
    BuildContext context, {
    bool quiet = false,
    Set<String> excludeProgressIds = const {},
  }) {
    final practice = _composeDaily(
      context,
      quiet: quiet,
      excludeProgressIds: excludeProgressIds,
    );
    if (practice.kana.isEmpty) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: practice.transfer,
    );
    Navigator.of(context).pushReplacement(
      QuizScreen.routeItems(
        items: practice.kana,
        title: AppStrings.dailySession,
        transferItems: practice.transfer,
        quiet: quiet,
        alreadyTransferredIds: excludeProgressIds,
        onAgain: () =>
            _againDaily(context, quiet: quiet, excludeProgressIds: nextExclude),
        onFinished: _travelBoostOnFinish(context),
      ),
    );
  }

  void _startFerry(BuildContext context, {bool replace = false}) {
    if (_learningBlocked(context)) return;
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(store)
        .map((k) => k.character)
        .toSet();
    final words = FerrySession.compose(
      words: kWords,
      learnedChars: learnedChars,
      rng: Random(),
      now: DateTime.now(),
      stats: context.read<WordProgressRepository>().stats,
    );
    final nav = Navigator.of(context);
    final route = FerryScreen.route(
      words,
      AppStrings.ferryTitle,
      // Re-composes fresh; the close itself (SessionSummary, render-time band)
      // suppresses it at night — so a session that crossed dusk still hides it.
      onMore: () => _startFerry(context, replace: true),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startDictation(
    BuildContext context, {
    bool replace = false,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_learningBlocked(context)) return;
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(store)
        .map((k) => k.character)
        .toSet();
    // Dictation never introduces (maxNew: 0): a word is met ear-first in the
    // ferry before it can be tested cold here.
    final words = ReadingSet.session(
      items: kWords,
      learnedChars: learnedChars,
      rng: Random(),
      now: (clock ?? DateTime.now)(),
      stats: context.read<WordProgressRepository>().stats,
      maxNew: 0,
    );
    if (words.isEmpty) return; // nothing met yet — the entry is hidden anyway
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: words,
    );
    final nav = Navigator.of(context);
    final route = DictationScreen.route(
      words,
      AppStrings.dictationTitle,
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startDictation(
        context,
        replace: true,
        excludeProgressIds: nextExclude,
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startListening(
    BuildContext context, {
    bool replace = false,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_learningBlocked(context)) return;
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(store)
        .map((k) => k.character)
        .toSet();
    final items = ListeningSession.compose(
      learnedChars: learnedChars,
      rng: Random(),
      now: (clock ?? DateTime.now)(),
      stats: context.read<WordProgressRepository>().stats,
    );
    if (items.isEmpty) return;
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: items,
    );
    final nav = Navigator.of(context);
    final route = ListeningScreen.route(
      items,
      AppStrings.listeningTitle,
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startListening(
        context,
        replace: true,
        excludeProgressIds: nextExclude,
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startWriting(BuildContext context) {
    if (_learningBlocked(context)) return;
    final store = context.read<KanaProgressRepository>();
    final pool = List<Kana>.of(StudySet.reviewPool(store))..shuffle();
    Navigator.of(context).push(
      WritingScreen.route(pool.take(12).toList(), AppStrings.writingTitle),
    );
  }

  /// [maxNew] lets the ambient line say what the day is FOR: a revision day
  /// passes 0, so a room that both introduces and reviews does not quietly
  /// introduce anyway (which would put intake beyond the guidance weights).
  /// Tapping the room from the home has no such instruction and introduces.
  void _startSentence(
    BuildContext context,
    List<Phrase> readable, {
    bool replace = false,
    int maxNew = 3,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_learningBlocked(context)) return;
    final store = context.read<KanaProgressRepository>();
    final learnedChars = StudySet.learned(store)
        .map((k) => k.character)
        .toSet();
    final now = (clock ?? DateTime.now)();
    final picked = ReadingSet.session(
      items: readable,
      learnedChars: learnedChars,
      rng: Random(),
      now: now,
      stats: context.read<WordProgressRepository>().stats,
      season: Season.forMonth(now.month),
      maxNew: maxNew,
    );
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: picked,
    );
    final nav = Navigator.of(context);
    final route = ReadingScreen.route(
      picked,
      AppStrings.sentenceTitle,
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startSentence(
        context,
        readable,
        replace: true,
        maxNew: maxNew,
        excludeProgressIds: nextExclude,
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startKanji(
    BuildContext context, {
    int maxNew = KanjiSession.kDefaultMaxNew,
  }) {
    if (_learningBlocked(context)) return;
    final repo = context.read<KanjiReadingRepository>();
    final units = KanjiSession.compose(
      units: kKanjiUnits,
      stats: repo.stats,
      now: DateTime.now(),
      rng: Random(),
      maxNew: maxNew,
    );
    if (units.isEmpty) return;
    Navigator.of(context)
        .push(KanjiQuizScreen.route(units, AppStrings.kanjiTitle));
  }

  void _startKanjiSentence(
    BuildContext context,
    List<KanjiPhrase> readable, {
    bool replace = false,
    int maxNew = 3,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_learningBlocked(context)) return;
    final now = (clock ?? DateTime.now)();
    final picked = ReadingSet.session(
      items: readable,
      learnedChars: StudySet.learned(context.read<KanaProgressRepository>())
          .map((k) => k.character)
          .toSet(),
      rng: Random(),
      now: now,
      stats: context.read<WordProgressRepository>().stats,
      maxNew: maxNew,
    );
    if (picked.isEmpty) return;
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: picked,
    );
    final nav = Navigator.of(context);
    final route = KanjiSentenceScreen.route(
      picked,
      AppStrings.kanjiSentenceTitle,
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startKanjiSentence(
        context,
        readable,
        replace: true,
        maxNew: maxNew,
        excludeProgressIds: nextExclude,
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  List<QuizQuestion> _composeConfusable(KanaProgressRepository store) {
    // Pool is learned gojūon only. Katakana groups enter by learned units,
    // never "any katakana glyph has been seen".
    final scoped = Confusable.scope(StudySet.learned(store));
    return Confusable.session(
      allKana: scoped.pool,
      length: 12,
      engine: const QuizEngine(),
      rng: Random(),
      sets: scoped.sets,
    );
  }

  void _startConfusable(BuildContext context) {
    if (_learningBlocked(context)) return;
    final store = context.read<KanaProgressRepository>();
    final questions = _composeConfusable(store);
    if (questions.isEmpty) {
      // Not enough learned look-alikes for a real drill — go learn more.
      _openLessons(context);
      return;
    }
    Navigator.of(context).push(
      QuizScreen.route(
        questions: questions,
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
        onAgain: () => _againConfusable(context),
      ),
    );
  }

  /// "再来一回" for 目利き. If the learned pool can no longer compose a
  /// meaningful drill, return home rather than an empty or padded quiz.
  void _againConfusable(BuildContext context) {
    final store = context.read<KanaProgressRepository>();
    final questions = _composeConfusable(store);
    if (questions.isEmpty) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).pushReplacement(
      QuizScreen.route(
        questions: questions,
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
        onAgain: () => _againConfusable(context),
      ),
    );
  }

  TravelFocusRepository? _watchTravel(BuildContext context) {
    try {
      return context.watch<TravelFocusRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  TravelFocusRepository? _readTravel(BuildContext context) {
    try {
      return context.read<TravelFocusRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  List<Widget> _buildHeroes(
    BuildContext context,
    GuidanceStep step,
    TravelFocusPlan plan,
    bool dailyReady,
  ) {
    final travelPrimary = plan.isActive && _isTravelHero(step);
    if (travelPrimary) {
      return [
        _HeroAction(
          action: _travelHeroAction(step),
          productName: _travelHeroProduct(step),
          onPressed: () => _openTravelHero(context, step),
        ),
        _HeroAction(
          action: AppStrings.travelPrepSkipAction,
          productName: AppStrings.travelFocusEntry,
          kind: _HeroKind.text,
          onPressed: () => _skipTravelStep(context, step),
        ),
        if (dailyReady) ...[
          _HeroAction(
            action: AppStrings.quietPracticeAction,
            productName: AppStrings.dailyQuiet,
            kind: _HeroKind.text,
            onPressed: () => _startDaily(context, quiet: true),
          ),
          const SizedBox(height: 12),
          _HeroAction(
            action: AppStrings.reviewKanaAction,
            productName: AppStrings.dailySession,
            kind: _HeroKind.outlined,
            onPressed: () => _startDaily(context),
          ),
          const SizedBox(height: 12),
        ],
        if (!dailyReady) const SizedBox(height: 12),
        _HeroAction(
          action: AppStrings.learnNewKanaAction,
          productName: AppStrings.continueLearning,
          kind: _HeroKind.outlined,
          onPressed: () => _openLessons(context),
        ),
      ];
    }
    if (dailyReady) {
      return [
        _HeroAction(
          action: AppStrings.reviewKanaAction,
          productName: AppStrings.dailySession,
          onPressed: () => _startDaily(context),
        ),
        // A quiet aside under the same button — two doors to the same
        // 稽古. 静かに composes a silent run (no listening prompts) for
        // practising without sound. Per-tap, never a saved mode; it
        // hugs its text (like 知道了) so it reads as a subordinate
        // aside, not a second full-width primary action.
        _HeroAction(
          action: AppStrings.quietPracticeAction,
          productName: AppStrings.dailyQuiet,
          kind: _HeroKind.text,
          onPressed: () => _startDaily(context, quiet: true),
        ),
        const SizedBox(height: 12),
        _HeroAction(
          action: AppStrings.learnNewKanaAction,
          productName: AppStrings.continueLearning,
          kind: _HeroKind.outlined,
          onPressed: () => _openLessons(context),
        ),
      ];
    }
    return [
      _HeroAction(
        action: AppStrings.learnNewKanaAction,
        productName: AppStrings.continueLearning,
        onPressed: () => _openLessons(context),
      ),
    ];
  }

  bool _isTravelHero(GuidanceStep step) {
    return switch (step.target) {
      GuidanceTarget.daily ||
      GuidanceTarget.travelMeet ||
      GuidanceTarget.travelRecall ||
      GuidanceTarget.travelListen ||
      GuidanceTarget.travelLearnKana => true,
      _ => false,
    };
  }

  String _travelHeroAction(GuidanceStep step) {
    return switch (step.target) {
      GuidanceTarget.daily => AppStrings.travelPrepBoostAction,
      GuidanceTarget.travelMeet => AppStrings.travelPrepMeetAction,
      GuidanceTarget.travelRecall => AppStrings.travelPrepRecallAction,
      GuidanceTarget.travelListen => AppStrings.travelPrepListenAction,
      GuidanceTarget.travelLearnKana => AppStrings.travelPrepLearnAction,
      _ => AppStrings.travelFocusEntry,
    };
  }

  String _travelHeroProduct(GuidanceStep step) {
    return switch (step.target) {
      GuidanceTarget.daily => AppStrings.dailySession,
      GuidanceTarget.travelMeet => AppStrings.travelSceneMeetTitle(
        _sceneLabel(step.scene),
      ),
      GuidanceTarget.travelRecall => AppStrings.travelSceneRecallTitle(
        _sceneLabel(step.scene),
      ),
      GuidanceTarget.travelListen => AppStrings.travelSceneListenTitle(
        _sceneLabel(step.scene),
      ),
      GuidanceTarget.travelLearnKana => AppStrings.continueLearning,
      _ => AppStrings.travelFocusEntry,
    };
  }

  void _openTravelHero(BuildContext context, GuidanceStep step) {
    if (_learningBlocked(context)) return;
    switch (step.target) {
      case GuidanceTarget.daily:
        _startDaily(context);
      case GuidanceTarget.travelMeet:
        _startTravelMeet(context, step);
      case GuidanceTarget.travelRecall:
        _startTravelRecall(context, step);
      case GuidanceTarget.travelListen:
        _startTravelListen(context, step);
      case GuidanceTarget.travelLearnKana:
        if (step.scene == null) {
          _openLessons(context);
          return;
        }
        Navigator.of(context)
            .push(TravelSceneHub.route(step.scene!, clock: clock));
      default:
        break;
    }
  }

  void _startTravelMeet(BuildContext context, GuidanceStep step) {
    if (_learningBlocked(context)) return;
    final scene = step.scene;
    if (scene == null) return;
    TravelSceneHub.startMeet(
      context,
      scene: scene,
      clock: clock,
      onFinished: () => _markTravelServed(context, scene),
    );
  }

  void _startTravelRecall(BuildContext context, GuidanceStep step) {
    if (_learningBlocked(context)) return;
    final scene = step.scene;
    if (scene == null) return;
    TravelSceneHub.startRecall(
      context,
      scene: scene,
      clock: clock,
      onFinished: () => _markTravelServed(context, scene),
    );
  }

  void _startTravelListen(BuildContext context, GuidanceStep step) {
    if (_learningBlocked(context)) return;
    final scene = step.scene;
    if (scene == null) return;
    TravelSceneHub.startListen(
      context,
      scene: scene,
      clock: clock,
      onFinished: () => _markTravelServed(context, scene),
    );
  }

  VoidCallback? _travelBoostOnFinish(BuildContext context) {
    final travel = _readTravel(context);
    if (travel == null || !travel.plan.isActive) return null;
    return () {
      if (!context.mounted) return;
      _markTravelBoost(context);
    };
  }

  void _skipTravelStep(BuildContext context, GuidanceStep step) {
    switch (step.target) {
      case GuidanceTarget.daily:
        _markTravelBoost(context);
      case GuidanceTarget.travelMeet:
      case GuidanceTarget.travelRecall:
      case GuidanceTarget.travelListen:
      case GuidanceTarget.travelLearnKana:
        if (step.scene != null) _markTravelServed(context, step.scene!);
      default:
        break;
    }
  }

  void _markTravelBoost(BuildContext context) {
    final travel = _readTravel(context);
    if (travel == null || !travel.plan.isActive) return;
    context.read<ProgressPersistenceController>().trackTravelFocus(
      travel.markKanaBoost((clock ?? DateTime.now)()),
    );
  }

  void _markTravelServed(BuildContext context, TravelSceneId scene) {
    final travel = _readTravel(context);
    if (travel == null || !travel.plan.isActive) return;
    context.read<ProgressPersistenceController>().trackTravelFocus(
      travel.markServed(scene, (clock ?? DateTime.now)()),
    );
  }

  String _sceneLabel(TravelSceneId? scene) {
    return switch (scene) {
      TravelSceneId.transport => AppStrings.travelSceneTransport,
      TravelSceneId.clothing => AppStrings.travelSceneClothing,
      TravelSceneId.shrine => AppStrings.travelSceneShrine,
      TravelSceneId.parkQueue => AppStrings.travelSceneParkQueue,
      TravelSceneId.restaurant => AppStrings.travelSceneRestaurant,
      TravelSceneId.convenience => AppStrings.travelSceneConvenience,
      TravelSceneId.hotel => AppStrings.travelSceneHotel,
      null => AppStrings.travelFocusEntry,
    };
  }

  TrackDue _kanjiTrackDue(KanjiReadingRepository repo, DateTime now) {
    final dueIds = repo.dueUnitIds(now);
    final oldest = dueIds.isEmpty ? null : repo.statForUnit(dueIds.first).dueAt;
    final totalUnits = kKanjiUnits.length;
    DateTime? lastMet;
    for (final s in repo.stats.values) {
      final seenAt = s.lastReviewedAt;
      if (seenAt != null && (lastMet == null || seenAt.isAfter(lastMet))) {
        lastMet = seenAt;
      }
    }
    return TrackDue(
      dueCount: dueIds.length,
      oldestDue: oldest,
      unmet: totalUnits - repo.seenUnitCount,
      lastMet: lastMet,
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
    required List<Phrase> readablePhrases,
    required List<KanjiPhrase> readableKanjiPhrases,
    required bool travelActive,
  }) {
    final text = switch (step.target) {
      GuidanceTarget.lessons =>
        coldStart
            ? AppStrings.guidanceStartLessons
            : AppStrings.guidanceLearnMore,
      GuidanceTarget.daily =>
        travelActive
            ? AppStrings.guidanceTravelBoost(step.dueCount)
            : AppStrings.guidanceReview(step.dueCount),
      GuidanceTarget.dictation => AppStrings.guidanceWordsReview(step.dueCount),
      GuidanceTarget.sentences =>
        step.dueCount > 0
            ? AppStrings.guidanceSentencesReview(step.dueCount)
            : AppStrings.guidanceMeetSentences,
      GuidanceTarget.kanjiSentences =>
        step.dueCount > 0
            ? AppStrings.guidanceKanjiSentencesReview(step.dueCount)
            : AppStrings.guidanceMeetKanjiSentences,
      GuidanceTarget.kanji =>
        step.dueCount > 0
            ? AppStrings.guidanceKanjiReview(step.dueCount)
            : AppStrings.guidanceMeetKanji,
      GuidanceTarget.ferry => AppStrings.guidanceMeetWords,
      GuidanceTarget.rest => AppStrings.guidanceCaughtUp,
      GuidanceTarget.travelMeet => AppStrings.guidanceTravelMeet(
        _sceneLabel(step.scene),
      ),
      GuidanceTarget.travelRecall => AppStrings.guidanceTravelRecall(
        _sceneLabel(step.scene),
        step.dueCount,
      ),
      GuidanceTarget.travelListen => AppStrings.guidanceTravelListen(
        _sceneLabel(step.scene),
      ),
      GuidanceTarget.travelLearnKana => AppStrings.guidanceTravelLearnKana(
        _sceneLabel(step.scene),
        step.missingUnits.take(8).join(' '),
      ),
      GuidanceTarget.travelHold => AppStrings.guidanceTravelHold,
    };
    final line = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
    );
    if (step.target == GuidanceTarget.rest ||
        step.target == GuidanceTarget.travelHold) {
      return Center(child: line);
    }
    final onTap = switch (step.target) {
      GuidanceTarget.daily => () => _startDaily(context),
      GuidanceTarget.ferry => () => _startFerry(context),
      GuidanceTarget.dictation => () => _startDictation(context),
      GuidanceTarget.sentences => () => _startSentence(
        context,
        readablePhrases,
        maxNew: step.isMeet ? 3 : 0,
      ),
      GuidanceTarget.kanjiSentences => () => _startKanjiSentence(
        context,
        readableKanjiPhrases,
        maxNew: step.isMeet ? 3 : 0,
      ),
      GuidanceTarget.kanji => () => _startKanji(
        context,
        maxNew: step.isMeet ? KanjiSession.kDefaultMaxNew : 0,
      ),
      GuidanceTarget.travelMeet => () => _startTravelMeet(context, step),
      GuidanceTarget.travelRecall => () => _startTravelRecall(context, step),
      GuidanceTarget.travelListen => () => _startTravelListen(context, step),
      GuidanceTarget.travelLearnKana => () {
        if (step.scene == null) {
          _openLessons(context);
          return;
        }
        Navigator.of(context)
            .push(TravelSceneHub.route(step.scene!, clock: clock));
      },
      GuidanceTarget.lessons ||
      GuidanceTarget.rest ||
      GuidanceTarget.travelHold => () => _openLessons(context),
    };
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _guardLearning(context, onTap),
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
          onPressed: () => context
              .read<ProgressPersistenceController>()
              .trackKana(store.markUnlockSeen(pending.id)),
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
    if (_learningBlocked(context)) return;
    context.read<ProgressPersistenceController>().trackKana(
      store.markUnlockSeen(pending.id),
    );
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

/// Primary home CTA: Chinese action on the first line, Japanese room name
/// beneath. Official Material buttons — no custom ink/focus of our own.
enum _HeroKind { filled, outlined, text }

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.action,
    required this.productName,
    required this.onPressed,
    this.kind = _HeroKind.filled,
  });

  final String action;
  final String productName;
  final VoidCallback onPressed;
  final _HeroKind kind;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(action, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(
          productName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: switch (kind) {
              _HeroKind.filled => Colors.white.withValues(alpha: 0.82),
              _HeroKind.outlined || _HeroKind.text => AppColors.inkMuted,
            },
          ),
        ),
      ],
    );
    return switch (kind) {
      _HeroKind.filled => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(double.infinity, 56),
          maximumSize: Size.infinite,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: label,
      ),
      _HeroKind.outlined => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          maximumSize: Size.infinite,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: AppColors.hairline),
          foregroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: label,
      ),
      _HeroKind.text => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
        child: label,
      ),
    };
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.productName,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String? productName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // ListTile's three-line height clips when the system text scale grows, so
    // the card sizes to its copy instead. InkWell + CircleAvatar keep the
    // Material focus / ripple / 48px icon target.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.accentSoft,
                  foregroundColor: AppColors.accent,
                  child: Icon(icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (productName != null)
                        Text(
                          productName!,
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
