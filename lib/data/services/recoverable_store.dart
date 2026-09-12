// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/data/services/preferences_service.dart';

/// How a guarded store came up at load.
enum StoreHealth {
  /// The primary key was absent — the only legal fresh-install empty state.
  empty,

  /// The primary decoded completely.
  loaded,

  /// The primary's top level was valid but some entries were not: the valid
  /// entries were kept and the exact raw payload quarantined first.
  salvaged,

  /// The primary was unreadable; state came from last-known-good after the
  /// exact raw payload was quarantined.
  restored,

  /// The primary was damaged but a usable value was recovered (salvage or
  /// last-known-good restore) — and the exact damaged raw could NOT yet be
  /// confirmed quarantined (the platform refused or threw). The raw still
  /// sits only under the primary key; [RecoverableStore.write] will not
  /// replace it until a quarantine write succeeds.
  preservationPending,

  /// The primary was unreadable and no valid last-known-good exists. The
  /// store starts empty in memory but was NOT mistaken for a fresh install:
  /// the damaged payload stays under its primary key, and the next
  /// successful write quarantines it before replacing it.
  recoveryRequired,
}

/// Typed outcome of [RecoverableStore.load]: the usable [value] plus how it
/// was obtained. [value] is a freshly-built mutable container; it is empty
/// for [StoreHealth.empty] and [StoreHealth.recoveryRequired].
class StoreLoad<T> {
  const StoreLoad(this.health, this.value);

  final StoreHealth health;
  final T value;
}

/// Verdict of decoding one raw payload.
sealed class DecodeResult<T> {
  const DecodeResult();
}

/// The top level decoded; [dropped] counts individually corrupt entries that
/// were discarded while the rest were kept (0 = fully valid).
final class DecodeOk<T> extends DecodeResult<T> {
  const DecodeOk(this.value, {this.dropped = 0});

  final T value;
  final int dropped;
}

/// The payload is unusable at the top level (unparseable or wrong type).
final class DecodeCorrupt<T> extends DecodeResult<T> {
  const DecodeCorrupt();
}

/// A set/remove the platform reported as failed (a `false` return). Thrown
/// instead of swallowed so a mutation is never mistaken for saved: it
/// surfaces on the future a repository mutation returns. Callers that don't
/// await keep the in-memory state and leave the retry to the next mutation.
class StoreWriteFailure implements Exception {
  const StoreWriteFailure(this.key);

  final String key;

  @override
  String toString() => 'StoreWriteFailure(key: $key)';
}

/// One shared_preferences slot guarded against data loss: a primary key plus
/// a last-known-good copy and a quarantine slot for damaged payloads (both
/// stored exactly as found, never re-encoded).
///
/// The write protocol is the firewall: before the primary is overwritten,
/// whatever is there now is preserved — a fully valid payload to
/// [lastGoodKey], a damaged one to [quarantineKey] (never promoted to
/// last-known-good). Only when preservation succeeds is the primary
/// replaced, so no failure sequence can silently destroy the only copy of
/// the user's progress.
class RecoverableStore<T> {
  RecoverableStore({
    required this._prefs,
    required this.primaryKey,
    required this.lastGoodKey,
    required this.quarantineKey,
    required this._empty,
    required this._decode,
  });

  final PreferencesService _prefs;
  final String primaryKey;
  final String lastGoodKey;
  final String quarantineKey;
  final T Function() _empty;
  final DecodeResult<T> Function(String raw) _decode;

  /// Loads the primary, distinguishing the cases documented on
  /// [StoreHealth]. A load never rewrites the primary. A damaged payload is
  /// only reported [StoreHealth.salvaged] / [StoreHealth.restored] once its
  /// exact raw was confirmed quarantined; an unconfirmed copy (a `false` or
  /// a platform exception) downgrades to [StoreHealth.preservationPending] —
  /// [write] then re-runs preservation as the hard gate before any
  /// overwrite, so the raw is still never lost.
  Future<StoreLoad<T>> load() async {
    final raw = _prefs.readString(primaryKey);
    if (raw == null) return StoreLoad(StoreHealth.empty, _empty());
    switch (_decode(raw)) {
      case DecodeOk<T>(:final value, dropped: 0):
        return StoreLoad(StoreHealth.loaded, value);
      case DecodeOk<T>(:final value):
        return StoreLoad(
          await _quarantine(raw)
              ? StoreHealth.salvaged
              : StoreHealth.preservationPending,
          value,
        );
      case DecodeCorrupt<T>():
        final lastGood = _prefs.readString(lastGoodKey);
        if (lastGood != null) {
          final restored = _decode(lastGood);
          if (restored is DecodeOk<T> && restored.dropped == 0) {
            return StoreLoad(
              await _quarantine(raw)
                  ? StoreHealth.restored
                  : StoreHealth.preservationPending,
              restored.value,
            );
          }
        }
        return StoreLoad(StoreHealth.recoveryRequired, _empty());
    }
  }

  /// Resolves the store's current value with the same recovery semantics as
  /// [load] — primary, else a fully-valid last-known-good, else empty — but
  /// touching nothing: no quarantine write, no primary write. Only
  /// meaningful right after [PreferencesService.reload], when reads reflect
  /// the platform's durable state rather than the legacy plugin cache.
  T recoverCurrent() {
    final raw = _prefs.readString(primaryKey);
    if (raw == null) return _empty();
    switch (_decode(raw)) {
      case DecodeOk<T>(:final value):
        return value;
      case DecodeCorrupt<T>():
        final lastGood = _prefs.readString(lastGoodKey);
        if (lastGood != null) {
          final restored = _decode(lastGood);
          if (restored is DecodeOk<T> && restored.dropped == 0) {
            return restored.value;
          }
        }
        return _empty();
    }
  }

  /// Overwrites the primary with [encoded] — after preserving what is there
  /// now (see the class doc). Throws [StoreWriteFailure] when the platform
  /// reports a failed write; the primary is only replaced once preservation
  /// has succeeded.
  Future<void> write(
    String encoded, {
    bool Function()? commitGuard,
  }) async {
    final current = _prefs.readString(primaryKey);
    if (current != null) {
      final verdict = _decode(current);
      final fullyValid = verdict is DecodeOk<T> && verdict.dropped == 0;
      await _checkedWrite(
        fullyValid ? lastGoodKey : quarantineKey,
        current,
        commitGuard: commitGuard,
      );
    }
    await _checkedWrite(primaryKey, encoded, commitGuard: commitGuard);
  }

  /// Removes exactly this store's keys (reset). Auxiliary copies go first so
  /// a failure part-way never deletes the primary while stale copies linger.
  Future<void> removeAll() async {
    for (final key in [quarantineKey, lastGoodKey, primaryKey]) {
      if (!await _prefs.remove(key)) throw StoreWriteFailure(key);
    }
  }

  Future<void> _checkedWrite(
    String key,
    String value, {
    bool Function()? commitGuard,
  }) async {
    if (commitGuard != null && !commitGuard()) return;
    if (!await _prefs.writeString(key, value)) {
      if (commitGuard != null && !commitGuard()) return;
      throw StoreWriteFailure(key);
    }
    if (commitGuard != null && !commitGuard()) return;
  }

  /// Attempts to copy a damaged raw payload into quarantine, reporting
  /// whether the platform confirmed it. Never throws — a load must not
  /// crash bootstrap — so a `false` and a platform exception both come back
  /// as an unconfirmed preservation for [load] to report honestly.
  Future<bool> _quarantine(String raw) async {
    try {
      return await _prefs.writeString(quarantineKey, raw);
    } catch (_) {
      return false;
    }
  }
}
