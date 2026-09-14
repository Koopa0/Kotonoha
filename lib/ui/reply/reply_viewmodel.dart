// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';

/// The two beats one reply drill runs through.
enum ReplyBeat {
  /// Name what the station ask wanted.
  intent,

  /// Pick the short reply that answers it.
  reply,
}

/// Owns one 短く返す session: the cursor, the beat, the shuffled choices,
/// what was heard, seen and hinted, both picks, the hear clock and every
/// analytics write. The screen plays audio, reports outcomes and
/// interrupts, renders, and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - Playback success is heard evidence ([isHeard]); only a heard drill is
///   scored, and its reaction time runs from the first completed hear.
/// - Seeing the Japanese ([sawText]) or the meaning ([hinted]) is recorded
///   separately — `independent`, `peeked` and `hinted` are never
///   interchangeable, and an unheard skip is `unheard`.
/// - The reply beat inherits the intent beat's independence: a peeked
///   intent cannot be followed by an independent reply.
/// - A correct tap is never spoken-production evidence, and this room never
///   writes 詞と句 SRS.
///
/// This type never interprets playback: the view decides what a completed
/// play is and drops cancelled or stale generations before calling
/// [notePlayback]. Pure of timers and navigation.
class ReplyViewModel extends ChangeNotifier {
  ReplyViewModel({
    required this.drills,
    required this.analytics,
    this.sessionId = '',
    DateTime Function()? clock,
    Random? rng,
  }) : _clock = clock ?? DateTime.now,
       _rng = rng ?? Random() {
    _shuffleChoices();
  }

  final List<ReplyDrill> drills;
  final AnalyticsLog analytics;
  final String sessionId;

  final DateTime Function() _clock;
  final Random _rng;

  int _index = 0;
  ReplyBeat _beat = ReplyBeat.intent;
  bool _heard = false;
  bool _sawText = false;
  bool _hinted = false;
  bool _finished = false;
  bool _intentIndependent = false;
  String? _intentPick;
  String? _replyPick;
  int _heardAtMs = 0;
  SpeechPlaybackResult? _lastPlay;
  late List<String> _intentOrder;
  late List<String> _replyOrder;

  int get index => _index;
  int get total => drills.length;
  ReplyDrill get current => drills[_index];
  bool get isLastItem => _index + 1 >= total;
  ReplyBeat get beat => _beat;

  /// A play completed for this drill — it can be scored.
  bool get isHeard => _heard;

  /// The Japanese is on screen (recorded as `prompted`).
  bool get sawText => _sawText;

  /// The meaning is on screen (recorded as `hinted`).
  bool get hinted => _hinted;
  String? get intentPick => _intentPick;
  String? get replyPick => _replyPick;

  /// Intent and reply choices in this drill's shuffled order.
  List<String> get intentOrder => _intentOrder;
  List<String> get replyOrder => _replyOrder;

  /// The last playback outcome the view reported for this drill, or `null`
  /// before any (a fresh drill forgets the previous one).
  SpeechPlaybackResult? get lastPlay => _lastPlay;
  bool get isFinished => _finished;

  bool isIntentCorrect(String option) => option == current.intentCorrect;
  bool isReplyCorrect(String option) => current.isReplyCorrect(option);

  /// The view reports the outcome of one foreground play of [itemIndex].
  /// A completion for another drill is stale and ignored — the view already
  /// drops cancelled generations before reporting.
  void notePlayback({
    required int itemIndex,
    required SpeechPlaybackResult result,
  }) {
    if (_finished || itemIndex != _index) return;
    _lastPlay = result;
    if (result == SpeechPlaybackResult.played) {
      _heard = true;
      if (_heardAtMs == 0) _heardAtMs = _clock().millisecondsSinceEpoch;
    }
    notifyListeners();
  }

  /// Pause / hide / inactive: the sound stopped before it finished.
  void noteInterrupted() {
    if (_finished) return;
    _lastPlay = SpeechPlaybackResult.interrupted;
    notifyListeners();
  }

