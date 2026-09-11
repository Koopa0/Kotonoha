// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:kotonoha/domain/data/confusable_sets.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';
import 'package:kotonoha/domain/use_cases/weakness.dart';

/// Composes the adaptive "today's session": one mixed-mode run drawn from the
/// learner's own data — due reviews + weak items + a little new — so they don't
/// have to choose a mode. Pure logic, deterministic under injected Random.
abstract final class DailySession {
  static const int kDue = 7;
  static const int kWeak = 4;
  static const int kNew = 3;

  /// [pool] = review pool (learned kana); [newCandidates] = kana of the next
  /// unlearned lesson; distractors lean on each target's look-alike group and
  /// stay within its script. A [quiet] run keeps reviews to visual recall — no
  /// listening prompt is ever generated — for practising without sound.
  static List<SessionItem> compose({
    required List<Kana> pool,
    required Map<String, KanaStat> stats,
    required List<Kana> newCandidates,
    required DateTime now,
    required Random rng,
    int length = 12,
    bool quiet = false,
    QuizEngine engine = const QuizEngine(),
  }) {
    if (pool.isEmpty && newCandidates.isEmpty) return const [];

    // Explicit priority — due / real-weak / new / long-uncovered.
    // [Weakness.isActionable] (not raw score > 0) so a recovered 1/N
    // historical miss cannot lock the weak quota by gojūon order.
    //
    // Due-vs-not-due leftover fill is coverage-ordered, not a hard
    // "never pick not-due while due remains" rule. Remaining due often
    // win that fill because they tend to be older; exclusive-due fill
    // is a product choice left open.
    final due = Scheduler.due(pool, stats, now: now).take(kDue);
    final weak = Weakness.rankByWeakness(pool, stats, now: now)
        .where(
          (k) =>
              Weakness.isActionable(stats[k.id] ?? const KanaStat(), now: now),
        )
        .take(kWeak);
    final neu = newCandidates.take(kNew);

    final seen = <String>{};
    final targets = <Kana>[];
    void addAll(Iterable<Kana> ks) {
      for (final k in ks) {
        if (!canComposeItem(k, pool, stats: stats, now: now)) continue;
        if (seen.add(k.id)) targets.add(k);
      }
    }

    addAll(due);
    addAll(weak);
    addAll(neu);
    addAll(
      _coverageFill(
        pool.where((k) => !seen.contains(k.id)).toList(),
        stats,
        rng,
        length - targets.length,
      ),
    );
    targets.shuffle(rng);

    final newIds = neu.map((k) => k.id).toSet();
    final items = <SessionItem>[];
    for (final t in targets.take(length)) {
      final question = engine.buildQuestion(
        t,
        directionFor(
          t,
          stat: stats[t.id] ?? const KanaStat(),
          isNew: newIds.contains(t.id),
          quiet: quiet,
          now: now,
          rng: rng,
          canDiscriminate: canDiscriminate(t, pool),
        ),
        _distractors(t, pool, engine.optionCount, rng),
        rng,
      );
      // Belt: a lone-option MCQ is not a review. kanaRecall keeps empty
      // options on purpose and is never [QuizQuestion.isForcedCorrect].
      if (question.isForcedCorrect) continue;
      items.add(SessionItem(question: question, mode: PracticeMode.daily));
    }
    return items;
  }

  /// A review item can score recall only when [pool] holds a same-script
  /// peer that is not the target and does not share its romaji.
  static bool canDiscriminate(Kana target, List<Kana> pool) => pool.any(
    (k) =>
        k.id != target.id &&
        k.romaji != target.romaji &&
        k.script == target.script,
  );

  /// Whether [target] can appear as a Daily item in [pool].
  ///
  /// Two different paths: a strong-fast review may be unprompted
  /// [QuizDirection.kanaRecall] even as a singleton; otherwise the item
  /// needs a discriminating MCQ foil. A due ん next to an undued ワ is
  /// not composable as MCQ and must not count as a review.
  static bool canComposeItem(
    Kana target,
    List<Kana> pool, {
    Map<String, KanaStat> stats = const {},
    DateTime? now,
  }) {
    if (now != null &&
        readyForRecall(stats[target.id] ?? const KanaStat(), now: now)) {
      return true;
    }
    return canDiscriminate(target, pool);
  }

  /// True when today's session can actually compose an item from [pool]:
  /// either a discriminating MCQ, or an unprompted [QuizDirection.kanaRecall]
  /// for a strong-fast review. Home and Guidance use the *learned* set —
  /// never the cold-start [StudySet.reviewPool] fallback.
  static bool isReady(
    List<Kana> pool, {
    Map<String, KanaStat> stats = const {},
    DateTime? now,
  }) => pool.any((t) => canComposeItem(t, pool, stats: stats, now: now));

