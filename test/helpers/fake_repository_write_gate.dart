// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

/// Two-phase gate for a fake repository flush: the flush completes
/// [entered] once it is about to persist, then parks until [release].
///
/// This is what lets a leave-page test dispose a ViewModel while a write is
/// genuinely in flight, rather than approximating it with a delay.
class FakeRepositoryWriteGate {
  final Completer<void> _entered = Completer<void>();
  final Completer<void> _released = Completer<void>();

  Future<void> get entered => _entered.future;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  Future<void> pass() async {
    if (!_entered.isCompleted) _entered.complete();
    await _released.future;
  }
}
