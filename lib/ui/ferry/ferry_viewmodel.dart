// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';

/// The three beats one word is ferried through.
enum FerryBeat {
  /// The word is only heard; its kana stays hidden.
  hear,

  /// The kana inks in over the still-ringing audio — the binding.
  see,

  /// The learner reads it back unaided, then self-grades.
  readback,
}

/// Owns one 渡し舟 session: the cursor, the beat, the read-back timing, the
/// self-grade, and every progress or analytics write that follows from it.
/// The screen speaks, renders each beat, and navigates.
///
/// Evidence contract (the same one the widget state used to hold):
/// - 渡し舟 introduces, it never reviews. A successful read-back is an
///   encode credit ([WordProgressRepository.introduce] → schedule).
/// - A first miss still marks the word seen
///   ([WordProgressRepository.markIntroduced]) so intake cannot replay it,
///   but never writes a successful recall. A seen miss writes nothing.
/// - Every grade is logged as a word-level ferry [Attempt] whose
///   [Attempt.rtMs] covers only the read-back beat — the see-beat dwell
///   is binding time, not recall.
///
/// Playback is not interpreted here: the word is spoken on arrival and on
/// the see beat as a binding, never as evidence, so the view owns the
/// speaker and its lifecycle. Pure of timers and navigation.
class FerryViewModel extends ChangeNotifier {
  FerryViewModel({
    required this.items,
    required this.words,
    required this.kana,
    required this.persistence,
    required this.analytics,
    this.sessionId = '',
    DateTime Function()? clock,
    Random? rng,
    this._kotenPool = kKoten,
  }) : _clock = clock ?? DateTime.now,
       _rng = rng ?? Random();

  final List<Word> items;

  /// Owner of the 詞と句 schedule this session introduces into.
  final WordProgressRepository words;

  /// Read only at the close: the met-kana count gates the classical 余韻.
  final KanaProgressRepository kana;

  /// App-scoped owner of every write's future; grading never waits on disk.
  final ProgressPersistenceController persistence;
  final AnalyticsLog analytics;
  final String sessionId;

  final DateTime Function() _clock;
  final Random _rng;
  final List<KotenLine> _kotenPool;

  int _index = 0;
  FerryBeat _beat = FerryBeat.hear;
  int _readbackAtMs = 0;
  int _correct = 0;
  bool _finished = false;
  KotenLine? _share;

  int get index => _index;
  int get total => items.length;
  Word get current => items[_index];
  bool get isLastItem => _index + 1 >= total;
  FerryBeat get beat => _beat;

  /// The kana is on screen from the see beat on.
  bool get showsKana => _beat != FerryBeat.hear;
  int get correctCount => _correct;
  bool get isFinished => _finished;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? get share => _share;

  /// Hear → see: the kana inks in. Ignored off the hear beat.
  void showText() {
    if (_finished || _beat != FerryBeat.hear) return;
    _beat = FerryBeat.see;
    notifyListeners();
  }

  /// See → read-back. Time only the read-back — the see-beat dwell must
  /// not count. Ignored off the see beat.
  void readSelf() {
    if (_finished || _beat != FerryBeat.see) return;
    _beat = FerryBeat.readback;
    _readbackAtMs = _clock().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Self-grades the read-back and moves on. Ignored off the read-back beat.
  void grade({required bool correct}) {
    if (_finished || _beat != FerryBeat.readback) return;
    final now = _clock();
    final item = current;
    analytics.recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: item.kana,
        itemType: ItemType.word,
        mode: PracticeMode.ferry.name,
        correct: correct,
        rtMs: now.millisecondsSinceEpoch - _readbackAtMs,
        sessionId: sessionId,
        meta: {'romaji': item.romaji},
      ),
    );
    // 渡し舟 introduces, it never reviews. A first successful read-back is
    // an encode credit (introduce → schedule). A first miss still marks the
    // word seen so intake cannot replay it, but must not write a successful
    // recall. Re-ferrying a seen word is exposure only.
    final id = item.progressId;
    if (correct) {
      persistence.trackWord(words.introduce(id, at: now));
    } else if (!words.statForItem(id).isSeen) {
      persistence.trackWord(words.markIntroduced(id, at: now));
    }
    if (correct) _correct++;
    if (isLastItem) {
      _share = KotenShare.pick(
        pool: _kotenPool,
        seenKanaCount: kana.seenCount,
        rng: _rng,
        season: Season.forMonth(now.month),
      );
      _finished = true;
    } else {
      _index++;
      _beat = FerryBeat.hear;
    }
    notifyListeners();
  }
}
