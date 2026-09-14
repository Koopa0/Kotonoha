// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/models/word.dart';
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
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';

/// Everything the home shows at one instant, derived from the four progress
/// owners and the clock. Immutable, and it exposes no collection — a door is
/// open or it is not, and the session behind it is composed on demand by
/// [HomeViewModel], so no reader can reshape what the owners hold.
@immutable
class HomeState {
  const HomeState({
    required this.gojuonSeen,
    required this.gojuonTotal,
    required this.isColdStart,
    required this.hasLearnedUnit,
    required this.confusableReady,
    required this.wordsReadable,
    required this.phrasesReadable,
    required this.kanjiPhrasesReadable,
    required this.dictationReady,
    required this.listeningReady,
    required this.dailyReady,
    required this.travelActive,
    required this.step,
    required this.pendingUnlock,
  });

  /// The 92 base gojūon met so far, and the whole set. The 116 dakuten and
  /// yōon stay out of the ring so they cannot dilute the core achievement.
  final int gojuonSeen;
  final int gojuonTotal;

  /// Nothing has ever been met — the one cold-start hand at the door.
  final bool isColdStart;

  /// At least one row has been learned, which every kana drill gates on.
  final bool hasLearnedUnit;

  /// Enough learned look-alikes for 目利き to compose a real drill.
  final bool confusableReady;

  /// Whether each reading track has anything the learner can actually read.
  final bool wordsReadable;
  final bool phrasesReadable;
  final bool kanjiPhrasesReadable;

  /// 文字起こし tests cold what 渡し舟 introduced, so it opens only once a
  /// readable word has actually been met.
  final bool dictationReady;

  /// 聞き取り reviews met station items only.
  final bool listeningReady;

  /// 今日の稽古 can compose something that discriminates or recalls. A lone
  /// learned ん is not enough; a strong-fast singleton still opens it.
  final bool dailyReady;

  /// A travel plan is running, which changes the hero and the next-step line.
  final bool travelActive;

  /// The ambient one-line hand on the shoulder.
  final GuidanceStep step;

  /// A track that just opened and has not been acknowledged, which borrows
  /// the next-step slot until the learner taps in or says 「知道了」.
  final Unlock? pendingUnlock;

  /// How far the base gojūon has been walked, 0..1.
  double get gojuonCoverage => gojuonTotal == 0 ? 0 : gojuonSeen / gojuonTotal;
}

