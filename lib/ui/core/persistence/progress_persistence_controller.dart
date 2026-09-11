// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kotonoha/data/services/recoverable_store.dart';

/// Which body of progress a tracked write belongs to. Failure and retry are
/// tracked per repository, not per store, because a repository flushes ALL of
/// its dirty stores together — so one confirmed write clears the whole
/// repository's backlog.
enum _Repo { kana, kanji, word, placement }

/// The startup recovery notice, coalesced most-severe-wins across every store.
/// Ordered by how much it should worry the reader ([none] < [salvaged] <
/// [restored] < [preservationPending] < [recoveryRequired]); [none] when every
/// store came up clean (empty or loaded).
enum RecoveryNotice {
  none,
  salvaged,
  restored,
  preservationPending,
  recoveryRequired,
}

/// The owner's current, observable persistence state. [saving] and [idle] are
/// silent (no banner); only [failedNeedsRetry] surfaces one.
enum PersistenceStatus {
  /// Nothing in flight and nothing unpersisted.
  idle,

  /// A write is in flight; the response already showed, so this stays silent.
  saving,

  /// A write failed with no later flush covering it — the one banner shows.
  failedNeedsRetry,
}

/// The app-scoped owner of every progress-persistence future — lifetime above
/// any route, so a failure survives the screen that caused it.
///
/// Screens hand it the future a repository mutation returns ([trackKana] /
/// [trackKanji] / [trackWord] / [trackPlacement]) instead of dropping it. The mutation's in-memory effect and
/// its UI feedback have already fired synchronously, so tracking never delays
/// the response — it only observes the disk outcome out-of-band. Every tracked
/// error is handled here, so none escapes to the uncaught zone.
///
/// A write that fails with no later mutation to retry it raises
/// [hasWriteFailure], which a single app-level banner surfaces. [retry] flushes
/// exactly the failing repositories (never replaying a domain mutation) and the
/// surface clears only once all of them confirm. Per-repository sequence
/// numbers make the state correct under any completion order: a stale
/// completion can neither clear a newer failure nor overwrite a newer
/// confirmed flush.
class ProgressPersistenceController extends ChangeNotifier {
  ProgressPersistenceController({
    required Future<void> Function() kanaFlush,
    required Future<void> Function() kanjiFlush,
    required Future<void> Function() wordFlush,
    Future<void> Function()? placementFlush,
    Iterable<StoreHealth> health = const [],
  }) : _flush = {
         _Repo.kana: kanaFlush,
         _Repo.kanji: kanjiFlush,
         _Repo.word: wordFlush,
         _Repo.placement: placementFlush ?? () async {},
       },
       _recovery = _noticeFor(health);

  final Map<_Repo, Future<void> Function()> _flush;

  // A monotonic stamp per repository, assigned at submission, so a completion
  // is compared by age (seq) rather than by the order futures happen to settle.
  final Map<_Repo, int> _seq = {for (final r in _Repo.values) r: 0};
  // The newest confirmed-on-disk seq per repository. A failure older than this
  // is stale — a later flush already persisted its data too.
  final Map<_Repo, int> _maxOk = {for (final r in _Repo.values) r: 0};
  // The outstanding failure per repository (its seq), or null when clean.
  final Map<_Repo, int?> _failed = {for (final r in _Repo.values) r: null};

  final RecoveryNotice _recovery;
  bool _recoveryAck = false;
  bool _retrying = false;
  // Count of tracked writes still in flight — drives the [saving] status.
  int _inFlight = 0;

  /// True while any repository holds an unpersisted write no later confirmed
  /// flush has covered. The one app-level failure surface shows iff this.
  bool get hasWriteFailure => _failed.values.any((seq) => seq != null);

  /// The current observable state. A failure outranks in-flight saving.
  PersistenceStatus get status {
    if (hasWriteFailure) return PersistenceStatus.failedNeedsRetry;
    if (_inFlight > 0) return PersistenceStatus.saving;
    return PersistenceStatus.idle;
  }

  /// A write is in flight and nothing has failed — deliberately silent.
  bool get isSaving => status == PersistenceStatus.saving;

  /// A retry is in flight; the banner disables its action while true.
  bool get isRetrying => _retrying;

  /// The startup recovery notice, or [RecoveryNotice.none] once acknowledged
  /// for the session (or if every store came up clean). A live write failure
  /// outranks it — the banner checks [hasWriteFailure] first.
  RecoveryNotice get recoveryNotice =>
      _recoveryAck ? RecoveryNotice.none : _recovery;

