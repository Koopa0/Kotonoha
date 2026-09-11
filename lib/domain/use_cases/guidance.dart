// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_prep.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';

/// Where the ambient "next step" line takes the learner when tapped.
enum GuidanceTarget {
  lessons,
  daily,

  /// Meet new words ear-first (渡し舟).
  ferry,

  /// Review due words cold (文字起こし).
  dictation,

  /// Read kana sentences — due ones first (黙読).
  sentences,

  /// Read mixed-script sentences, the grammar-pattern spine (名残の仮名).
  kanjiSentences,

  /// Kanji readings — due reviews or new teach beats (漢字の声).
  kanji,
  rest,

  /// Travel-prep: meet unread readable items in the retained scene.
  travelMeet,

  /// Travel-prep: recall already-seen (usually due) items in the scene.
  travelRecall,

  /// Travel-prep: listen to already-seen items in the scene.
  travelListen,

  /// Travel-prep: the retained scene is still unreadable — learn those kana.
  travelLearnKana,

  /// Travel-prep: today's short Home steps are done. Not a completion.
  travelHold,
}

/// A track's standing in the schedule, as plain data — the caller (the View,
/// which holds the repositories) summarises each track into one of these so
/// this use_case never has to import the kanji module or walk stat maps.
class TrackDue {
  const TrackDue({
    this.dueCount = 0,
    this.oldestDue,
    this.unmet = 0,
    this.lastMet,
  });

  static const TrackDue none = TrackDue();

  /// Items due for review now.
  final int dueCount;

  /// The earliest due instant among them (null when [dueCount] is 0).
  final DateTime? oldestDue;

  /// Readable items never met yet.
  final int unmet;

  /// When this track was last touched at all — the most recent review instant
  /// across its met items, or null if nothing in it has ever been met. It is
  /// how long a track has gone NEGLECTED, which is what decides who gets the
  /// next introduction (never a count, never shown).
  final DateTime? lastMet;

  /// Summarises one reading track from the items the learner can actually read
  /// and the stats its sessions schedule by. Lives here, not in the View, so
  /// the guidance rules and the thing that feeds them are tested together.
  static TrackDue fromItems(
    List<ReadingItem> readable,
    Map<String, WordStat> stats,
    DateTime now,
  ) {
    var dueCount = 0;
    var unmet = 0;
    DateTime? oldestDue;
    DateTime? lastMet;
    for (final item in readable) {
      final s = stats[item.progressId] ?? const WordStat();
      if (!s.isSeen) {
        unmet++;
        continue;
      }
      final seenAt = s.lastReviewedAt;
      if (seenAt != null && (lastMet == null || seenAt.isAfter(lastMet))) {
        lastMet = seenAt;
      }
      final d = s.dueAt;
      if (d != null && !d.isAfter(now)) {
        dueCount++;
        if (oldestDue == null || d.isBefore(oldestDue)) oldestDue = d;
      }
    }
    return TrackDue(
      dueCount: dueCount,
      oldestDue: oldestDue,
      unmet: unmet,
      lastMet: lastMet,
    );
  }
}

/// One calm "do this next" decision, derived from learning state.
///
/// A pure value object: it carries only the navigation [target] and — for the
/// review states — the [dueCount] the View needs to fill in its sentence. The
/// 繁中 copy itself lives in `AppStrings` (the UI layer), so this stays
/// Flutter-free.
class GuidanceStep {
  const GuidanceStep(
    this.target, {
    this.dueCount = 0,
    this.scene,
    this.missingUnits = const [],
  }) : isMeet = false;

  /// A step that sends the learner to MEET new material rather than revise.
  const GuidanceStep.meet(
    this.target, {
    this.scene,
    this.missingUnits = const [],
  }) : dueCount = 0,
       isMeet = true;

  final GuidanceTarget target;

  /// Whether this step is an introduction. Some rooms both introduce and
  /// review (黙読, 名残の仮名), so the target alone cannot say which the day is
  /// for — and a review day that quietly also introduced would put the intake
  /// beyond the reach of the weights in [kMeetWeightMixedSentences] & co.
  final bool isMeet;

  /// Items due for review; only meaningful for the review targets ([daily] /
  /// [dictation] / [sentences] / [kanji]-review / [travelRecall] — 0 otherwise).
  final int dueCount;

  /// Retained travel scene for the travel-prep targets; null otherwise.
  final TravelSceneId? scene;

  /// Kana still gating the retained scene. Only for [travelLearnKana].
  final List<String> missingUnits;

  @override
  bool operator ==(Object other) =>
      other is GuidanceStep &&
      other.target == target &&
      other.dueCount == dueCount &&
      other.isMeet == isMeet &&
      other.scene == scene &&
      _sameUnits(other.missingUnits, missingUnits);

  @override
  int get hashCode => Object.hash(
    target,
    dueCount,
    isMeet,
    scene,
    Object.hashAll(missingUnits),
  );

