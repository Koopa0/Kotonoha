// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/ferry/ferry_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

const _eki = Word(kana: 'えき', romaji: 'eki', meaning: '車站');
const _koko = Word(kana: 'ここ', romaji: 'koko', meaning: '這裡');

/// A [Random] whose every draw is 0 — the classical 余韻 always surfaces
/// once the earned gate is met.
class _AlwaysShare implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the ferry ViewModel's contract without pumping a widget or any
/// speech service: the three beats, the read-back clock, introduce vs.
/// mark-introduced, the close, and the persistence owner's failure /
/// retry path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime(2026, 9, 10, 12);

  setUp(() => now = DateTime(2026, 9, 10, 12));

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  Future<
    ({
      FerryViewModel vm,
      WordProgressRepository words,
      KanaProgressRepository kana,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm(
    List<Word> items, {
    Random? rng,
    WordProgressRepository? words,
    ProgressPersistenceController? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final resolvedWords = words ?? await WordProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final vm = FerryViewModel(
      items: items,
      words: resolvedWords,
      kana: kana,
      persistence: persistence ?? owner(),
      analytics: log,
      sessionId: 's1',
      clock: () => now,
      rng: rng,
    );
    return (vm: vm, words: resolvedWords, kana: kana, log: log);
  }

  void ferry(FerryViewModel vm, {required bool correct}) {
    vm.showText();
    vm.readSelf();
    vm.grade(correct: correct);
  }

  test('opens on the hear beat with the kana hidden', () async {
    final t = await makeVm(const [_eki, _koko]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, _eki);
    expect(t.vm.beat, FerryBeat.hear);
    expect(t.vm.showsKana, isFalse);
    expect(t.vm.correctCount, 0);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isLastItem, isFalse);
    t.vm.dispose();
  });

  test(
    'hear → see → read-back → 讀對了 logs a ferry attempt and encodes',
    () async {
      final t = await makeVm(const [_eki, _koko]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);

      t.vm.showText();
      expect(t.vm.beat, FerryBeat.see);
      expect(t.vm.showsKana, isTrue);
      now = now.add(const Duration(seconds: 3)); // the see-beat dwell
      t.vm.readSelf();
      expect(t.vm.beat, FerryBeat.readback);
      expect(t.vm.showsKana, isTrue);
      now = now.add(const Duration(milliseconds: 800)); // the read-back
      t.vm.grade(correct: true);

      final a = (await t.log.all()).single;
      expect(a.mode, PracticeMode.ferry.name);
      expect(a.itemType, ItemType.word);
      expect(a.itemId, 'えき');
      expect(a.correct, isTrue);
      expect(a.rtMs, 800);
      expect(a.sessionId, 's1');
      expect(a.meta, {'romaji': 'eki'});
      final stat = t.words.statForItem(_eki.progressId);
      expect(stat.isSeen, isTrue);
      expect(stat.srsLevel, 1);
      expect(stat.correctCount, 1);
      expect(stat.lastReviewedAt, now);

      expect(t.vm.correctCount, 1);
      expect(t.vm.index, 1);
      expect(t.vm.current, _koko);
      expect(t.vm.beat, FerryBeat.hear);
      expect(t.vm.showsKana, isFalse);
      expect(t.vm.isLastItem, isTrue);
      expect(notifications, 3);
      t.vm.dispose();
    },
  );

  group('introduce, never review', () {
    test('a first 讀不出來 marks introduced without encode credit', () async {
      final t = await makeVm(const [_eki]);
      ferry(t.vm, correct: false);
      final stat = t.words.statForItem(_eki.progressId);
      expect(stat.isSeen, isTrue);
      expect(stat.correctCount, 0);
      expect(stat.wrongCount, 0);
      expect(stat.srsLevel, 0);
      expect(t.vm.correctCount, 0);
      final a = (await t.log.all()).single;
      expect(a.correct, isFalse);
      t.vm.dispose();
    });

    test(
      'a seen miss writes nothing; a seen success adds no second encode',
      () async {
        final t = await makeVm(const [_eki, _koko]);
        await t.words.introduce(_eki.progressId, at: now);
        await t.words.introduce(_koko.progressId, at: now);

        ferry(t.vm, correct: false);
        var stat = t.words.statForItem(_eki.progressId);
        expect(stat.srsLevel, 1);
        expect(stat.correctCount, 1);
        expect(stat.wrongCount, 0);

        ferry(t.vm, correct: true);
        stat = t.words.statForItem(_koko.progressId);
        expect(stat.srsLevel, 1);
        expect(stat.correctCount, 1);
        // Both are still ferry attempts — exposure is logged, not scheduled.
        expect((await t.log.all()).map((a) => a.correct), [false, true]);
        t.vm.dispose();
      },
    );
  });

  test('beats only advance in order', () async {
    final t = await makeVm(const [_eki]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    // Off the read-back beat a grade is not an exit.
    t.vm.readSelf();
    t.vm.grade(correct: true);
    expect(t.vm.beat, FerryBeat.hear);
    expect(notifications, 0);

    t.vm.showText();
    t.vm.showText(); // already seen — silent
    t.vm.grade(correct: true);
    expect(t.vm.beat, FerryBeat.see);
    expect(notifications, 1);

    t.vm.readSelf();
    t.vm.showText();
    t.vm.readSelf();
    expect(t.vm.beat, FerryBeat.readback);
    expect(notifications, 2);
    expect(await t.log.all(), isEmpty);
    expect(t.words.statForItem(_eki.progressId).isSeen, isFalse);
    t.vm.dispose();
  });

  group('the close', () {
    test('finishes on the last word and ignores anything after', () async {
      final t = await makeVm(const [_eki]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      ferry(t.vm, correct: true);
      expect(t.vm.isFinished, isTrue);
      expect(t.vm.index, 0);
      expect(t.vm.correctCount, 1);
      expect(notifications, 3);

      ferry(t.vm, correct: false);
      expect(t.vm.beat, FerryBeat.readback);
      expect(notifications, 3);
      expect(await t.log.all(), hasLength(1));
      expect(t.words.statForItem(_eki.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('the classical 余韻 waits on the kana owner\'s earned gate', () async {
      final fresh = await makeVm(const [_eki], rng: _AlwaysShare());
      ferry(fresh.vm, correct: true);
      expect(fresh.vm.isFinished, isTrue);
      expect(fresh.vm.share, isNull);
      fresh.vm.dispose();

      final earned = await makeVm(const [_eki], rng: _AlwaysShare());
      for (final k in kHiraganaGojuon.take(16)) {
        await earned.kana.recordAnswer(k, correct: true, at: now);
      }
      ferry(earned.vm, correct: true);
      expect(earned.vm.share, isNotNull);
      earned.vm.dispose();
    });
  });

  test(
    'a failed save surfaces on the owner and retry flushes without re-encoding',
    () async {
      final fake = FakePreferencesService();
      final words = await WordProgressRepository.load(fake);
      fake.failWrites.add('word_stats_v1');
      final persist = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: words.flushPending,
      );
      final t = await makeVm(const [_eki], words: words, persistence: persist);

      ferry(t.vm, correct: true);
      expect(words.statForItem('word:えき').srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(words.statForItem('word:えき').srsLevel, 1);
      expect(words.statForItem('word:えき').correctCount, 1);
      final reloaded = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForItem('word:えき').srsLevel, 1);
      t.vm.dispose();
    },
  );
}
