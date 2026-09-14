// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #149 B9: every repository is the single owner of its data, so what a
/// reader gets back must be a snapshot it cannot write through. Two
/// separate promises are checked per collection:
///
/// 1. The returned collection rejects mutation, so a reader cannot reach
///    into the owner by accident.
/// 2. A snapshot taken before a write does not change when the owner
///    writes, so a value already handed out cannot shift underfoot.
///
/// These were once held by `Map.unmodifiable` / `Set.unmodifiable` calls
/// that a later edit could quietly drop (#151). Reading them back here
/// makes the promise executable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 6, 10, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('kana progress', () {
    test('stats is a snapshot the reader cannot write through', () async {
      final kana = await KanaProgressRepository.load();
      final first = kHiraganaGojuon.first;
      await kana.recordAnswer(first, correct: true, at: at, latencyMs: 300);

      final snapshot = kana.stats;
      expect(snapshot, isNotEmpty);
      expect(snapshot.clear, throwsUnsupportedError);
      expect(
        () => snapshot[first.id] = const KanaStat(),
        throwsUnsupportedError,
      );
      expect(() => snapshot.remove(first.id), throwsUnsupportedError);

      final before = Map<String, KanaStat>.of(snapshot);
      await kana.recordAnswer(
        kHiraganaGojuon[1],
        correct: true,
        at: at,
        latencyMs: 300,
      );
      expect(snapshot.keys, before.keys, reason: 'the handed-out map moved');
      expect(kana.stats.keys, isNot(before.keys));
    });

    test(
      'learnedUnits is a snapshot the reader cannot write through',
      () async {
        final kana = await KanaProgressRepository.load();
        final rows = Lessons.fromKana(kana.allKana);
        await kana.markUnitLearned(rows.first.id);

        final snapshot = kana.learnedUnits;
        expect(snapshot, contains(rows.first.id));
        expect(snapshot.clear, throwsUnsupportedError);
        expect(() => snapshot.add('made up'), throwsUnsupportedError);

        await kana.markUnitLearned(rows[1].id);
        expect(snapshot, hasLength(1), reason: 'the handed-out set moved');
        expect(kana.learnedUnits, hasLength(2));
      },
    );

    test('seenUnlocks is a snapshot the reader cannot write through', () async {
      final kana = await KanaProgressRepository.load();
      await kana.markUnlockSeen('words');

      final snapshot = kana.seenUnlocks;
      expect(snapshot, contains('words'));
      expect(snapshot.clear, throwsUnsupportedError);
      expect(() => snapshot.add('made up'), throwsUnsupportedError);

      await kana.markUnlockSeen('phrases');
      expect(snapshot, hasLength(1), reason: 'the handed-out set moved');
      expect(kana.seenUnlocks, hasLength(2));
    });

    test('the kana catalogue is read-only', () async {
      final kana = await KanaProgressRepository.load();
      expect(kana.allKana.clear, throwsUnsupportedError);
      // gojuonKana filters into a fresh list, so writing to it is harmless —
      // but it must not be the same object twice, or two readers would share.
      expect(identical(kana.gojuonKana, kana.gojuonKana), isFalse);
    });
  });

  test('word stats is a snapshot the reader cannot write through', () async {
    final words = await WordProgressRepository.load();
    await words.recordAnswer('word:あい', correct: true, at: at);

    final snapshot = words.stats;
    expect(snapshot, isNotEmpty);
    expect(snapshot.clear, throwsUnsupportedError);
    expect(
      () => snapshot['word:あい'] = const WordStat(),
      throwsUnsupportedError,
    );

    final before = Map<String, WordStat>.of(snapshot);
    await words.recordAnswer('word:えき', correct: true, at: at);
    expect(snapshot.keys, before.keys, reason: 'the handed-out map moved');
    expect(words.stats.keys, isNot(before.keys));
  });

  group('kanji reading', () {
    test('stats is a snapshot the reader cannot write through', () async {
      final kanji = await KanjiReadingRepository.load();
      final unitId = kanji.stats.keys.isEmpty ? null : kanji.stats.keys.first;
      expect(unitId, isNull, reason: 'a cold store starts with no rows');

      final cold = kanji.stats;
      expect(cold.clear, throwsUnsupportedError);
      expect(
        () => cold['unit:made-up'] = const ReadingStat(),
        throwsUnsupportedError,
      );
    });

    test('the kanji catalogue is read-only', () async {
      final kanji = await KanjiReadingRepository.load();
      expect(kanji.allKanji.clear, throwsUnsupportedError);
    });
  });

  test(
    'the travel plan is a snapshot the reader cannot write through',
    () async {
      final travel = await TravelFocusRepository.load();
      await travel.saveFocuses([
        const TravelFocus(scene: TravelSceneId.transport),
      ]);
      await travel.markServed(TravelSceneId.transport, at);

      final plan = travel.plan;
      expect(plan.focuses.clear, throwsUnsupportedError);
      expect(plan.servedOn.clear, throwsUnsupportedError);
      expect(
        () => plan.focuses.add(const TravelFocus(scene: TravelSceneId.hotel)),
        throwsUnsupportedError,
      );

      await travel.saveFocuses([const TravelFocus(scene: TravelSceneId.hotel)]);
      expect(
        plan.focuses.single.scene,
        TravelSceneId.transport,
        reason: 'the handed-out plan moved',
      );
      expect(travel.plan.focuses.single.scene, TravelSceneId.hotel);
    },
  );

  test('the placement draft is a snapshot the reader cannot write '
      'through', () async {
    final kana = await KanaProgressRepository.load();
    final checks = await PlacementCheckRepository.load();
    final row = Lessons.fromKana(kana.allKana).first;
    await checks.save(PlacementCheck.start([row])!);

    final draft = checks.draft;
    expect(draft.pendingKanaIds, isNotEmpty);
    expect(draft.lessonIds.clear, throwsUnsupportedError);
    expect(draft.pendingKanaIds.clear, throwsUnsupportedError);
    expect(draft.records.clear, throwsUnsupportedError);
    expect(draft.hintedKanaIds.clear, throwsUnsupportedError);

    final pendingBefore = List<String>.of(draft.pendingKanaIds);
    await checks.save(
      PlacementCheck.record(
        draft,
        draft.pendingKanaIds.first,
        PlacementOutcome.independent,
      ),
    );
    expect(
      draft.pendingKanaIds,
      pendingBefore,
      reason: 'the handed-out draft moved',
    );
    expect(checks.draft.pendingKanaIds, isNot(pendingBefore));
  });
}