  /// Observes a kana-progress mutation's future. Pass the future a mutation
  /// already returned (its in-memory effect has fired); the caller never awaits
  /// it, so answering stays instant.
  void trackKana(Future<void> save) => _track(_Repo.kana, save);

  /// Observes a kanji-progress mutation's future. See [trackKana].
  void trackKanji(Future<void> save) => _track(_Repo.kanji, save);

  /// Observes a 詞と句-progress mutation's future. See [trackKana].
  void trackWord(Future<void> save) => _track(_Repo.word, save);

  /// Observes a placement-check draft write. Retry / drain flush the draft
  /// only — they never replay [QuizViewModel.gradeRecall] or mint a second
  /// independent correct. Production always passes [placementFlush]; the
  /// no-op default is for tests that never touch this store.
  void trackPlacement(Future<void> save) => _track(_Repo.placement, save);

  // The observable signature the banner reacts to; notify only when it moves.
  (PersistenceStatus, bool) _view() => (status, _retrying);
  void _emitIfChanged((PersistenceStatus, bool) before) {
    if (_view() != before) notifyListeners();
  }

  void _track(_Repo repo, Future<void> save) {
    final before = _view();
    final seq = _seq[repo]! + 1;
    _seq[repo] = seq;
    _inFlight++;
    _emitIfChanged(before); // idle → saving, if this is the first in flight
    // Both handlers attach synchronously here, so [save]'s error is always
    // handled and never reaches the uncaught zone; the derived future carries
    // nothing to leak, so it is intentionally not awaited.
    unawaited(
      save.then(
        (_) => _settle(repo, seq, ok: true),
        onError: (Object _, StackTrace _) => _settle(repo, seq, ok: false),
      ),
    );
  }

  void _settle(_Repo repo, int seq, {required bool ok}) {
    final before = _view();
    _inFlight--;
    if (ok) {
      if (seq > _maxOk[repo]!) _maxOk[repo] = seq;
      final failed = _failed[repo];
      // A confirmed flush at-or-after the failed op persisted its data too (the
      // repository flushes every dirty store together), so the failure resolves.
      if (failed != null && seq >= failed) _failed[repo] = null;
    } else if (seq > _maxOk[repo]!) {
      // Not stale (no newer op has confirmed on disk) → record the newest fail.
      final failed = _failed[repo];
      if (failed == null || seq > failed) _failed[repo] = seq;
    }
    _emitIfChanged(before);
  }

  /// Retries every currently-failing repository by flushing its pending state
  /// (no domain mutation is replayed). The surface clears only when all failing
  /// repositories confirm; any that fail again keep it up. Rapid taps while a
  /// retry is in flight are ignored.
  Future<void> retry() async {
    if (_retrying) return;
    final before = _view();
    _retrying = true;
    _emitIfChanged(before); // notify: the action goes to its retrying state
    try {
      final pending = <Future<void>>[];
      for (final repo in _Repo.values) {
        if (_failed[repo] != null) {
          final save = _flush[repo]!();
          _track(repo, save);
          // A swallowing copy so the retry future itself completes without
          // rethrowing; the real outcome is already recorded via _track.
          pending.add(save.catchError((Object _) {}));
        }
      }
      await Future.wait(pending);
    } finally {
      final settled = _view();
      _retrying = false;
      _emitIfChanged(settled); // notify: retry finished (cleared or still up)
    }
  }

  /// Best-effort flush of every repository for a lifecycle hide/pause/detach
  /// drain. A clean repository is a no-op; a failure is observed like any
  /// tracked write. Never a guarantee the OS lets it finish before a kill.
  void drain() {
    for (final repo in _Repo.values) {
      _track(repo, _flush[repo]!());
    }
  }

  /// Dismisses the startup recovery notice for this app session only (not
  /// persisted — a genuinely unresolved store speaks again next launch).
  void acknowledgeRecovery() {
    if (_recoveryAck) return;
    _recoveryAck = true;
    notifyListeners();
  }

  static RecoveryNotice _noticeFor(Iterable<StoreHealth> health) {
    var worst = RecoveryNotice.none;
    for (final h in health) {
      final notice = switch (h) {
        StoreHealth.empty || StoreHealth.loaded => RecoveryNotice.none,
        StoreHealth.salvaged => RecoveryNotice.salvaged,
        StoreHealth.restored => RecoveryNotice.restored,
        StoreHealth.preservationPending => RecoveryNotice.preservationPending,
        StoreHealth.recoveryRequired => RecoveryNotice.recoveryRequired,
      };
      if (notice.index > worst.index) worst = notice;
    }
    return worst;
  }
}
