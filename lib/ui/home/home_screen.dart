// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/domain/use_cases/unlocks.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
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
import 'package:kotonoha/ui/home/home_viewmodel.dart';
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

/// The home — a quiet 目次 over the whole path, and the one place every room
/// is entered from.
///
/// A thin View over [HomeViewModel]: which doors are open, the ambient next
/// step, the unlock line and every session's composition are the ViewModel's;
/// this widget lays them out and does the routing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({this.clock, super.key});

  /// Injectable clock so 凪「もう一回」 can be exercised in daytime in tests.
  final DateTime Function()? clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = HomeViewModel(
      kana: context.read<KanaProgressRepository>(),
      words: context.read<WordProgressRepository>(),
      kanji: context.read<KanjiReadingRepository>(),
      travel: context.read<TravelFocusRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      recovery: context.read<ProgressRestoreRecoveryController>(),
      clock: widget.clock,
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  /// Passed on to the rooms that keep their own clock.
  DateTime Function()? get _clock => widget.clock;

  void _guardLearning(VoidCallback action) {
    if (_vm.learningBlocked) return;
    action();
  }

  void _openLessons() {
    if (_vm.learningBlocked) return;
    Navigator.of(context).push(LessonsScreen.route());
  }

  void _openLearnGrid() {
    if (_vm.learningBlocked) return;
    Navigator.of(context).push(LearnScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No app-bar title — the wordmark below is the sole brand mark, so the
      // name 「言の葉」 never appears twice (and never as bare romaji).
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            final home = _vm.state;
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
                // Ring tracks the 92 base gojūon (five-fifty); the 116 dakuten/
                // yoon don't dilute the core achievement.
                Center(
                  child: ProgressRing(
                    value: home.gojuonCoverage,
                    centerLabel: '${home.gojuonSeen}/${home.gojuonTotal}',
                    caption: AppStrings.practiced,
                    title: AppStrings.practicedGojuonScope,
                  ),
                ),
                const SizedBox(height: 12),
                // A cold-start hand only. Once practice begins, the ring and the
                // next-step line carry the state — no accuracy score at the door.
                if (home.isColdStart)
                  const Center(
                    child: Text(
                      AppStrings.coldStartCaption,
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                const SizedBox(height: 16),
                if (home.pendingUnlock != null)
                  _buildUnlock(home.pendingUnlock!)
                else
                  _buildNextStep(
                    home.step,
                    coldStart: !home.hasLearnedUnit,
                    travelActive: home.travelActive,
                  ),
                const SizedBox(height: 20),
                ..._buildHeroes(home),
                // The home is grouped into a quiet 目次 — 假名 → 詞と句 → 漢字 →
                // 回望. Each header appears only when its section has a card, so
                // an empty section shows no label (feature honesty). The 今日の稽古
                // / 手解き hero buttons above stay the single primary action,
                // governed by the next-step line — not folded under a header.
                ..._section(AppStrings.sectionKana, [
                  // 目利き — the look-alike drill the daily session can't replace.
                  if (home.hasLearnedUnit && home.confusableReady)
                    _NavCard(
                      icon: Icons.compare_arrows_rounded,
                      label: AppStrings.confusableAction,
                      productName: AppStrings.confusableEntry,
                      subtitle: AppStrings.confusableSubtitle,
                      onTap: _startConfusable,
                    ),
                  // 手習い draws the review pool — gated like 目利き so a brand-new
                  // learner is never asked to write kana they haven't met yet.
                  if (home.hasLearnedUnit)
                    _NavCard(
                      icon: Icons.edit_note_rounded,
                      label: AppStrings.writingAction,
                      productName: AppStrings.writingEntry,
                      subtitle: AppStrings.writingSubtitle,
                      onTap: _startWriting,
                    ),
                  _NavCard(
                    icon: Icons.grid_view_rounded,
                    label: AppStrings.learnHiragana,
                    subtitle: AppStrings.learnHiraganaSubtitle,
                    onTap: _openLearnGrid,
                  ),
                ]),
                ..._section(AppStrings.sectionWords, [
                  if (home.wordsReadable)
                    _NavCard(
                      icon: Icons.sailing_rounded,
                      label: AppStrings.meetWordsAction,
                      productName: AppStrings.ferryEntry,
                      subtitle: AppStrings.ferrySubtitle,
                      onTap: _startFerry,
                    ),
                  // 文字起こし tests cold what the ferry introduced — it opens
                  // only once something has actually been met (feature honesty).
                  if (home.dictationReady)
                    _NavCard(
                      icon: Icons.keyboard_rounded,
                      label: AppStrings.dictationAction,
                      productName: AppStrings.dictationEntry,
                      subtitle: AppStrings.dictationSubtitle,
                      onTap: _startDictation,
                    ),
                  // 聞き取り reviews already-met T01 station items only.
                  if (home.listeningReady)
                    _NavCard(
                      icon: Icons.hearing_rounded,
                      label: AppStrings.listenFirstAction,
                      productName: AppStrings.listeningEntry,
                      subtitle: AppStrings.listeningSubtitle,
                      onTap: _startListening,
                    ),
                  if (home.phrasesReadable)
                    _NavCard(
                      icon: Icons.subject_rounded,
                      label: AppStrings.readPhrasesAction,
                      productName: AppStrings.sentenceEntry,
                      subtitle: AppStrings.sentenceSubtitle,
                      onTap: _startSentence,
                    ),
                  // #48 owns this room. Isolated from travel-scene selection.
                  _NavCard(
                    icon: Icons.swap_horiz_rounded,
                    label: AppStrings.shiftAction,
                    productName: AppStrings.shiftEntry,
                    subtitle: AppStrings.shiftSubtitle,
                    onTap: () => _guardLearning(
                      () =>
                          Navigator.of(context)
                              .push(ShiftFocusScreen.route(clock: _clock)),
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
                      () =>
                          Navigator.of(context).push(TravelSceneScreen.route()),
                    ),
                  ),
                  _NavCard(
                    icon: Icons.flag_outlined,
                    label: home.travelActive
                        ? AppStrings.travelFocusEditAction
                        : AppStrings.travelFocusAction,
                    productName: AppStrings.travelFocusEntry,
                    subtitle: AppStrings.travelFocusSubtitle,
                    onTap: () => _guardLearning(
                      () =>
                          Navigator.of(context)
                              .push(TravelFocusScreen.route(clock: _clock)),
                    ),
                  ),
                  // Isolated from #47 scene membership and #9 聞き取り self-grade.
                  _NavCard(
                    icon: Icons.record_voice_over_outlined,
                    label: AppStrings.replyAction,
                    productName: AppStrings.replyEntry,
                    subtitle: AppStrings.replySubtitle,
                    onTap: () => _guardLearning(
                      () =>
                          Navigator.of(context)
                              .push(ReplyHubScreen.route(clock: _clock)),
                    ),
                  ),
                ]),
                ..._section(AppStrings.sectionKanji, [
                  _NavCard(
                    icon: Icons.translate_rounded,
                    label: AppStrings.kanjiEntry,
                    subtitle: AppStrings.kanjiSubtitle,
                    onTap: _startKanji,
                  ),
                  if (home.kanjiPhrasesReadable)
                    _NavCard(
                      icon: Icons.auto_stories_rounded,
                      label: AppStrings.readKanjiSentencesAction,
                      productName: AppStrings.kanjiSentenceEntry,
                      subtitle: AppStrings.kanjiSentenceSubtitle,
                      onTap: _startKanjiSentence,
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

  void _startDaily({
    bool quiet = false,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_vm.learningBlocked) return;
    final practice = _vm.composeDaily(
      quiet: quiet,
      excludeProgressIds: excludeProgressIds,
    );
    if (practice.kana.isEmpty) {
      // Nothing that can discriminate or recall — go learn instead.
      _openLessons();
      return;
    }
    Navigator.of(context)
        .push(_dailyRoute(practice, quiet, excludeProgressIds));
  }

  /// "再来一回" for 今日の稽古: a fresh session in place of the result screen. If
  /// the pool has drained mid-grind, return home rather than an empty quiz.
  /// [quiet] carries the silent-run choice across rounds. [excludeProgressIds]
  /// is the accumulated transfer history for this grind so later rounds cover
  /// remaining eligible items first.
  void _againDaily({
    bool quiet = false,
    Set<String> excludeProgressIds = const {},
  }) {
    final practice = _vm.composeDaily(
      quiet: quiet,
      excludeProgressIds: excludeProgressIds,
    );
    final nav = Navigator.of(context);
    if (practice.kana.isEmpty) {
      nav.popUntil((r) => r.isFirst);
      return;
    }
    nav.pushReplacement(_dailyRoute(practice, quiet, excludeProgressIds));
  }

  Route<void> _dailyRoute(
    ({List<SessionItem> kana, List<ReadingItem> transfer}) practice,
    bool quiet,
    Set<String> excludeProgressIds,
  ) {
    final nextExclude = _vm.nextExclude(
      previous: excludeProgressIds,
      transfer: practice.transfer,
    );
    return QuizScreen.routeItems(
      items: practice.kana,
      title: AppStrings.dailySession,
      transferItems: practice.transfer,
      quiet: quiet,
      alreadyTransferredIds: excludeProgressIds,
      onAgain: () => _againDaily(quiet: quiet, excludeProgressIds: nextExclude),
      onFinished: _travelBoostOnFinish(),
    );
  }

  void _startFerry({bool replace = false}) {
    if (_vm.learningBlocked) return;
    final nav = Navigator.of(context);
    final route = FerryScreen.route(
      _vm.composeFerry(),
      AppStrings.ferryTitle,
      // Re-composes fresh; the close itself (SessionSummary, render-time band)
      // suppresses it at night — so a session that crossed dusk still hides it.
      onMore: () => _startFerry(replace: true),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startDictation({
    bool replace = false,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_vm.learningBlocked) return;
    final words = _vm.composeDictation();
    if (words.isEmpty) return; // nothing met yet — the entry is hidden anyway
    final nextExclude = _vm.nextExclude(
      previous: excludeProgressIds,
      transfer: words,
    );
    final nav = Navigator.of(context);
    final route = DictationScreen.route(
      words,
      AppStrings.dictationTitle,
      clock: _clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () =>
          _startDictation(replace: true, excludeProgressIds: nextExclude),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startListening({
    bool replace = false,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_vm.learningBlocked) return;
    final items = _vm.composeListening();
    if (items.isEmpty) return;
    final nextExclude = _vm.nextExclude(
      previous: excludeProgressIds,
      transfer: items,
    );
    final nav = Navigator.of(context);
    final route = ListeningScreen.route(
      items,
      AppStrings.listeningTitle,
      clock: _clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () =>
          _startListening(replace: true, excludeProgressIds: nextExclude),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startWriting() {
    if (_vm.learningBlocked) return;
    Navigator.of(
      context,
    ).push(WritingScreen.route(_vm.composeWriting(), AppStrings.writingTitle));
  }

  /// [maxNew] lets the ambient line say what the day is FOR: a revision day
  /// passes 0, so a room that both introduces and reviews does not quietly
  /// introduce anyway (which would put intake beyond the guidance weights).
  /// Tapping the room from the home has no such instruction and introduces.
  void _startSentence({
    bool replace = false,
    int maxNew = 3,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_vm.learningBlocked) return;
    final picked = _vm.composeSentence(maxNew: maxNew);
    final nextExclude = _vm.nextExclude(
      previous: excludeProgressIds,
      transfer: picked,
    );
    final nav = Navigator.of(context);
    final route = ReadingScreen.route(
      picked,
      AppStrings.sentenceTitle,
      clock: _clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startSentence(
        replace: true,
        maxNew: maxNew,
        excludeProgressIds: nextExclude,
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startKanji({int maxNew = KanjiSession.kDefaultMaxNew}) {
    if (_vm.learningBlocked) return;
    final units = _vm.composeKanji(maxNew: maxNew);
    if (units.isEmpty) return;
    Navigator.of(context)
        .push(KanjiQuizScreen.route(units, AppStrings.kanjiTitle));
  }

  void _startKanjiSentence({
    bool replace = false,
    int maxNew = 3,
    Set<String> excludeProgressIds = const {},
  }) {
    if (_vm.learningBlocked) return;
    final picked = _vm.composeKanjiSentence(maxNew: maxNew);
    if (picked.isEmpty) return;
    final nextExclude = _vm.nextExclude(
      previous: excludeProgressIds,
      transfer: picked,
    );
    final nav = Navigator.of(context);
    final route = KanjiSentenceScreen.route(
      picked,
      AppStrings.kanjiSentenceTitle,
      clock: _clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startKanjiSentence(
        replace: true,
        maxNew: maxNew,
        excludeProgressIds: nextExclude,
      ),
    );
    unawaited(replace ? nav.pushReplacement(route) : nav.push(route));
  }

  void _startConfusable() {
    if (_vm.learningBlocked) return;
    final questions = _vm.composeConfusable();
    if (questions.isEmpty) {
      // Not enough learned look-alikes for a real drill — go learn more.
      _openLessons();
      return;
    }
    Navigator.of(context).push(
      QuizScreen.route(
        questions: questions,
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
        onAgain: _againConfusable,
      ),
    );
  }

  /// "再来一回" for 目利き. If the learned pool can no longer compose a
  /// meaningful drill, return home rather than an empty or padded quiz.
  void _againConfusable() {
    final questions = _vm.composeConfusable();
    final nav = Navigator.of(context);
    if (questions.isEmpty) {
      nav.popUntil((r) => r.isFirst);
      return;
    }
    nav.pushReplacement(
      QuizScreen.route(
        questions: questions,
        title: AppStrings.quizTitleConfusable,
        mode: PracticeMode.confusable,
        onAgain: _againConfusable,
      ),
    );
  }

  List<Widget> _buildHeroes(HomeState home) {
    final dailyReady = home.dailyReady;
    final step = home.step;
    if (home.travelActive && _isTravelHero(step)) {
      return [
        _HeroAction(
          action: _travelHeroAction(step),
          productName: _travelHeroProduct(step),
          onPressed: () => _openTravelHero(step),
        ),
        _HeroAction(
          action: AppStrings.travelPrepSkipAction,
          productName: AppStrings.travelFocusEntry,
          kind: _HeroKind.text,
          onPressed: () => _skipTravelStep(step),
        ),
        if (dailyReady) ...[
          _HeroAction(
            action: AppStrings.quietPracticeAction,
            productName: AppStrings.dailyQuiet,
            kind: _HeroKind.text,
            onPressed: () => _startDaily(quiet: true),
          ),
          const SizedBox(height: 12),
          _HeroAction(
            action: AppStrings.reviewKanaAction,
            productName: AppStrings.dailySession,
            kind: _HeroKind.outlined,
            onPressed: _startDaily,
          ),
          const SizedBox(height: 12),
        ],
        if (!dailyReady) const SizedBox(height: 12),
        _HeroAction(
          action: AppStrings.learnNewKanaAction,
          productName: AppStrings.continueLearning,
          kind: _HeroKind.outlined,
          onPressed: _openLessons,
        ),
      ];
    }
    if (dailyReady) {
      return [
        _HeroAction(
          action: AppStrings.reviewKanaAction,
          productName: AppStrings.dailySession,
          onPressed: _startDaily,
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
          onPressed: () => _startDaily(quiet: true),
        ),
        const SizedBox(height: 12),
        _HeroAction(
          action: AppStrings.learnNewKanaAction,
          productName: AppStrings.continueLearning,
          kind: _HeroKind.outlined,
          onPressed: _openLessons,
        ),
      ];
    }
    return [
      _HeroAction(
        action: AppStrings.learnNewKanaAction,
        productName: AppStrings.continueLearning,
        onPressed: _openLessons,
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

  void _openTravelHero(GuidanceStep step) {
    if (_vm.learningBlocked) return;
    switch (step.target) {
      case GuidanceTarget.daily:
        _startDaily();
      case GuidanceTarget.travelMeet:
        _startTravelMeet(step);
      case GuidanceTarget.travelRecall:
        _startTravelRecall(step);
      case GuidanceTarget.travelListen:
        _startTravelListen(step);
      case GuidanceTarget.travelLearnKana:
        _openTravelSceneHub(step);
      default:
        break;
    }
  }

  void _openTravelSceneHub(GuidanceStep step) {
    final scene = step.scene;
    if (scene == null) {
      _openLessons();
      return;
    }
    Navigator.of(context).push(TravelSceneHub.route(scene, clock: _clock));
  }

  void _startTravelMeet(GuidanceStep step) {
    if (_vm.learningBlocked) return;
    final scene = step.scene;
    if (scene == null) return;
    TravelSceneHub.startMeet(
      context,
      scene: scene,
      clock: _clock,
      onFinished: () => _vm.markTravelServed(scene),
    );
  }

  void _startTravelRecall(GuidanceStep step) {
    if (_vm.learningBlocked) return;
    final scene = step.scene;
    if (scene == null) return;
    TravelSceneHub.startRecall(
      context,
      scene: scene,
      clock: _clock,
      onFinished: () => _vm.markTravelServed(scene),
    );
  }

  void _startTravelListen(GuidanceStep step) {
    if (_vm.learningBlocked) return;
    final scene = step.scene;
    if (scene == null) return;
    TravelSceneHub.startListen(
      context,
      scene: scene,
      clock: _clock,
      onFinished: () => _vm.markTravelServed(scene),
    );
  }

  /// The plan only hears about a 今日の稽古 that actually served it, and only
  /// while this home is still on screen.
  VoidCallback? _travelBoostOnFinish() {
    if (!_vm.travelActive) return null;
    return () {
      if (!mounted) return;
      _vm.markTravelBoost();
    };
  }

  void _skipTravelStep(GuidanceStep step) {
    switch (step.target) {
      case GuidanceTarget.daily:
        _vm.markTravelBoost();
      case GuidanceTarget.travelMeet:
      case GuidanceTarget.travelRecall:
      case GuidanceTarget.travelListen:
      case GuidanceTarget.travelLearnKana:
        if (step.scene != null) _vm.markTravelServed(step.scene!);
      default:
        break;
    }
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

  /// The ambient one-line "next step" — a hand on the shoulder, not a banner.
  /// It is tappable (routing to its target) in every state except
  /// [GuidanceTarget.rest], which is a calm closing line and stays inert so it
  /// never reads as a dead button.
  Widget _buildNextStep(
    GuidanceStep step, {
    required bool coldStart,
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
      GuidanceTarget.daily => _startDaily,
      GuidanceTarget.ferry => _startFerry,
      GuidanceTarget.dictation => _startDictation,
      GuidanceTarget.sentences => () => _startSentence(
        maxNew: step.isMeet ? 3 : 0,
      ),
      GuidanceTarget.kanjiSentences => () => _startKanjiSentence(
        maxNew: step.isMeet ? 3 : 0,
      ),
      GuidanceTarget.kanji => () => _startKanji(
        maxNew: step.isMeet ? KanjiSession.kDefaultMaxNew : 0,
      ),
      GuidanceTarget.travelMeet => () => _startTravelMeet(step),
      GuidanceTarget.travelRecall => () => _startTravelRecall(step),
      GuidanceTarget.travelListen => () => _startTravelListen(step),
      GuidanceTarget.travelLearnKana => () => _openTravelSceneHub(step),
      GuidanceTarget.lessons ||
      GuidanceTarget.rest ||
      GuidanceTarget.travelHold => _openLessons,
    };
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _guardLearning(onTap),
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
  Widget _buildUnlock(Unlock pending) {
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
          onTap: () => _onUnlockTap(pending),
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
          onPressed: () => _vm.markUnlockSeen(pending),
          style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
          child: const Text(AppStrings.unlockDismiss),
        ),
      ],
    );
  }

  /// Acts on an unlock: marks it seen, then opens the freshly-available track
  /// (the gentler ear-first 渡し舟 for the word pair).
  void _onUnlockTap(Unlock pending) {
    if (_vm.learningBlocked) return;
    _vm.markUnlockSeen(pending);
    switch (pending) {
      case Unlock.words:
        _startFerry();
      case Unlock.phrases:
        _startSentence();
      case Unlock.kanjiPhrases:
        _startKanjiSentence();
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
              _HeroKind.filled => AppColors.onButtonMuted,
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
