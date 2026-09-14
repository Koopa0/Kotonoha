// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/reading/reading_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

const _inu = Word(kana: 'いぬ', romaji: 'inu', meaning: '狗');
const _yama = Word(kana: 'やま', romaji: 'yama', meaning: '山');
const _sora = Phrase(kana: 'そらが あおい', romaji: 'sora ga aoi', meaning: '天空是藍的');

/// A [Random] whose every draw is 0 — [KotenShare.pick] always surfaces the
/// first line, so the earned gate is the only thing under test.
class _AlwaysShare implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

/// Polls the real event loop until [done] — FakePreferencesService parks
/// each write on a zero-length timer, so a bare await never suffices.
Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the reading ViewModel's contract without pumping a widget: the
/// evidence a self-grade writes, the 「もう一回」 gate, the close, and the
/// persistence owner's failure / retry path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noon = DateTime(2026, 9, 11, 12);

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  Future<
    ({
      ReadingViewModel vm,
      WordProgressRepository words,
      KanaProgressRepository kana,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm(
    List<ReadingItem> items, {
    Set<String> alreadyTransferredIds = const {},
    Random? rng,
    WordProgressRepository? words,
    ProgressPersistenceController? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final resolvedWords = words ?? await WordProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final vm = ReadingViewModel(
      items: items,
      words: resolvedWords,
      kana: kana,
      persistence: persistence ?? owner(),
      analytics: log,
      sessionId: 's1',
      alreadyTransferredIds: alreadyTransferredIds,
      clock: () => noon,
      rng: rng,
    );
    return (vm: vm, words: resolvedWords, kana: kana, log: log);
  }

  test('starts on the first item, unrevealed', () async {
    final t = await makeVm(const [_inu, _yama]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, _inu);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.unpromptedCommit, isFalse);
    expect(t.vm.correctCount, 0);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isLastItem, isFalse);
    t.vm.dispose();
  });

  test(
    'reveal exposes the reading and keeps the commit; grade waits',
    () async {
      final t = await makeVm(const [_inu]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);

      t.vm.grade(correct: true); // before reveal — ignored
      expect(await t.log.all(), isEmpty);
      expect(t.words.statForItem('word:いぬ').isSeen, isFalse);

      t.vm.reveal(unpromptedCommit: true);
      expect(t.vm.isRevealed, isTrue);
      expect(t.vm.unpromptedCommit, isTrue);
      expect(notifications, 1);
      // Reveal alone writes nothing — the schedule moves only on the grade.
      expect(t.words.statForItem('word:いぬ').correctCount, 0);
      expect(t.words.statForItem('word:いぬ').isSeen, isFalse);

      t.vm.reveal(unpromptedCommit: false); // a second reveal cannot demote
      expect(t.vm.unpromptedCommit, isTrue);
      expect(notifications, 1);
      t.vm.dispose();
    },
  );

  test(
    'unprompted correct climbs and logs an unprompted reading attempt',
    () async {
      final t = await makeVm(const [_inu]);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);

      final stat = t.words.statForItem('word:いぬ');
      expect(stat.correctCount, 1);
      expect(stat.srsLevel, 1);
      expect(stat.lastReviewedAt, noon);
      expect(t.vm.correctCount, 1);
      expect(t.vm.isFinished, isTrue);

      final attempt = (await t.log.all()).single;
      expect(attempt.mode, PracticeMode.reading.name);
      expect(attempt.itemType, ItemType.word);
      expect(attempt.itemId, 'いぬ');
      expect(attempt.correct, isTrue);
      expect(attempt.rtMs, 0);
      expect(attempt.sessionId, 's1');
      expect(attempt.meta[AttemptMeta.prompted], isFalse);
      expect(attempt.meta['romaji'], 'inu');
      t.vm.dispose();
    },
  );

  test(
    'prompted correct on a new item keeps intake without mastering',
    () async {
      final t = await makeVm(const [_sora]);
      t.vm.reveal(unpromptedCommit: false);
      t.vm.grade(correct: true);

      final stat = t.words.statForItem(_sora.progressId);
      expect(stat.isSeen, isTrue);
      expect(stat.correctCount, 0);
      expect(stat.srsLevel, 0);
      expect(t.vm.correctCount, 1);
      final attempt = (await t.log.all()).single;
      expect(attempt.itemId, 'そらが あおい');
      expect(attempt.correct, isTrue);
      expect(attempt.meta[AttemptMeta.prompted], isTrue);
      t.vm.dispose();
    },
  );

  test(
    'prompted correct on a seen item writes nothing to the schedule',
    () async {
      final t = await makeVm(const [_inu]);
      await t.words.introduce('word:いぬ', at: noon);
      final before = t.words.statForItem('word:いぬ');
      expect(before.srsLevel, 1);

      t.vm.reveal(unpromptedCommit: false);
      t.vm.grade(correct: true);

      final after = t.words.statForItem('word:いぬ');
      expect(after.srsLevel, 1);
      expect(after.correctCount, before.correctCount);
      expect(after.dueAt, before.dueAt);
      expect((await t.log.all()).single.meta[AttemptMeta.prompted], isTrue);
      t.vm.dispose();
    },
  );

  test('a miss always resets, prompted or not', () async {
    for (final unprompted in [true, false]) {
      final t = await makeVm(const [_inu]);
      await t.words.introduce('word:いぬ', at: noon);
      t.vm.reveal(unpromptedCommit: unprompted);
      t.vm.grade(correct: false);

      final stat = t.words.statForItem('word:いぬ');
      expect(stat.srsLevel, 0);
      expect(stat.wrongCount, 1);
      expect(t.vm.correctCount, 0);
      final attempt = (await t.log.all()).single;
      expect(attempt.correct, isFalse);
      expect(attempt.meta[AttemptMeta.prompted], !unprompted);
      t.vm.dispose();
    }
  });

  group('もう一回 grind gate', () {
    test('wrap same id unprompted-correct does not climb', () async {
      final t = await makeVm(const [_inu], alreadyTransferredIds: {'word:いぬ'});
      await t.words.introduce('word:いぬ', at: noon);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.words.statForItem('word:いぬ').srsLevel, 1);
      expect(t.words.statForItem('word:いぬ').correctCount, 1);
      // Still reading evidence for analytics — only the schedule is gated.
      expect((await t.log.all()).single.correct, isTrue);
      t.vm.dispose();
    });

    test('wrap miss still resets', () async {
      final t = await makeVm(const [_inu], alreadyTransferredIds: {'word:いぬ'});
      await t.words.introduce('word:いぬ', at: noon);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: false);
      expect(t.words.statForItem('word:いぬ').srsLevel, 0);
      t.vm.dispose();
    });

    test('uncovered id in the same grind still climbs', () async {
      final t = await makeVm(
        const [_inu, _yama],
        alreadyTransferredIds: {'word:いぬ'},
      );
      await t.words.introduce('word:いぬ', at: noon);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.words.statForItem('word:いぬ').srsLevel, 1);
      expect(t.words.statForItem('word:やま').srsLevel, 1);
      t.vm.dispose();
    });
  });

  test('advances through items, resets the reveal, then closes', () async {
    final t = await makeVm(const [_inu, _yama, _sora]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    t.vm.reveal(unpromptedCommit: true);
    t.vm.grade(correct: true);
    expect(t.vm.index, 1);
    expect(t.vm.current, _yama);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.unpromptedCommit, isFalse);
    expect(t.vm.isFinished, isFalse);

    t.vm.reveal(unpromptedCommit: false);
    t.vm.grade(correct: false);
    expect(t.vm.index, 2);
    expect(t.vm.isLastItem, isTrue);

    t.vm.reveal(unpromptedCommit: true);
    t.vm.grade(correct: true);
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.correctCount, 2);
    expect(t.vm.index, 2);
    expect(notifications, 6);

    // Nothing after the close can write.
    t.vm.grade(correct: false);
    t.vm.reveal(unpromptedCommit: true);
    expect(notifications, 6);
    expect((await t.log.all()).length, 3);
    expect(t.words.statForItem(_sora.progressId).srsLevel, 1);
    t.vm.dispose();
  });

  group('classical 余韻 at the close', () {
    test('stays null for a learner under the earned gate', () async {
      final t = await makeVm(const [_inu], rng: _AlwaysShare());
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.vm.isFinished, isTrue);
      expect(t.vm.share, isNull);
      t.vm.dispose();
    });

    test('reads the met-kana count from the kana owner', () async {
      final t = await makeVm(const [_inu], rng: _AlwaysShare());
      for (final k in kHiraganaGojuon.take(16)) {
        await t.kana.recordAnswer(k, correct: true, at: noon);
      }
      expect(t.kana.seenCount, 16);
      expect(t.vm.share, isNull, reason: 'picked at the close, not before');
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.vm.share, isNotNull);
      t.vm.dispose();
    });
  });

  test(
    'a failed save surfaces on the owner and retry flushes without re-climbing',
    () async {
      final fake = FakePreferencesService();
      final words = await WordProgressRepository.load(fake);
      await words.introduce('word:いぬ', at: noon);
      expect(words.statForItem('word:いぬ').srsLevel, 1);
      fake.failWrites.add('word_stats_v1');
      final persist = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: words.flushPending,
      );
      final t = await makeVm(const [_inu], words: words, persistence: persist);

      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      // The in-memory answer lands at once; the disk outcome is observed later.
      expect(words.statForItem('word:いぬ').srsLevel, 2);
      expect(words.statForItem('word:いぬ').correctCount, 2);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(words.statForItem('word:いぬ').srsLevel, 2);
      expect(words.statForItem('word:いぬ').correctCount, 2);
      final reloaded = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForItem('word:いぬ').srsLevel, 2);
      t.vm.dispose();
    },
  );
}
