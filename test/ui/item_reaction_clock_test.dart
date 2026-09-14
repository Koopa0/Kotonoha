// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/ui/core/item_reaction_clock.dart';

void main() {
  test('foreground elapsed is recorded as timed RT', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.start();
    elapsed = 500;
    now = now.add(const Duration(milliseconds: 500));
    expect(clock.elapsedMs(), 500);
  });

  test('invalidate then complete is untimed', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.start();
    clock.invalidate();
    elapsed = 600500;
    now = now.add(const Duration(minutes: 10, milliseconds: 500));
    expect(clock.elapsedMs(), 0);
  });

  test('start after invalidate does not wash a fresh RT', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.invalidate();
    elapsed = 1000;
    now = now.add(const Duration(milliseconds: 1000));
    clock.start();
    elapsed = 1500;
    now = now.add(const Duration(milliseconds: 500));
    expect(clock.elapsedMs(), 0);
    expect(clock.isValid, isFalse);
  });

  test('resume must not restart an interrupted item', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.start();
    clock.invalidate();
    elapsed = 1000;
    now = now.add(const Duration(milliseconds: 1000));
    clock.start();
    elapsed = 1500;
    expect(clock.elapsedMs(), 0);
  });

  test('arm on a new item restores a timed window', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.start();
    clock.invalidate();
    expect(clock.elapsedMs(), 0);

    elapsed = 2000;
    now = now.add(const Duration(milliseconds: 2000));
    clock.arm();
    clock.start();
    elapsed = 2500;
    now = now.add(const Duration(milliseconds: 500));
    expect(clock.elapsedMs(), 500);
    expect(clock.isValid, isTrue);
  });

  test('second start does not move the origin', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 0;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.start();
    elapsed = 400;
    clock.start();
    elapsed = 900;
    now = now.add(const Duration(milliseconds: 900));
    expect(clock.elapsedMs(), 900);
  });

  test('non-positive mono or backward wall is untimed', () {
    var now = DateTime(2026, 9, 10, 12);
    var elapsed = 10;
    final clock = ItemReactionClock(
      clock: () => now,
      monotonicMs: () => elapsed,
    );
    clock.start();
    elapsed = 10;
    expect(clock.elapsedMs(), 0);
    elapsed = 50;
    now = now.subtract(const Duration(milliseconds: 20));
    expect(clock.elapsedMs(), 0);
  });
}
