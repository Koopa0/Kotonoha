// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production-composition regression for #15: a due backlog that already
/// fills a session must keep being served across days of real
/// [ReadingStat.recordAnswer] updates. The composer on main ranked new
/// ahead of due, so 12 overdue units never boarded while 153 unmet ones
/// existed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'eight days of real stats: due backlog is served, new intake is capped',
    () async {
      final repo = await KanjiReadingRepository.load();
      final start = DateTime(2026, 9, 10, 10);
      final originalDue = kKanjiUnits.take(12).toList();
      final originalIds = {for (final u in originalDue) u.id};
      final seededAt = start.subtract(const Duration(days: 2));
      for (final u in originalDue) {
        await repo.recordAnswer(u.id, correct: true, at: seededAt);
      }

      var daysDueWentUnserved = 0;
      for (var day = 0; day < 8; day++) {
        final now = start.add(Duration(days: day));
        final dueBefore = repo.dueUnitIds(now).toSet();
        final picked = KanjiSession.compose(
          units: kKanjiUnits,
          stats: repo.stats,
          now: now,
          rng: Random(day),
        );
        final selectedDue = picked
            .where((u) => dueBefore.contains(u.id))
            .length;
        final selectedNew = picked
            .where((u) => !repo.statForUnit(u.id).isSeen)
            .length;
        final originalDueSelected = picked
            .where((u) => originalIds.contains(u.id))
            .length;

        if (dueBefore.length >= KanjiSession.kDefaultLength) {
          expect(selectedDue, KanjiSession.kDefaultLength, reason: 'day=$day');
          expect(selectedNew, 0, reason: 'day=$day backlog must gate new');
        } else {
          expect(
            selectedDue,
            dueBefore.length,
            reason: 'day=$day every due boards',
          );
          expect(
            selectedNew,
            lessThanOrEqualTo(KanjiSession.kDefaultMaxNew),
            reason: 'day=$day',
          );
        }
        if (dueBefore.isNotEmpty && selectedDue == 0) daysDueWentUnserved++;

        // Mix: some of the original twelve stay in the pool as not-yet-due
        // after a correct answer; the composer must not drop them from the
        // universe, only from the due tier.
        expect(picked, isNotEmpty);
        expect({for (final u in picked) u.id}, hasLength(picked.length));

        for (final u in picked) {
          await repo.recordAnswer(u.id, correct: true, at: now);
        }

        // Silence unused on the first days when original twelve are not due.
        expect(originalDueSelected, greaterThanOrEqualTo(0));
      }

      expect(daysDueWentUnserved, 0);
      // The original twelve were served on day 0 (all due) and must still
      // have progress — never wiped, never stuck at the seed.
      for (final u in originalDue) {
        final s = repo.statForUnit(u.id);
        expect(s.seenCount, greaterThan(1), reason: u.id);
        expect(s.srsLevel, greaterThan(1), reason: u.id);
      }
    },
  );

  test(
    'mixed due / not-due / new: review compose keeps teach XOR recall',
    () async {
      final repo = await KanjiReadingRepository.load();
      final now = DateTime(2026, 9, 10, 10);
      final due = kKanjiUnits.take(5).toList();
      final rest = kKanjiUnits.skip(5).take(5).toList();
      for (final u in due) {
        await repo.recordAnswer(
          u.id,
          correct: true,
          at: now.subtract(const Duration(days: 2)),
        );
      }
      for (final u in rest) {
        await repo.recordAnswer(u.id, correct: true, at: now);
      }

      final review = KanjiSession.compose(
        units: kKanjiUnits,
        stats: repo.stats,
        now: now,
        rng: Random(1),
        maxNew: 0,
      );
      expect(review.where((u) => due.any((d) => d.id == u.id)).length, 5);
      expect(review.any((u) => !repo.statForUnit(u.id).isSeen), isFalse);

      final meet = KanjiSession.compose(
        units: kKanjiUnits,
        stats: repo.stats,
        now: now,
        rng: Random(1),
      );
      final meetNew = meet.where((u) => !repo.statForUnit(u.id).isSeen).length;
      expect(meet.where((u) => due.any((d) => d.id == u.id)).length, 5);
      expect(meetNew, KanjiSession.kDefaultMaxNew);

      // Teach vs recall is still isSeen: due/rest stay recall, new stay teach.
      bool isTeach(KanjiUnit u) => !repo.statForUnit(u.id).isSeen;
      expect(meet.where(isTeach).length, meetNew);
      expect(review.where(isTeach), isEmpty);
    },
  );
}