  /// Remaining slots prefer long-uncovered kana (oldest lastReviewedAt;
  /// never-reviewed first). Equal timestamps are shuffled so gojūon order
  /// cannot lock the same four strong items. Recent-correct therefore land
  /// last among the fill, not in the weak quota.
  static List<Kana> _coverageFill(
    List<Kana> candidates,
    Map<String, KanaStat> stats,
    Random rng,
    int want,
  ) {
    if (want <= 0 || candidates.isEmpty) return const [];
    final buckets = <int, List<Kana>>{};
    for (final k in candidates) {
      final t = stats[k.id]?.lastReviewedAt?.millisecondsSinceEpoch ?? -1;
      buckets.putIfAbsent(t, () => []).add(k);
    }
    final keys = buckets.keys.toList()..sort();
    final out = <Kana>[];
    for (final key in keys) {
      final group = buckets[key]!..shuffle(rng);
      for (final k in group) {
        out.add(k);
        if (out.length >= want) return out;
      }
    }
    return out;
  }

  /// Distractors that lean on the target's look-alike group, so a review can't
  /// be passed by elimination — the same desirable-difficulty idea as 目利き
  /// ([Confusable]), now folded into the daily review. The group's members come
  /// first, topped up within the target's own script. [QuizEngine.buildQuestion]
  /// adds the answer, so we supply up to [want] - 1 distractors.
  static List<Kana> _distractors(
    Kana t,
    List<Kana> pool,
    int want,
    Random rng,
  ) {
    // [usable] mirrors buildQuestion's own candidate filter (line ~38) ON
    // PURPOSE — not redundantly. We hand the engine a tightly-capped pool, so a
    // same-romaji kana (ぢ/じ, づ/ず) slipping in would be dropped THERE and
    // leave only 2 distractors → a 3-option question. Pre-screening here keeps
    // every pick valid, so we reliably fill want - 1 and the engine yields 4.
    bool usable(Kana k) =>
        k.id != t.id && k.romaji != t.romaji && k.script == t.script;
    final picks = <Kana>{
      ...Confusable.groupFor(t.character, pool, _confusableSets).where(usable),
    };
    for (final k in List<Kana>.of(pool)..shuffle(rng)) {
      if (picks.length >= want - 1) break;
      if (usable(k)) picks.add(k);
    }
    return picks.toList()..shuffle(rng);
  }

  static const List<List<String>> _confusableSets = [
    ...kConfusableSets,
    ...kKatakanaConfusableSets,
  ];

  /// New items stay form→sound (gentlest). Weak / still-learning reviews keep
  /// multiple-choice recognition. A strong, fast, recovered review leaves the
  /// option list and becomes unprompted [QuizDirection.kanaRecall] only when
  /// listening is recently confirmed — visual fluency must not hide an
  /// unknown or stale sound direction. Historical success past
  /// [KanaStat.kListeningRecheckWindow] is sampled as sound again if
  /// this item is selected; it is not a miss and does not add a sound
  /// quota. [quiet] still forbids listening, not silent recall, and never
  /// restuffs an easy MCQ. A singleton that cannot host a fair sound MCQ
  /// stays [QuizDirection.kanaRecall] rather than a forced-correct listen.
  static QuizDirection directionFor(
    Kana _, {
    required KanaStat stat,
    required bool isNew,
    required bool quiet,
    required DateTime now,
    required Random rng,
    bool canDiscriminate = true,
  }) {
    if (isNew) return QuizDirection.kanaToRomaji;
    final visualReady = readyForRecall(stat, now: now);
    if (quiet) {
      return visualReady
          ? QuizDirection.kanaRecall
          : QuizDirection.romajiToKana;
    }
    if (visualReady) {
      if (stat.needsListeningProbe(now: now) && canDiscriminate) {
        return QuizDirection.soundToKana;
      }
      return QuizDirection.kanaRecall;
    }
    if (stat.listeningUnrecovered) {
      return QuizDirection.soundToKana;
    }
    return rng.nextBool()
        ? QuizDirection.romajiToKana
        : QuizDirection.soundToKana;
  }

  /// Whether this kana has enough *recognition* evidence to leave easy MCQ.
  ///
  /// Display-[KanaStatus.strong] alone is not enough: a recent miss, a slow
  /// average, or an untimed-only climb must keep the option list. Timed-fast
  /// and past the untimed cap are required so "was introduced" cannot pass.
  static bool readyForRecall(KanaStat stat, {required DateTime now}) {
    if (!stat.isSeen) return false;
    if (Weakness.isActionable(stat, now: now)) return false;
    if (stat.status != KanaStatus.strong) return false;
    if (stat.avgLatencyMs <= 0) return false;
    if (stat.avgLatencyMs >= KanaStat.kFastThresholdMs) return false;
    if (stat.srsLevel < KanaStat.kUntimedCapLevel) return false;
    return true;
  }
}