  static bool _sameUnits(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Reads learning state and answers one question: what should the learner do
/// next? One quiet step at a time — never a map or a checklist. Pure logic,
/// deterministic under an injected [now].
abstract final class Guidance {
  /// How much of the learner's NEW material each track should get — a
  /// statement about where the bottleneck is right now, not a permanent truth.
  ///
  /// For a 漢字-literate adult whose kana are fluent, the gap is reading real
  /// written Japanese: he already owns the meaning of 学校 and cannot yet say
  /// がっこう. So mixed-script sentences dominate, kanji readings feed them,
  /// words support both, and the all-kana sentences are maintenance only —
  /// they train a decoding skill he has finished acquiring.
  ///
  /// These bias RATE, never access: branch E scores a track by neglect × weight
  /// and every score grows without bound, so a low weight slows a track down
  /// but can never silence it. Revisit when the bottleneck moves (when
  /// unfamiliar VOCABULARY, not unfamiliar sound, is what stops a sentence).
  static const double kMeetWeightMixedSentences = 0.55;
  static const double kMeetWeightKanji = 0.25;
  static const double kMeetWeightWords = 0.15;
  static const double kMeetWeightKanaSentences = 0.05;

  /// One session's worth of reviews. At or above it the day is spent revising;
  /// below it there is room for new material. The same intake valve the
  /// session composers apply inside a room, applied one level up — between
  /// rooms — because the words track meets and reviews in two different ones.
  static const int kReviewFirstBacklog = 8;

  /// First-match-wins over three eras:
  ///
  /// **The kana era** (unchanged — the foundation always speaks first):
  /// - **A** nothing learned yet → start the lessons (手解き).
  /// - **B** kana reviews are due → today's session (今日の稽古), with count.
  ///   A retained travel plan spends this once per day, then continues the
  ///   scene — leftover unlearned rows (branch C) must not block readable
  ///   travel words.
  /// - **C** caught up but rows remain → keep learning (手解き).
  ///
  /// **The reading era** (the kana are quiet — route into the corpus). Its
  /// branches all answer the same question, "who has waited longest?", so no
  /// track can be starved by another's bigger pool:
  /// - **D0** a track never opened at all → open it. Once each, ahead of
  ///   reviews: an unopened room is not novelty competing with revision, it is
  ///   a whole part of the app the learner cannot see exists.
  /// - **D** something is due somewhere → the track whose oldest due item has
  ///   waited longest. Words review in 文字起こし, kana sentences in 黙読,
  ///   mixed-script sentences in 名残の仮名, readings in 漢字の声.
  /// - **E** nothing due but unmet material remains → the track NEGLECTED
  ///   longest gets the introduction (oldest [TrackDue.lastMet]; a track never
  ///   touched at all wins outright). A fixed curriculum order here would have
  ///   pointed at 渡し舟 for months — the word pool is the largest, so a
  ///   first-match chain silently hides every other track until it empties.
  ///
  /// - **F** everything met and nothing due → rest; the day is theirs.
  ///
  /// Ties in either branch fall back to declaration order (words → kana
  /// sentences → mixed sentences → kanji), which only matters on a cold start
  /// where every track is equally untouched.
  ///
  /// "Due" for kana is the learned set filtered by
  /// [DailySession.canComposeItem] — the same gate compose uses — so a due ん
  /// with no same-script foil cannot pin Guidance on 今日の稽古 while the
  /// session only serves an undued ワ. Each reading track's standing arrives
  /// as a [TrackDue] summary computed by the caller from the same
  /// repositories its sessions draw on.
  static GuidanceStep nextStep(
    KanaProgressRepository store, {
    required DateTime now,
    TrackDue words = TrackDue.none,
    TrackDue sentences = TrackDue.none,
    TrackDue kanjiSentences = TrackDue.none,
    TrackDue kanji = TrackDue.none,
    TravelFocusPlan travelPlan = TravelFocusPlan.empty,
    Map<TravelSceneId, TravelSceneView> travelViews = const {},
  }) {
    // A — a brand-new learner: send them to be taught, before anything is due.
    if (store.learnedUnitCount == 0) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // B — kana reviews take priority, but only for targets compose can
    // actually serve: a discriminating MCQ, or a strong-fast kanaRecall.
    // A due singleton ん next to an undued ワ must not pin this branch
    // (the session would skip ん and never clear the due count).
    final learned = StudySet.learned(store);
    final due = Scheduler.due(learned, store.stats, now: now)
        .where(
          (k) => DailySession.canComposeItem(
            k,
            learned,
            stats: store.stats,
            now: now,
          ),
        )
        .length;
    final travel = _travelStep(
      plan: travelPlan,
      views: travelViews,
      dueKanaCount: due,
      now: now,
    );
    if (travel != null) return travel;
    if (due > 0) {
      return GuidanceStep(GuidanceTarget.daily, dueCount: due);
    }
    // C — caught up, but there is still a row left to learn.
    final hasUnlearned = Lessons.fromKana(store.allKana)
        .any((l) => !store.isUnitLearned(l.id));
    if (hasUnlearned) {
      return const GuidanceStep(GuidanceTarget.lessons);
    }
    // The reading era. Declaration order is the tie-break for every branch.
    // The weights say where the learner's bottleneck is, and they only bias
    // INTRODUCTION (branch E) — reviews stay schedule-driven, and the review
    // volume follows whatever was introduced. See [kMeetWeight].
    final tracks = [
      (
        review: GuidanceTarget.dictation,
        meet: GuidanceTarget.ferry,
        t: words,
        weight: kMeetWeightWords,
      ),
      (
        review: GuidanceTarget.sentences,
        meet: GuidanceTarget.sentences,
        t: sentences,
        weight: kMeetWeightKanaSentences,
      ),
      (
        review: GuidanceTarget.kanjiSentences,
        meet: GuidanceTarget.kanjiSentences,
        t: kanjiSentences,
        weight: kMeetWeightMixedSentences,
      ),
      (
        review: GuidanceTarget.kanji,
        meet: GuidanceTarget.kanji,
        t: kanji,
        weight: kMeetWeightKanji,
      ),
    ];

    // D0 — a track the learner has NEVER opened gets opened first, ahead of
    // any review. Opening a room is a one-off event per track, not recurring
    // novelty, so it cannot crowd reviews out; leaving it behind them can and
    // did — reviews of an already-started track regenerate every day, so a
    // review-first rule alone hid the newest track for ~86 simulated days
    // (see guidance_fairness_simulation_test).
    final unopened = tracks.where((c) => c.t.unmet > 0 && c.t.lastMet == null);
    if (unopened.isNotEmpty) {
      return GuidanceStep.meet(unopened.first.meet);
    }

    final overdue =
        tracks.where((c) => c.t.dueCount > 0 && c.t.oldestDue != null).toList()
          ..sort((a, b) => a.t.oldestDue!.compareTo(b.t.oldestDue!));
    final backlog = tracks.fold<int>(0, (n, c) => n + c.t.dueCount);

    GuidanceStep review() =>
        GuidanceStep(overdue.first.review, dueCount: overdue.first.t.dueCount);

    // D — the review backlog already fills a whole session: revise, longest
    // overdue first. Below that threshold the day has slack, and spending it
    // on new material costs nothing (what stays due is picked up tomorrow).
    if (backlog >= kReviewFirstBacklog) return review();

    // E — there is slack: new material goes to the track that is most starved,
    // where starvation is how long it has been neglected TIMES how much of the
    // learner's attention it should be getting. Weighting only shifts the rate;
    // every track's score still grows without bound, so none can be locked out
    // (guidance_fairness_simulation_test asserts both the reach and the share).
    //
    // This branch has to outrank a small backlog, because for words the meeting
    // beat and the reviewing beat are different rooms (渡し舟 / 文字起こし) — a
    // strict review-first rule pointed at 文字起こし almost every day and the
    // learner met three new words in half a year.
    final unmet = tracks.where((c) => c.t.unmet > 0).toList();
    if (unmet.isNotEmpty) {
      // D0 already claimed every never-opened track, so lastMet is set here.
      double starvation(TrackDue t, double weight) =>
          now.difference(t.lastMet ?? now).inSeconds * weight;
      unmet.sort(
        (a, b) =>
            starvation(b.t, b.weight).compareTo(starvation(a.t, a.weight)),
      );
      return GuidanceStep.meet(unmet.first.meet);
    }

    // Nothing new anywhere, but a few items are still due.
    if (overdue.isNotEmpty) return review();

    // F — everything met, nothing pending: the day is theirs.
    return const GuidanceStep(GuidanceTarget.rest);
  }

  /// Travel-prep overrides the reading era and the leftover-row branch: one
  /// necessary kana boost, then one retained scene. Unselected, this is a
  /// no-op so general mode stays the existing recommendation.
  static GuidanceStep? _travelStep({
    required TravelFocusPlan plan,
    required Map<TravelSceneId, TravelSceneView> views,
    required int dueKanaCount,
    required DateTime now,
  }) {
    if (!plan.isActive) return null;
    if (TravelPrep.needsKanaBoost(
      plan: plan,
      dueKanaCount: dueKanaCount,
      now: now,
    )) {
      return GuidanceStep(GuidanceTarget.daily, dueCount: dueKanaCount);
    }
    final scene = TravelPrep.pickScene(plan, now);
    if (scene == null) {
      return const GuidanceStep(GuidanceTarget.travelHold);
    }
    final view = views[scene];
    if (view == null) {
      return GuidanceStep(GuidanceTarget.travelLearnKana, scene: scene);
    }
    return switch (TravelPrep.kindFor(view)) {
      TravelPrepKind.meet => GuidanceStep.meet(
        GuidanceTarget.travelMeet,
        scene: scene,
      ),
      TravelPrepKind.recall => GuidanceStep(
        GuidanceTarget.travelRecall,
        dueCount: view.dueReadable.length,
        scene: scene,
      ),
      TravelPrepKind.listen => GuidanceStep(
        GuidanceTarget.travelListen,
        scene: scene,
      ),
      TravelPrepKind.learnKana => GuidanceStep(
        GuidanceTarget.travelLearnKana,
        scene: scene,
        missingUnits: view.missingUnits,
      ),
    };
  }
}