/// Owns the home: which doors are open, the ambient next step, the pending
/// unlock line, and how every session behind a door is composed from the
/// learned kana and the 詞と句 / 漢字 schedules. It also owns the two cursor
/// writes the home makes — acknowledging an unlock and moving the travel
/// plan's daily cursor. The screen renders the 目次 and does the routing.
///
/// Every owner is injected at construction, including the travel plan: the
/// home must not quietly become a different product when a provider happens
/// to be missing.
///
/// [state] is derived fresh on every read, against the clock at that moment,
/// so a day boundary or a new due item shows up as soon as the home rebuilds.
/// The View reads it once per build. Pure of widgets and navigation.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required this.kana,
    required this.words,
    required this.kanji,
    required this.travel,
    required this.persistence,
    required this.recovery,
    DateTime Function()? clock,
    Random? rng,
  }) : _clock = clock ?? DateTime.now,
       _rng = rng ?? Random() {
    kana.addListener(notifyListeners);
    words.addListener(notifyListeners);
    kanji.addListener(notifyListeners);
    travel.addListener(notifyListeners);
  }

  /// Owner of every kana's state, the learned rows and the seen unlocks.
  final KanaProgressRepository kana;

  /// Owner of the 詞と句 schedule.
  final WordProgressRepository words;

  /// Owner of the 漢字 reading schedule.
  final KanjiReadingRepository kanji;

  /// Owner of the travel plan and its daily cursor.
  final TravelFocusRepository travel;

  /// Tracks the durable writes the home starts, and retries them.
  final ProgressPersistenceController persistence;

  /// Says whether durable state is still unconfirmed, which holds learning.
  final ProgressRestoreRecoveryController recovery;

  final DateTime Function() _clock;
  final Random _rng;

  /// Durable state could not be confirmed, so no learning may start and no
  /// evidence may be written until recovery succeeds.
  bool get learningBlocked => recovery.needsRecovery;

  /// A travel plan is running. The cheap live read, for deciding whether a
  /// session that is about to start should report back to the plan at all.
  bool get travelActive => travel.plan.isActive;

  Set<String> get _learnedChars =>
      StudySet.learned(kana).map((k) => k.character).toSet();

  /// The home as it stands right now. Derived, never stored.
  HomeState get state {
    final now = _clock();
    final learnedKana = StudySet.learned(kana);
    final learnedChars = learnedKana.map((k) => k.character).toSet();
    final confusableScope = Confusable.scope(learnedKana);
    final readableWords = ReadingSet.readable(kWords, learnedChars);
    final readablePhrases = ReadingSet.readable(kPhrases, learnedChars);
    // Mixed-script sentences gate on their NON-kanji kana only — the kanji
    // come with furigana (see ReadingItem.gatingText).
    final readableKanjiPhrases = ReadingSet.readable(
      kKanjiPhrases,
      learnedChars,
    );
    final gojuon = kana.gojuonKana;
    final plan = travel.plan;
    final step = Guidance.nextStep(
      kana,
      now: now,
      words: TrackDue.fromItems(readableWords, words.stats, now),
      sentences: TrackDue.fromItems(readablePhrases, words.stats, now),
      kanjiSentences: TrackDue.fromItems(
        readableKanjiPhrases,
        words.stats,
        now,
      ),
      kanji: _kanjiTrackDue(now),
      travelPlan: plan,
      travelViews: {
        for (final focus in plan.focuses)
          focus.scene: TravelScene.inspect(
            scene: focus.scene,
            learnedChars: learnedChars,
            stats: words.stats,
            now: now,
          ),
      },
    );
    return HomeState(
      gojuonSeen: kana.seenInSet(gojuon),
      gojuonTotal: gojuon.length,
      isColdStart: kana.seenCount == 0,
      hasLearnedUnit: kana.learnedUnitCount > 0,
      confusableReady: Confusable.isReady(
        confusableScope.pool,
        confusableScope.sets,
      ),
      wordsReadable: readableWords.isNotEmpty,
      phrasesReadable: readablePhrases.isNotEmpty,
      kanjiPhrasesReadable: readableKanjiPhrases.isNotEmpty,
      dictationReady: readableWords.any(
        (w) => words.statForItem(w.progressId).isSeen,
      ),
      listeningReady: ListeningSession.hasReadyItems(
        learnedChars: learnedChars,
        stats: words.stats,
      ),
      // learnedUnitCount > 0 is not enough: a lone ん is learned but cannot
      // make an MCQ. Match what compose will actually build.
      dailyReady: DailySession.isReady(
        learnedKana,
        stats: kana.stats,
        now: now,
      ),
      travelActive: plan.isActive,
      step: step,
      pendingUnlock: Unlocks.pending(
        wordsReadable: readableWords.isNotEmpty,
        phrasesReadable: readablePhrases.isNotEmpty,
        kanjiPhrasesReadable: readableKanjiPhrases.isNotEmpty,
        seenUnlocks: kana.seenUnlocks,
      ),
    );
  }

  /// The 漢字 track summarised the way Guidance weighs every other track:
  /// what is due, how long it has been neglected, and what is still unmet.
  TrackDue _kanjiTrackDue(DateTime now) {
    final dueIds = kanji.dueUnitIds(now);
    DateTime? lastMet;
    for (final s in kanji.stats.values) {
      final seenAt = s.lastReviewedAt;
      if (seenAt != null && (lastMet == null || seenAt.isAfter(lastMet))) {
        lastMet = seenAt;
      }
    }
    return TrackDue(
      dueCount: dueIds.length,
      oldestDue: dueIds.isEmpty ? null : kanji.statForUnit(dueIds.first).dueAt,
      unmet: kKanjiUnits.length - kanji.seenUnitCount,
      lastMet: lastMet,
    );
  }

  /// 今日の稽古: the kana to review and the 詞と句 items that ride along.
  ///
  /// It REVIEWS only kana already met, so it can never cold-test the learner;
  /// new kana are learned in 手解き. [quiet] composes a silent run.
  /// [excludeProgressIds] is the accumulated 「もう一回」 history of this grind,
  /// so later rounds cover the remaining eligible items first.
  ({List<SessionItem> kana, List<ReadingItem> transfer}) composeDaily({
    bool quiet = false,
    Set<String> excludeProgressIds = const {},
  }) {
    final now = _clock();
    final session = DailySession.compose(
      pool: StudySet.reviewPool(kana),
      stats: kana.stats,
      newCandidates: const <Kana>[],
      now: now,
      rng: _rng,
      quiet: quiet,
    );
    final transfer = DailyBridge.compose(
      sessionKana: [for (final i in session) i.question.target],
      words: kWords,
      phrases: kPhrases,
      learnedChars: _learnedChars,
      wordStats: words.stats,
      kanaStats: kana.stats,
      now: now,
      rng: _rng,
      excludeProgressIds: excludeProgressIds,
    );
    return (kana: session, transfer: transfer);
  }

  /// The 「もう一回」 history after showing [transfer].
  Set<String> nextExclude({
    required Set<String> previous,
    required Iterable<ReadingItem> transfer,
  }) => DailyBridge.nextExclude(previous: previous, transfer: transfer);

  /// 渡し舟 — the ear-first meeting room for words.
  List<Word> composeFerry() => FerrySession.compose(
    words: kWords,
    learnedChars: _learnedChars,
    rng: _rng,
    now: _clock(),
    stats: words.stats,
  );

  /// 文字起こし — never introduces (maxNew: 0): a word is met ear-first in
  /// the ferry before it can be tested cold here.
  List<Word> composeDictation() => ReadingSet.session(
    items: kWords,
    learnedChars: _learnedChars,
    rng: _rng,
    now: _clock(),
    stats: words.stats,
    maxNew: 0,
  );

  /// 聞き取り — reviews of already-met station items only.
  List<ReadingItem> composeListening() => ListeningSession.compose(
    learnedChars: _learnedChars,
    rng: _rng,
    now: _clock(),
    stats: words.stats,
  );

  /// 黙読 — the readable phrases for one sitting.
  ///
  /// [maxNew] lets the ambient line say what the day is FOR: a revision day
  /// passes 0, so a room that both introduces and reviews does not quietly
  /// introduce anyway. Tapping the room from the home has no such
  /// instruction and introduces.
  List<Phrase> composeSentence({int maxNew = 3}) {
    final now = _clock();
    return ReadingSet.session(
      items: ReadingSet.readable(kPhrases, _learnedChars),
      learnedChars: _learnedChars,
      rng: _rng,
      now: now,
      stats: words.stats,
      season: Season.forMonth(now.month),
      maxNew: maxNew,
    );
  }

  /// 漢字 — the reading units for one sitting.
  List<KanjiUnit> composeKanji({int maxNew = KanjiSession.kDefaultMaxNew}) =>
      KanjiSession.compose(
        units: kKanjiUnits,
        stats: kanji.stats,
        now: _clock(),
        rng: _rng,
        maxNew: maxNew,
      );

  /// 交じり文 — the readable mixed-script sentences for one sitting.
  List<KanjiPhrase> composeKanjiSentence({int maxNew = 3}) =>
      ReadingSet.session(
        items: ReadingSet.readable(kKanjiPhrases, _learnedChars),
        learnedChars: _learnedChars,
        rng: _rng,
        now: _clock(),
        stats: words.stats,
        maxNew: maxNew,
      );

  /// 手習い — a shuffled dozen from the review pool, so a brand-new learner
  /// is never asked to write kana they have not met.
  List<Kana> composeWriting() => (List<Kana>.of(
    StudySet.reviewPool(kana),
  )..shuffle(_rng)).take(12).toList();

  /// 目利き — the look-alike drill. The pool is learned gojūon only; katakana
  /// groups enter by learned units, never "any katakana glyph has been seen".
  List<QuizQuestion> composeConfusable() {
    final scoped = Confusable.scope(StudySet.learned(kana));
    return Confusable.session(
      allKana: scoped.pool,
      length: 12,
      engine: const QuizEngine(),
      rng: _rng,
      sets: scoped.sets,
    );
  }

  /// Acknowledges an unlock line. A deliberate gesture, never a build
  /// side-effect, so marking-seen settles instead of looping the home.
  void markUnlockSeen(Unlock unlock) =>
      persistence.trackKana(kana.markUnlockSeen(unlock.id));

  /// Moves the travel plan's kana cursor after a 今日の稽古 that served it.
  void markTravelBoost() {
    if (!travel.plan.isActive) return;
    persistence.trackTravelFocus(travel.markKanaBoost(_clock()));
  }

  /// Moves the travel plan's cursor for [scene] after its step was served.
  void markTravelServed(TravelSceneId scene) {
    if (!travel.plan.isActive) return;
    persistence.trackTravelFocus(travel.markServed(scene, _clock()));
  }

  @override
  void dispose() {
    kana.removeListener(notifyListeners);
    words.removeListener(notifyListeners);
    kanji.removeListener(notifyListeners);
    travel.removeListener(notifyListeners);
    super.dispose();
  }
}
