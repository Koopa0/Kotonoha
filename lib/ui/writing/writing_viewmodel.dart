// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// Owns one 習字 session: the cursor, the reveal, the self-grade, and every
/// progress or analytics write. The screen speaks, renders, and navigates.
///
/// Evidence contract (the same one the widget state used to hold): every
/// self-grade is a kana answer on the per-kana schedule (a miss resets, a
/// hit climbs) and a `write`-direction [Attempt]; the handwriting itself is
/// on paper and never inspected. Untimed — the paper has no clock.
///
/// Playback is not interpreted here: hearing the kana is a comfort, not
/// evidence, so the view owns the speaker. Pure of timers and navigation.
class WritingViewModel extends ChangeNotifier {
  WritingViewModel({
    required this.targets,
    required this.kana,
    required this.persistence,
    required this.analytics,
    this.sessionId = '',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<Kana> targets;

  /// Owner of the per-kana schedule this session grades into.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future; grading never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  final DateTime Function() _clock;

  int _index = 0;
  bool _revealed = false;
  int _correct = 0;
  bool _finished = false;

  int get index => _index;
  int get total => targets.length;
  Kana get current => targets[_index];
  bool get isLastItem => _index + 1 >= total;
  bool get isRevealed => _revealed;
  int get correctCount => _correct;
  bool get isFinished => _finished;

  /// Shows the kana the learner just wrote from its romaji.
  void reveal() {
    if (_finished || _revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// Self-grades the revealed kana and moves on. Ignored before reveal.
  void grade({required bool correct}) {
    if (_finished || !_revealed) return;
    final now = _clock();
    final item = current;
    persistence.trackKana(kana.recordAnswer(item, correct: correct, at: now));
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: item.id,
        mode: PracticeMode.writing.name,
        correct: correct,
        sessionId: sessionId,
        meta: const {AttemptMeta.direction: 'write'},
      ),
    );
    if (correct) _correct++;
    if (isLastItem) {
      _finished = true;
    } else {
      _index++;
      _revealed = false;
    }
    notifyListeners();
  }
}
