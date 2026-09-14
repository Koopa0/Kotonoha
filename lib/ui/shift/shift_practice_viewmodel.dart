// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// The steps one 換句 sitting walks through per beat.
enum ShiftPhase {
  /// New forms are taught before the first read.
  intro,

  /// Read the sentence; commit unprompted or ask for the reading.
  readCommit,

  /// The reading is shown; self-grade the read.
  readGrade,

  /// Action drills: restore the dictionary form (choose).
  verbAsk,

  /// The verb choice is revealed.
  verbReveal,

  /// Action drills: name who / what.
  rolesAsk,

  /// The roles are revealed.
  rolesReveal,

  /// Commit to the sense unprompted or ask for a hint.
  senseCommit,

  /// The meaning is shown; self-grade the sense.
  senseGrade,
}

/// Owns one 換句 practice sitting: the beats and the phase within each, the
/// reservation and sightings, every check's evidence and its analytics
/// write, the durable-write state and its retry, and the history shown at
/// the close. The screen speaks, renders each phase, keeps the free-text
/// pad, and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - Every attempt is written to the analytics log and tracked by the
///   app-scoped persistence owner. A failed durable write keeps the row in
///   memory; [isUnsaved] stays honest and [retryPersist] flushes it.
/// - A hold lane writes its reservation first; each beat's first sitting
///   writes one practice sighting.
/// - Hints never leak another check: a verb hint prompts only the verb, a
///   roles hint or revealed roles answer prompts the sense too, and the read
///   support at the sense grade is independent only after an unprompted,
///   correct read.
/// - Free text is never auto-graded; the sense is self-graded.
/// - Word / phrase SRS is never touched.
///
/// Pure of timers, widgets and navigation.
class ShiftPracticeViewModel extends ChangeNotifier {
  ShiftPracticeViewModel({
    required this.drill,
    required this.analytics,
    required this.persistence,
    this.sessionId = '',
    this.sourceUrl,
    this.lane = ShiftLane.sameDay,
    List<ShiftBeat>? beats,
    this.firstUnseen = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       beats = List<ShiftBeat>.unmodifiable(
         beats ?? const [ShiftBeat.base, ShiftBeat.shift],
       ) {
    _beat = this.beats.first;
    _phase = intro.isEmpty ? ShiftPhase.readCommit : ShiftPhase.intro;
  }

  final ShiftDrill drill;
  final AnalyticsLog analytics;

  /// App-scoped owner of every write's future; a failure survives this
  /// sitting.
  final ProgressPersistenceController persistence;
  final String sessionId;
  final String? sourceUrl;
  final ShiftLane lane;

  /// Which pair beats this sitting plays.
  final List<ShiftBeat> beats;
  final bool firstUnseen;

  final DateTime Function() _clock;
  final Set<ShiftBeat> _exposed = <ShiftBeat>{};

  late ShiftBeat _beat;
  late ShiftPhase _phase;
  List<ShiftSelfGrade> _history = const [];
  int _introIndex = 0;
  bool _readUnprompted = false;
  bool _readCorrect = false;
  bool _senseUnprompted = false;
  bool _verbPrompted = false;
  bool _rolesPrompted = false;
  bool _rolesRevealedAnswer = false;
  String? _pickedVerb;
  String? _pickedActor;
  String? _pickedItem;
  bool _senseGrading = false;
  bool _finished = false;
  bool _unsaved = false;
  bool _retrying = false;

  ShiftBeat get beat => _beat;
  int get beatIndex => beats.indexOf(_beat);
  ShiftPhase get phase => _phase;
  ShiftSentence get sentence => drill.sentenceAt(_beat);

  /// Speakable form — layout spaces removed.
  String get say => sentence.kana.replaceAll(' ', '');
  bool get isAction => drill.isAction;
  List<ShiftIntroCard> get intro => drill.introduce;
  int get introIndex => _introIndex;

  bool get readUnprompted => _readUnprompted;
  bool get senseUnprompted => _senseUnprompted;
  bool get verbPrompted => _verbPrompted;
  bool get rolesPrompted => _rolesPrompted;
  String? get pickedVerb => _pickedVerb;
  String? get pickedActor => _pickedActor;
  String? get pickedItem => _pickedItem;
  bool get canLockRoles => _pickedActor != null && _pickedItem != null;
  bool get isSenseGrading => _senseGrading;
  bool get isFinished => _finished;

  /// Rows the log still holds only in memory.
  bool get isUnsaved => _unsaved;
  bool get isRetrying => _retrying;

  /// This drill's self-grades, loaded at the close.
  List<ShiftSelfGrade> get history => _history;

  bool isVerbCorrect(String choice) =>
      ShiftSession.gradesVerb(choice, sentence);

  /// Opens the sitting: the hold reservation, then the first beat's
  /// practice sighting.
  Future<void> start() async {
    await _reserveIfNeeded();
    await _markPracticeSight();
    _syncUnsaved();
  }

  void advanceIntro() {
    if (_finished || _phase != ShiftPhase.intro) return;
    if (_introIndex + 1 < intro.length) {
      _introIndex += 1;
    } else {
      _phase = ShiftPhase.readCommit;
    }
    notifyListeners();
  }

  void commitRead({required bool unprompted}) {
    if (_finished || _phase != ShiftPhase.readCommit) return;
    _readUnprompted = unprompted;
    _phase = ShiftPhase.readGrade;
    notifyListeners();
  }

  void gradeRead({required bool correct}) {
    if (_finished || _phase != ShiftPhase.readGrade) return;
    unawaited(
      _write(ShiftCheck.read, prompted: !_readUnprompted, correct: correct),
    );
    _readCorrect = correct;
    _phase = isAction ? ShiftPhase.verbAsk : ShiftPhase.senseCommit;
    notifyListeners();
  }

  void hintVerb() {
    if (_finished || _phase != ShiftPhase.verbAsk || _verbPrompted) return;
    _verbPrompted = true;
    notifyListeners();
  }

  void pickVerb(String choice) {
    if (_finished || _phase != ShiftPhase.verbAsk || _pickedVerb != null) {
      return;
    }
    final correct = isVerbCorrect(choice);
    unawaited(
      _write(ShiftCheck.verb, prompted: _verbPrompted, correct: correct),
    );
    _pickedVerb = choice;
    _phase = ShiftPhase.verbReveal;
    notifyListeners();
  }

  void afterVerb() {
    if (_finished || _phase != ShiftPhase.verbReveal) return;
    _phase = ShiftPhase.rolesAsk;
    notifyListeners();
  }

  void hintRoles() {
    if (_finished || _phase != ShiftPhase.rolesAsk || _rolesPrompted) return;
    _rolesPrompted = true;
    notifyListeners();
  }

  void selectActor(String choice) {
    if (_finished || _phase != ShiftPhase.rolesAsk) return;
    _pickedActor = choice;
    notifyListeners();
  }

  void selectItem(String choice) {
    if (_finished || _phase != ShiftPhase.rolesAsk) return;
    _pickedItem = choice;
    notifyListeners();
  }

  void lockRoles() {
    if (_finished || _phase != ShiftPhase.rolesAsk) return;
    final actor = _pickedActor;
    final item = _pickedItem;
    if (actor == null || item == null) return;
    final correct = ShiftSession.gradesRoles(
      actor: actor,
      item: item,
      sentence: sentence,
    );
    unawaited(
      _write(ShiftCheck.roles, prompted: _rolesPrompted, correct: correct),
    );
    _rolesRevealedAnswer = !correct;
    _phase = ShiftPhase.rolesReveal;
    notifyListeners();
  }

  void afterRoles() {
    if (_finished || _phase != ShiftPhase.rolesReveal) return;
    _phase = ShiftPhase.senseCommit;
    notifyListeners();
  }

  bool get _rolesSenseSupport => _rolesPrompted || _rolesRevealedAnswer;

  void commitSense({required bool unprompted}) {
    if (_finished || _phase != ShiftPhase.senseCommit) return;
    _senseUnprompted = unprompted && !_rolesSenseSupport;
    _phase = ShiftPhase.senseGrade;
    notifyListeners();
  }

  /// Reading support on screen when the sense check is graded — not the
  /// pre-reveal commit alone, and not the roles Chinese gloss.
  String get _readSupportAtSenseGrade => _readUnprompted && _readCorrect
      ? ShiftReadSupport.independent
      : ShiftReadSupport.prompted;

  /// Self-grades the sense, then the next beat or the close. The write is
  /// awaited so a second tap cannot land while the first is in flight.
  Future<void> gradeSense({required bool correct}) async {
    if (_finished || _phase != ShiftPhase.senseGrade || _senseGrading) return;
    _senseGrading = true;
    notifyListeners();
    await _write(
      ShiftCheck.sense,
      prompted: ShiftSession.sensePrompted(
        askedSenseHint: !_senseUnprompted,
        sawRolesGloss: _rolesPrompted,
        sawRolesReveal: _rolesRevealedAnswer,
      ),
      correct: correct,
      readSupport: _readSupportAtSenseGrade,
    );
    final next = beatIndex + 1;
    if (next < beats.length) {
      _senseGrading = false;
      _beat = beats[next];
      _phase = ShiftPhase.readCommit;
      _readUnprompted = false;
      _readCorrect = false;
      _senseUnprompted = false;
      _verbPrompted = false;
      _rolesPrompted = false;
      _rolesRevealedAnswer = false;
      _pickedVerb = null;
      _pickedActor = null;
      _pickedItem = null;
      notifyListeners();
      await _markPracticeSight();
      return;
    }
    _finished = true;
    notifyListeners();
    await _loadHistory();
  }

  /// Retries the durable write of every unsaved row.
  Future<void> retryPersist() async {
    if (_retrying) return;
    _retrying = true;
    notifyListeners();
    await persistence.retry();
    try {
      await analytics.flushPending();
    } on Object {
      // Leave [isUnsaved] honest. Do not invent a persist.
    }
    _retrying = false;
    _syncUnsaved();
  }

  Future<void> _reserveIfNeeded() async {
    if (lane != ShiftLane.hold) return;
    await _record(
      ShiftSession.reservation(
        drill: drill,
        sessionId: sessionId,
        at: _clock(),
        sourceUrl: sourceUrl,
      ),
    );
  }

  Future<void> _markPracticeSight() async {
    if (!_exposed.add(_beat)) return;
    await _record(
      ShiftSession.sighting(
        drill: drill,
        beat: _beat,
        kind: ShiftSightKind.practice,
        sessionId: sessionId,
        at: _clock(),
        lane: lane,
        sourceUrl: sourceUrl,
      ),
    );
  }

  Future<void> _loadHistory() async {
    final all = await analytics.all();
    _history = ShiftSession.selfGrades(all, drillId: drill.id);
    notifyListeners();
  }

  Future<void> _write(
    ShiftCheck check, {
    required bool prompted,
    required bool correct,
    String? readSupport,
  }) => _record(
    ShiftSession.attempt(
      drill: drill,
      beat: _beat,
      check: check,
      prompted: prompted,
      correct: correct,
      sessionId: sessionId,
      at: _clock(),
      sourceUrl: sourceUrl,
      lane: lane,
      readSupport: readSupport,
    ),
  );

  Future<void> _record(Attempt attempt) async {
    final pending = analytics.record(attempt);
    persistence.trackAnalytics(pending);
    try {
      await pending;
    } on Object {
      // Memory retains the row; [isUnsaved] stays honest.
    }
    _syncUnsaved();
  }

  void _syncUnsaved() {
    _unsaved = analytics.unpersistedCount > 0;
    notifyListeners();
  }
}
