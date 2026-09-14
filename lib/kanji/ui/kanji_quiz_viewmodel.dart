// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_reading_question.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_reading_quiz.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/kanji_mode.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns one 漢字の声 session: the cursor, whether each unit is TAUGHT or
/// RECALLed, the recall question and its verdict, the running count, and
/// every progress or analytics write. The screen speaks, renders each beat,
/// and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - The route is captured once on entering a unit: a never-met unit is
///   taught, a met one recalled. A teach beat flips `isSeen`, so the route
///   is never re-derived from the live stat mid-beat. Each unit appears at
///   most once per session, so teach-before-test holds by construction.
/// - TEACH 次へ records an honest ENCODE (untimed correct → seen) and a
///   `teach` attempt; it is not a graded test and never counts in the score.
/// - RECALL is graded but untimed (the kanji track has no clock). A wrong
///   reading is a miss on the scheduled unit. A legal alternate (毎年 →
///   ねん while the stem asked とし) is not a miss, but it is not retrieval
///   of the scheduled reading either: the harvested sibling is credited
///   only when that reading is already seen; otherwise the answer is
///   accepted without moving anyone's Leitner, and logged unscored.
///
/// Playback is not interpreted here: the view speaks a teach beat on
/// arrival and the [confirmedReading] after a choice. Pure of timers and
/// navigation.
class KanjiQuizViewModel extends ChangeNotifier {
  KanjiQuizViewModel({
    required this.units,
    required this.kanji,
    required this.persistence,
    required this.analytics,
    this.sessionId = '',
    DateTime Function()? clock,
    Random? rng,
    List<KanjiUnit>? corpus,
    this.quiz = const KanjiReadingQuiz(),
  }) : _clock = clock ?? DateTime.now,
       _rng = rng ?? Random(),
       _corpus = corpus ?? kKanjiUnits {
    _route();
  }

  final List<KanjiUnit> units;

  /// Owner of the per-reading Leitner this session encodes and grades into.
  final KanjiReadingRepository kanji;

  /// App-scoped owner of every write's future; answering never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  /// Builds the recall question (the option set) for a met unit.
  final KanjiReadingQuiz quiz;

  final DateTime Function() _clock;
  final Random _rng;

  /// Every harvested unit — where a legal alternate reading's sibling lives.
  final List<KanjiUnit> _corpus;

  int _index = 0;
  bool _isTeach = true;
  Set<String> _validReadings = const {};
  KanjiReadingQuestion? _question;
  int? _picked;
  String? _confirmedReading;
  int _graded = 0;
  int _correct = 0;
  bool _finished = false;

  int get index => _index;
  int get total => units.length;
  KanjiUnit get current => units[_index];
  bool get isLastItem => _index + 1 >= total;

  /// Whether the current unit is met for the first time (taught, not tested).
  bool get isTeach => _isTeach;

  /// The recall question, `null` on a teach beat.
  KanjiReadingQuestion? get question => _question;

  /// The chosen option on a recall beat, `null` until committed.
  int? get picked => _picked;
  bool get isAnswered => _picked != null;

  /// The reading to sound after a choice: the chosen one when it was legal,
  /// otherwise the scheduled reading. `null` until answered.
  String? get confirmedReading => _confirmedReading;

  /// Recall beats answered, and answered with a legal reading.
  int get gradedCount => _graded;
  int get correctCount => _correct;
  bool get isFinished => _finished;

  /// Whether option [i] is a legal reading of the marked run in its sentence.
  bool acceptsOption(int i) => _validReadings.contains(_question!.options[i]);

  /// TEACH 次へ: the honest encode, then the next unit or the close.
  void teachNext() {
    if (_finished || !_isTeach) return;
    final now = _clock();
    persistence.trackKanji(
      kanji.recordAnswer(current.id, correct: true, at: now),
    );
    _logAttempt(correct: true, beat: 'teach', now: now);
    _advance();
  }

  /// RECALL pick: graded but untimed. Ignored once answered or on a teach.
  void answer(int i) {
    if (_finished || _isTeach || _picked != null) return;
    final now = _clock();
    final chosen = _question!.options[i];
    final target = current;
    final legal = _validReadings.contains(chosen);

    final KanjiUnit eventUnit;
    final String? scoreId;
    final bool scoreCorrect;
    String? scheduledId;

    if (!legal) {
      eventUnit = target;
      scoreId = target.id;
      scoreCorrect = false;
    } else if (chosen == target.reading) {
      eventUnit = target;
      scoreId = target.id;
      scoreCorrect = true;
    } else {
      final sibling = KanjiPrompt.creditedUnit(target, chosen, corpus: _corpus);
      scheduledId = target.id;
      eventUnit =
          sibling ??
          KanjiUnit(
            written: target.written,
            reading: chosen,
            example: target.example,
          );
      final canCredit = sibling != null && kanji.statForUnit(sibling.id).isSeen;
      scoreId = canCredit ? sibling.id : null;
      scoreCorrect = true;
    }

    if (scoreId != null) {
      persistence.trackKanji(
        kanji.recordAnswer(scoreId, correct: scoreCorrect, at: now),
      );
    }
    _logAttempt(
      item: eventUnit,
      correct: legal,
      beat: 'recall',
      now: now,
      chosen: chosen,
      scheduledId: scheduledId,
      scored: scoreId != null,
    );
    _graded++;
    if (legal) _correct++;
    _picked = i;
    _confirmedReading = legal ? chosen : target.reading;
    notifyListeners();
  }

  /// Leaves an answered recall: the next unit or the close.
  void advance() {
    if (_finished || _isTeach || _picked == null) return;
    _advance();
  }

  void _advance() {
    if (isLastItem) {
      _finished = true;
    } else {
      _index++;
      _route();
    }
    notifyListeners();
  }

  void _route() {
    final p = current;
    _isTeach = !kanji.statForUnit(p.id).isSeen;
    _picked = null;
    _confirmedReading = null;
    _validReadings = KanjiPrompt.validReadings(p);
    _question = _isTeach
        ? null
        : quiz.buildQuestion(p, units, kanji.allKanji, _rng);
  }

  void _logAttempt({
    required bool correct,
    required String beat,
    required DateTime now,
    String? chosen,
    KanjiUnit? item,
    String? scheduledId,
    bool scored = true,
  }) {
    final p = item ?? current;
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: p.id,
        itemType: ItemType.kanji,
        mode: KanjiMode.kanjiReading.name,
        correct: correct,
        sessionId: sessionId,
        meta: {
          'written': p.written,
          'reading': p.reading,
          // Separates honest encodes from graded recalls in the stream, so a
          // teach exposure is never read as a passed test.
          'beat': beat,
          'chosen': ?chosen,
          if (scheduledId != null && scheduledId != p.id)
            'scheduled': scheduledId,
          if (!scored) 'scored': false,
        },
      ),
    );
  }
}
