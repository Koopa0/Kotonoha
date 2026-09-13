// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// One item's foreground reaction-time window.
///
/// Valid RT is monotonic elapsed while the item stayed answerable.
/// [invalidate] freezes the clock — resume or same-item replay must not
/// restart it. Only [arm] (a new item) restores validity.
///
/// 0 means untimed (see Attempt.rtMs), not a claimed 0ms reflex.
class ItemReactionClock {
  ItemReactionClock({DateTime Function()? clock, int Function()? monotonicMs})
    : _clock = clock ?? DateTime.now,
      _monotonicMs = monotonicMs {
    _stopwatch = Stopwatch()..start();
  }

  final DateTime Function() _clock;
  final int Function()? _monotonicMs;
  late final Stopwatch _stopwatch;

  bool _valid = true;
  bool _started = false;
  int _startMonoMs = 0;
  int _startWallMs = 0;

  /// Whether this item may still contribute fluency evidence.
  bool get isValid => _valid;

  int _nowMonoMs() => _monotonicMs?.call() ?? _stopwatch.elapsedMilliseconds;

  /// Opens a new item. Timing is valid again; the start is unmarked unless
  /// [startImmediately] (dictation show-time).
  void arm({bool startImmediately = false}) {
    _valid = true;
    _started = false;
    if (startImmediately) start();
  }

  /// Marks the RT start (dictation show, or listening first valid hear).
  /// No-op once started or after [invalidate] — a replay cannot wash
  /// an interrupted item into a fresh clock.
  void start() {
    if (!_valid || _started) return;
    _started = true;
    _startMonoMs = _nowMonoMs();
    _startWallMs = _clock().millisecondsSinceEpoch;
  }

  /// Pause / hide / inactive. Invalidates this item's RT only.
  void invalidate() {
    _valid = false;
  }

  /// Monotonic foreground elapsed, or 0 when untimed.
  int elapsedMs() {
    if (!_valid || !_started) return 0;
    final mono = _nowMonoMs() - _startMonoMs;
    final wall = _clock().millisecondsSinceEpoch - _startWallMs;
    if (mono <= 0 || wall < 0) return 0;
    return mono;
  }
}
