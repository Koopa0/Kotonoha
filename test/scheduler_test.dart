// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/use_cases/scheduler.dart';

void main() {
  const all = kHiraganaGojuon;
  final now = DateTime(2026, 5, 30, 12);

  test('due lists only kana whose dueAt has passed, earliest first', () {
    final stats = <String, KanaStat>{
      'あ': KanaStat(
        seenCount: 1,
        dueAt: now.subtract(const Duration(hours: 2)),
      ),
      'い': KanaStat(
        seenCount: 1,
        dueAt: now.subtract(const Duration(hours: 5)),
      ),
      'う': KanaStat(
        seenCount: 1,
        dueAt: now.add(const Duration(hours: 1)),
      ), // future
    };
    final due = Scheduler.due(all, stats, now: now);
    expect(due.map((k) => k.character).toList(), ['い', 'あ']); // earliest first
    expect(Scheduler.dueCount(all, stats, now: now), 2);
  });

  test('unseen / never-scheduled kana are not due', () {
    expect(Scheduler.due(all, const {}, now: now), isEmpty);
  });

  test('a correct answer pushes dueAt into the future (not due now)', () {
    final stat = const KanaStat().recordAnswer(correct: true, at: now);
    expect(stat.srsLevel, 1);
    expect(stat.dueAt!.isAfter(now), isTrue);
    final stats = {'あ': stat};
    expect(Scheduler.due(all, stats, now: now), isEmpty);
    // ...but it IS due once the interval elapses.
    final later = stat.dueAt!.add(const Duration(minutes: 1));
    expect(Scheduler.dueCount(all, stats, now: later), 1);
  });

  test('a wrong answer resets srsLevel and schedules a soon review', () {
    final strong = const KanaStat(
      srsLevel: 4,
    ).recordAnswer(correct: false, at: now);
    expect(strong.srsLevel, 0);
    expect(strong.dueAt!.isBefore(now.add(const Duration(hours: 1))), isTrue);
  });
}
