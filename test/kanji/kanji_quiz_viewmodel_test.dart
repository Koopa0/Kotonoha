// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/kanji_mode.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_viewmodel.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';

// A compound whose reading cannot be assembled character by character.
const _gakkouExample = KanjiPhrase(
  segments: [
    RubySegment(text: '学校', furigana: 'がっこう'),
    RubySegment(text: 'へ'),
    RubySegment(text: '行', furigana: 'い'),
    RubySegment(text: 'く'),
  ],
  romaji: 'gakkou e iku',
  meaning: '去學校',
);
const _gakkou = KanjiUnit(
  written: '学校',
  reading: 'がっこう',
  example: _gakkouExample,
);

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the 漢字の声 ViewModel's contract without pumping a widget or any
/// speech service: the teach / recall route, the honest encode, the graded
/// untimed recall and where a legal alternate lands, the close, and the
/// persistence owner's failure / retry path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 10, 12);

  final hi = kKanjiUnits.singleWhere((u) => u.id == 'unit:日#ひ');
  final nichi = kKanjiUnits.singleWhere((u) => u.id == 'unit:日#にち');
  final toshi = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#とし');
  final nen = kKanjiUnits.singleWhere((u) => u.id == 'unit:年#ねん');

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  Future<
    ({
      KanjiQuizViewModel vm,
      KanjiReadingRepository kanji,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm(
    List<KanjiUnit> units, {
    Iterable<KanjiUnit> seen = const [],
    int seenLevel = 3,
    KanjiReadingRepository? kanji,
    ProgressPersistenceController? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final resolvedKanji = kanji ?? await KanjiReadingRepository.load();
    for (final u in seen) {
      for (var i = 0; i < seenLevel; i++) {
        await resolvedKanji.recordAnswer(u.id, correct: true, at: now);
      }
    }
    final log = InMemoryAnalyticsLog();
    final vm = KanjiQuizViewModel(
      units: units,
      kanji: resolvedKanji,
      persistence: persistence ?? owner(),
      analytics: log,
      sessionId: 's1',
      clock: () => now,
      rng: Random(0),
    );
    return (vm: vm, kanji: resolvedKanji, log: log);
  }

  int optionOf(KanjiQuizViewModel vm, String reading) {
    final i = vm.question!.options.indexOf(reading);
    expect(i, isNonNegative, reason: '$reading is not offered');
    return i;
  }

  group('teach', () {
    test(
      'a never-met unit is taught: encode, teach attempt, no score',
      () async {
        final t = await makeVm(const [_gakkou]);
        expect(t.vm.isTeach, isTrue);
        expect(t.vm.question, isNull);
        expect(t.vm.isAnswered, isFalse);
        expect(t.vm.confirmedReading, isNull);
        var notifications = 0;
        t.vm.addListener(() => notifications++);

        t.vm.teachNext();
        final stat = t.kanji.statForUnit(_gakkou.id);
        expect(stat.isSeen, isTrue);
        expect(stat.seenCount, 1);
        expect(stat.srsLevel, 1);
        final a = (await t.log.all()).single;
        expect(a.mode, KanjiMode.kanjiReading.name);
        expect(a.itemType, ItemType.kanji);
        expect(a.itemId, _gakkou.id);
        expect(a.correct, isTrue);
        expect(a.rtMs, 0); // the kanji track is untimed
        expect(a.sessionId, 's1');
        expect(a.meta['beat'], 'teach');
        expect(a.meta['written'], '学校');
        expect(a.meta['reading'], 'がっこう');
        expect(a.meta.containsKey('chosen'), isFalse);
        expect(a.meta.containsKey('scored'), isFalse);
        expect(t.vm.gradedCount, 0);
        expect(t.vm.correctCount, 0);
        expect(t.vm.isFinished, isTrue);
        expect(notifications, 1);
        t.vm.dispose();
      },
    );

    test('the route is captured on entering each unit', () async {
      final t = await makeVm([_gakkou, hi], seen: [hi]);
      expect(t.vm.isTeach, isTrue);
      t.vm.teachNext();
      expect(t.vm.index, 1);
      expect(t.vm.current, hi);
      expect(t.vm.isTeach, isFalse);
      expect(t.vm.question, isNotNull);
      expect(t.vm.question!.unit, hi);
      final options = t.vm.question!.options;
      expect(options, contains('ひ'));
      expect(options.toSet(), hasLength(options.length));
      expect(t.vm.isLastItem, isTrue);
      t.vm.dispose();
    });
  });

  group('recall', () {
    test('the scheduled reading is credited and confirmed', () async {
      final t = await makeVm([hi, nichi], seen: [hi, nichi]);
      expect(t.vm.isTeach, isFalse);
      final before = t.kanji.statForUnit(hi.id);
      var notifications = 0;
      t.vm.addListener(() => notifications++);

      final i = optionOf(t.vm, 'ひ');
      expect(t.vm.acceptsOption(i), isTrue);
      expect(t.vm.acceptsOption(optionOf(t.vm, 'にち')), isFalse);
      t.vm.answer(i);
      expect(t.vm.picked, i);
      expect(t.vm.isAnswered, isTrue);
      expect(t.vm.confirmedReading, 'ひ');
      expect(t.vm.gradedCount, 1);
      expect(t.vm.correctCount, 1);
      expect(notifications, 1);

      final after = t.kanji.statForUnit(hi.id);
      expect(after.srsLevel, greaterThan(before.srsLevel));
      expect(after.correctCount, before.correctCount + 1);
      expect(after.wrongCount, before.wrongCount);
      final a = (await t.log.all()).single;
      expect(a.itemId, hi.id);
      expect(a.correct, isTrue);
      expect(a.meta['beat'], 'recall');
      expect(a.meta['chosen'], 'ひ');
      expect(a.meta.containsKey('scheduled'), isFalse);
      expect(a.meta.containsKey('scored'), isFalse);

      t.vm.advance();
      expect(t.vm.index, 1);
      expect(t.vm.isAnswered, isFalse);
      expect(t.vm.confirmedReading, isNull);
      expect(notifications, 2);
      t.vm.dispose();
    });

    test('the other taught reading of the run is a real miss', () async {
      final t = await makeVm([hi, nichi], seen: [hi, nichi]);
      t.vm.answer(optionOf(t.vm, 'にち'));
      expect(t.vm.confirmedReading, 'ひ');
      expect(t.vm.gradedCount, 1);
      expect(t.vm.correctCount, 0);
      final after = t.kanji.statForUnit(hi.id);
      expect(after.srsLevel, 0);
      expect(after.wrongCount, 1);
      expect(t.kanji.statForUnit(nichi.id).srsLevel, 3);
      final a = (await t.log.all()).single;
      expect(a.itemId, hi.id);
      expect(a.correct, isFalse);
      expect(a.meta['chosen'], 'にち');
      t.vm.dispose();
    });

    test(
      'a legal alternate credits its seen sibling, never the scheduled unit',
      () async {
        final t = await makeVm([toshi, nen], seen: [toshi, nen]);
        expect(t.vm.current, toshi);
        final toshiBefore = t.kanji.statForUnit(toshi.id);
        final nenBefore = t.kanji.statForUnit(nen.id);

        final i = optionOf(t.vm, 'ねん');
        expect(t.vm.acceptsOption(i), isTrue);
        t.vm.answer(i);
        expect(t.vm.confirmedReading, 'ねん');
        expect(t.vm.correctCount, 1);

        final toshiAfter = t.kanji.statForUnit(toshi.id);
        expect(toshiAfter.srsLevel, toshiBefore.srsLevel);
        expect(toshiAfter.correctCount, toshiBefore.correctCount);
        expect(toshiAfter.dueAt, toshiBefore.dueAt);
        expect(
          t.kanji.statForUnit(nen.id).correctCount,
          nenBefore.correctCount + 1,
        );
        final a = (await t.log.all()).single;
        expect(a.itemId, nen.id);
        expect(a.correct, isTrue);
        expect(a.meta['reading'], 'ねん');
        expect(a.meta['chosen'], 'ねん');
        expect(a.meta['scheduled'], toshi.id);
        expect(a.meta.containsKey('scored'), isFalse);
        t.vm.dispose();
      },
    );

    test('a legal alternate with an unseen sibling moves no Leitner', () async {
      final t = await makeVm([toshi, nen], seen: [toshi]);
      final before = t.kanji.stats;
      t.vm.answer(optionOf(t.vm, 'ねん'));
      expect(t.vm.confirmedReading, 'ねん');
      expect(t.vm.correctCount, 1);
      expect(t.kanji.stats, before);
      final a = (await t.log.all()).single;
      expect(a.itemId, nen.id);
      expect(a.correct, isTrue);
      expect(a.meta['scheduled'], toshi.id);
      expect(a.meta['scored'], isFalse);
      t.vm.dispose();
    });
  });

  test('commands off their beat are ignored', () async {
    final t = await makeVm([_gakkou, hi], seen: [hi]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    // Teach beat: no answer, no advance.
    t.vm.answer(0);
    t.vm.advance();
    expect(t.vm.index, 0);
    expect(notifications, 0);

    t.vm.teachNext();
    expect(t.vm.index, 1);
    // Recall beat: no teach, no advance before a choice, one choice only.
    t.vm.teachNext();
    t.vm.advance();
    expect(t.vm.isAnswered, isFalse);
    final first = optionOf(t.vm, 'ひ');
    t.vm.answer(first);
    t.vm.answer((first + 1) % 4);
    expect(t.vm.picked, first);
    expect(notifications, 2);
    expect(await t.log.all(), hasLength(2));
    expect(t.kanji.statForUnit(hi.id).correctCount, 4);
    t.vm.dispose();
  });

  test('finishes after the last unit and ignores anything after', () async {
    final t = await makeVm([hi], seen: [hi]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.answer(optionOf(t.vm, 'ひ'));
    t.vm.advance();
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.index, 0);
    expect(notifications, 2);

    t.vm.answer(0);
    t.vm.advance();
    t.vm.teachNext();
    expect(notifications, 2);
    expect(await t.log.all(), hasLength(1));
    t.vm.dispose();
  });

  test(
    'a failed save surfaces on the owner and retry flushes without re-climbing',
    () async {
      final fake = FakePreferencesService();
      final kanji = await KanjiReadingRepository.load(fake);
      final persist = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: kanji.flushPending,
        wordFlush: () async {},
      );
      final t = await makeVm(
        const [_gakkou],
        kanji: kanji,
        persistence: persist,
      );
      fake.failWrites.add('kanji_units_v1');

      t.vm.teachNext();
      expect(kanji.statForUnit(_gakkou.id).srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(kanji.statForUnit(_gakkou.id).srsLevel, 1);
      expect(kanji.statForUnit(_gakkou.id).seenCount, 1);
      final reloaded = await KanjiReadingRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForUnit(_gakkou.id).srsLevel, 1);
      t.vm.dispose();
    },
  );
}
