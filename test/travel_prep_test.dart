// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_prep.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const transportClothing = [
    TravelFocus(scene: TravelSceneId.transport),
    TravelFocus(scene: TravelSceneId.clothing),
  ];

  test('needsKanaBoost is once per calendar day', () {
    var plan = TravelFocusPlan.empty.withFocuses(transportClothing);
    final now = DateTime(2026, 9, 11, 12);
    expect(
      TravelPrep.needsKanaBoost(plan: plan, dueKanaCount: 3, now: now),
      isTrue,
    );
    plan = plan.markKanaBoost(now);
    expect(
      TravelPrep.needsKanaBoost(plan: plan, dueKanaCount: 3, now: now),
      isFalse,
    );
    expect(
      TravelPrep.needsKanaBoost(
        plan: plan,
        dueKanaCount: 3,
        now: DateTime(2026, 9, 12, 8),
      ),
      isTrue,
    );
    expect(
      TravelPrep.needsKanaBoost(plan: plan, dueKanaCount: 0, now: now),
      isFalse,
    );
  });

  test('pickScene rotates two focuses and pauses after both ran today', () {
    var plan = TravelFocusPlan.empty.withFocuses(transportClothing);
    final day1 = DateTime(2026, 9, 11, 12);
    expect(TravelPrep.pickScene(plan, day1), TravelSceneId.transport);
    plan = plan.markServed(TravelSceneId.transport, day1);
    expect(TravelPrep.pickScene(plan, day1), TravelSceneId.clothing);
    plan = plan.markServed(TravelSceneId.clothing, day1);
    expect(TravelPrep.pickScene(plan, day1), isNull);

    final day2 = DateTime(2026, 9, 12, 9);
    expect(TravelPrep.pickScene(plan, day2), TravelSceneId.transport);
  });

  test('pickScene serves restaurant and convenience like the older rooms', () {
    var plan = TravelFocusPlan.empty.withFocuses(const [
      TravelFocus(scene: TravelSceneId.restaurant),
      TravelFocus(scene: TravelSceneId.convenience),
    ]);
    final day = DateTime(2026, 9, 11, 12);
    expect(TravelPrep.pickScene(plan, day), TravelSceneId.restaurant);
    plan = plan.markServed(TravelSceneId.restaurant, day);
    expect(TravelPrep.pickScene(plan, day), TravelSceneId.convenience);
    plan = plan.markServed(TravelSceneId.convenience, day);
    expect(TravelPrep.pickScene(plan, day), isNull);

    plan = TravelFocusPlan.empty.withFocuses(const [
      TravelFocus(scene: TravelSceneId.hotel),
    ]);
    expect(TravelPrep.pickScene(plan, day), TravelSceneId.hotel);
  });

  test(
    'kindFor recalls due first, teaches only when nothing is due, else listen',
    () {
      const aKa = {'あ', 'い', 'う', 'え', 'お', 'か', 'き', 'く', 'け', 'こ'};
      final now = DateTime(2026, 9, 11, 12);
      final unread = TravelScene.inspect(
        scene: TravelSceneId.transport,
        learnedChars: aKa,
        stats: const {},
        now: now,
      );
      expect(unread.unreadReadable, isNotEmpty);
      expect(unread.dueReadable, isEmpty);
      expect(TravelPrep.kindFor(unread), TravelPrepKind.meet);

      final mixed = TravelScene.inspect(
        scene: TravelSceneId.transport,
        learnedChars: aKa,
        stats: {
          'word:えき': WordStat.fromJson({
            's': 1,
            'c': 1,
            'd': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          }),
        },
        now: now,
      );
      expect(mixed.dueReadable.map((i) => i.progressId), contains('word:えき'));
      expect(
        mixed.unreadReadable.map((i) => i.progressId),
        contains('word:ここ'),
      );
      expect(TravelPrep.kindFor(mixed), TravelPrepKind.recall);

      final newbie = TravelScene.inspect(
        scene: TravelSceneId.transport,
        learnedChars: const {},
        stats: const {},
      );
      expect(TravelPrep.kindFor(newbie), TravelPrepKind.learnKana);
    },
  );

  test('already-seen due items recall; seen with no due listen', () {
    const aKa = {'あ', 'い', 'う', 'え', 'お', 'か', 'き', 'く', 'け', 'こ'};
    final now = DateTime(2026, 9, 11, 12);
    final unread = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      stats: const {},
      now: now,
    );
    final seenStats = {
      for (final item in unread.readable)
        item.progressId: WordStat.fromJson({
          's': 1,
          'c': 1,
          'd': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        }),
    };
    final due = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      stats: seenStats,
      now: now,
    );
    expect(due.unreadReadable, isEmpty);
    expect(due.dueReadable, isNotEmpty);
    expect(TravelPrep.kindFor(due), TravelPrepKind.recall);

    final futureDue = {
      for (final item in unread.readable)
        item.progressId: WordStat.fromJson({
          's': 1,
          'c': 1,
          'd': now.add(const Duration(days: 3)).millisecondsSinceEpoch,
        }),
    };
    final listen = TravelScene.inspect(
      scene: TravelSceneId.transport,
      learnedChars: aKa,
      stats: futureDue,
      now: now,
    );
    expect(listen.dueReadable, isEmpty);
    expect(listen.seenReadable, isNotEmpty);
    expect(TravelPrep.kindFor(listen), TravelPrepKind.listen);
  });

  test(
    'seven Home days continue both scenes through real repositories',
    () async {
      final kana = await KanaProgressRepository.load();
      final words = await WordProgressRepository.load();
      await kana.markUnitLearned('hira_row_0');
      await kana.markUnitLearned('hira_row_1');
      final a = kana
          .gojuonForScript(KanaScript.hiragana)
          .firstWhere((k) => k.character == 'あ');
      final start = DateTime(2026, 9, 11, 12);
      await kana.recordAnswer(
        a,
        correct: false,
        at: start.subtract(const Duration(hours: 1)),
      );
      var plan = TravelFocusPlan.empty.withFocuses([
        TravelFocus(
          scene: TravelSceneId.transport,
          date: DateTime(2026, 9, 18),
        ),
        TravelFocus(scene: TravelSceneId.clothing, date: DateTime(2026, 9, 18)),
      ]);

      final served = <TravelSceneId>{};
      final beforeSwitch = Map<String, int>.from(
        words.stats.map((id, s) => MapEntry(id, s.seenCount)),
      );

      for (var day = 0; day < 7; day++) {
        final now = DateTime(2026, 9, 11 + day, 12);
        final learnedChars = StudySet.learned(kana)
            .map((k) => k.character)
            .toSet();
        Map<TravelSceneId, TravelSceneView> views() => {
          for (final focus in plan.focuses)
            focus.scene: TravelScene.inspect(
              scene: focus.scene,
              learnedChars: learnedChars,
              stats: words.stats,
              now: now,
            ),
        };

        var step = Guidance.nextStep(
          kana,
          now: now,
          travelPlan: plan,
          travelViews: views(),
        );
        if (step.target == GuidanceTarget.daily) {
          await kana.recordAnswer(a, correct: true, at: now, latencyMs: 400);
          plan = plan.markKanaBoost(now);
          step = Guidance.nextStep(
            kana,
            now: now,
            travelPlan: plan,
            travelViews: views(),
          );
        }
        expect(step.target, isNot(GuidanceTarget.lessons));
        expect(step.target, isNot(GuidanceTarget.rest));
        expect(step.scene, isNotNull);
        final scene = step.scene!;
        served.add(scene);
        final view = views()[scene]!;
        expect(view.readable, isNotEmpty, reason: 'day $day ${scene.name}');
        if (step.target == GuidanceTarget.travelMeet) {
          expect(view.unreadReadable, isNotEmpty);
          await words.introduce(view.unreadReadable.first.progressId, at: now);
        } else if (step.target == GuidanceTarget.travelRecall) {
          expect(view.dueReadable, isNotEmpty);
          await words.recordAnswer(
            view.dueReadable.first.progressId,
            correct: true,
            at: now,
          );
        } else if (step.target == GuidanceTarget.travelListen) {
          expect(view.seenReadable, isNotEmpty);
          await words.recordAnswer(
            view.seenReadable.first.progressId,
            correct: true,
            at: now,
          );
        } else {
          fail('day $day used ${step.target} instead of a scene step');
        }
        plan = plan.markServed(scene, now);
      }

      expect(served, contains(TravelSceneId.transport));
      expect(served, contains(TravelSceneId.clothing));

      final beforeClear = Map.of(words.stats);
      plan = plan.cleared();
      expect(plan.isActive, isFalse);
      expect(words.stats.keys, beforeClear.keys);
      for (final id in beforeClear.keys) {
        expect(words.stats[id]!.seenCount, beforeClear[id]!.seenCount);
      }
      expect(
        words.stats.values.any((s) => s.seenCount > 0),
        isTrue,
        reason: 'seven days must have written 詞と句 progress',
      );
      expect(beforeSwitch.values.every((n) => n == 0), isTrue);
    },
  );

  test('dates before, on, and after still have a next step', () async {
    final kana = await KanaProgressRepository.load();
    await kana.markUnitLearned('hira_row_0');
    await kana.markUnitLearned('hira_row_1');
    final plan = TravelFocusPlan.empty.withFocuses([
      TravelFocus(scene: TravelSceneId.transport, date: DateTime(2026, 9, 18)),
    ]);
    for (final now in [
      DateTime(2026, 9, 11, 12),
      DateTime(2026, 9, 18, 12),
      DateTime(2026, 9, 25, 12),
    ]) {
      final learnedChars = StudySet.learned(kana)
          .map((k) => k.character)
          .toSet();
      final step = Guidance.nextStep(
        kana,
        now: now,
        travelPlan: plan,
        travelViews: {
          TravelSceneId.transport: TravelScene.inspect(
            scene: TravelSceneId.transport,
            learnedChars: learnedChars,
            stats: const {},
            now: now,
          ),
        },
      );
      expect(step.target, GuidanceTarget.travelMeet, reason: now.toString());
      expect(step.scene, TravelSceneId.transport);
    }
  });
}