  /// Shows the meaning. Recorded on every later pick of this drill.
  void showHint() {
    if (_finished || _hinted) return;
    _hinted = true;
    notifyListeners();
  }

  /// Shows the Japanese. Recorded on every later pick of this drill.
  void showText() {
    if (_finished || _sawText) return;
    _sawText = true;
    notifyListeners();
  }

  /// Names the intent. Logged at once; ignored once picked.
  void pickIntent(String choice) {
    if (_finished || _beat != ReplyBeat.intent || _intentPick != null) return;
    final correct = isIntentCorrect(choice);
    final evidence = ReplyEvidence.classify(
      heard: _heard,
      sawText: _sawText,
      usedHint: _hinted,
      correct: correct,
    );
    _log(beat: ReplyEvidence.intent, choice: choice, evidence: evidence);
    _intentPick = choice;
    _intentIndependent = ReplyEvidence.isIndependent(evidence);
    notifyListeners();
  }

  /// Intent → reply. Ignored until the intent is named.
  void toReply() {
    if (_finished || _beat != ReplyBeat.intent || _intentPick == null) return;
    _beat = ReplyBeat.reply;
    notifyListeners();
  }

  /// Picks the short reply. Logged at once; ignored once picked.
  void pickReply(String choice) {
    if (_finished || _beat != ReplyBeat.reply || _replyPick != null) return;
    final correct = isReplyCorrect(choice);
    final evidence = ReplyEvidence.classify(
      heard: _heard,
      sawText: _sawText,
      usedHint: _hinted,
      correct: correct,
      priorIndependent: _intentIndependent,
    );
    _log(beat: ReplyEvidence.reply, choice: choice, evidence: evidence);
    _replyPick = choice;
    notifyListeners();
  }

  /// Leaves an answered drill: the next one, or the close after the last.
  void advance() {
    if (_finished || _replyPick == null) return;
    _advance();
  }

  /// Moves past a drill that was never heard, logging it as `unheard`.
  void skipUnheard() {
    if (_finished || _heard || _intentPick != null) return;
    _log(
      beat: ReplyEvidence.intent,
      choice: '',
      evidence: ReplyEvidence.unheard,
    );
    _advance();
  }

  void _advance() {
    if (isLastItem) {
      _finished = true;
    } else {
      _index++;
      _beat = ReplyBeat.intent;
      _heard = false;
      _sawText = false;
      _hinted = false;
      _intentIndependent = false;
      _intentPick = null;
      _replyPick = null;
      _heardAtMs = 0;
      _lastPlay = null;
      _shuffleChoices();
    }
    notifyListeners();
  }

  void _shuffleChoices() {
    _intentOrder = List<String>.of(current.intentChoices)..shuffle(_rng);
    _replyOrder = List<String>.of(current.replyChoices)..shuffle(_rng);
  }

  void _log({
    required String beat,
    required String choice,
    required String evidence,
  }) {
    final now = _clock();
    final scored = _heard;
    final correct =
        evidence == ReplyEvidence.independent ||
        evidence == ReplyEvidence.peeked ||
        evidence == ReplyEvidence.hinted;
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: current.id,
        itemType: ItemType.word,
        mode: PracticeMode.reply.name,
        correct: scored && correct,
        rtMs: scored && _heardAtMs != 0
            ? now.millisecondsSinceEpoch - _heardAtMs
            : 0,
        sessionId: sessionId,
        meta: {
          AttemptMeta.beat: beat,
          AttemptMeta.evidence: evidence,
          AttemptMeta.heard: _heard,
          AttemptMeta.prompted: _sawText,
          AttemptMeta.hinted: _hinted,
          AttemptMeta.scored: scored,
          AttemptMeta.playback:
              (_lastPlay ?? SpeechPlaybackResult.interrupted).name,
          if (!correct && choice.isNotEmpty) AttemptMeta.distractor: choice,
        },
      ),
    );
  }
}
