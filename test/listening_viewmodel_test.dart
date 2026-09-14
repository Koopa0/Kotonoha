// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/listening/listening_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

const _station = Phrase(
  kana: 'えきは どこ',
  romaji: 'eki wa doko',
  meaning: '車站在哪裡',
);
const _ticket = Word(kana: 'きっぷ', romaji: 'kippu', meaning: '車票');
const _kimi = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');

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

/// Reads the listening ViewModel's contract without pumping a widget or
/// any speech service: what a reported play means (blind / prompted /
/// nothing), the reaction clock, the 「もう一回」 gate, the close, and the
/// persistence owner's failure / retry path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var now = DateTime(2026, 9, 10, 12);
  var elapsed = 0;

  setUp(() {
    now = DateTime(2026, 9, 10, 12);
    elapsed = 0;
  });

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  Future<
    ({
      ListeningViewModel vm,
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
    final vm = ListeningViewModel(
      items: items,
      words: resolvedWords,
      kana: kana,
      persistence: persistence ?? owner(),
      analytics: log,
      sessionId: 's1',
      alreadyTransferredIds: alreadyTransferredIds,
      clock: () => now,
      monotonicMs: () => elapsed,
      rng: rng,
    );
    return (vm: vm, words: resolvedWords, kana: kana, log: log);
  }

  test('starts unrevealed and unheard', () async {
    final t = await makeVm(const [_station, _ticket]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, _station);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.blindHeard, isFalse);
    expect(t.vm.promptedHeard, isFalse);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isLastItem, isFalse);
    t.vm.dispose();
  });

  test(
    'blind hear → reveal → heard writes a timed, scored attempt and SRS',
    () async {
      final t = await makeVm(const [_station, _ticket]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);

      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      expect(t.vm.blindHeard, isTrue);
      expect(t.vm.promptedHeard, isFalse);
      expect(notifications, 1);

      t.vm.reveal();
      elapsed = 4000;
      now = now.add(const Duration(seconds: 4));
      t.vm.gradeBlind(correct: true);

      final logged = await t.log.all();
      expect(logged, hasLength(1));
      final a = logged.single;
      expect(a.mode, PracticeMode.listening.name);
      expect(a.itemType, ItemType.word);
      expect(a.itemId, 'えきは どこ');
      expect(a.correct, isTrue);
      expect(a.rtMs, 4000);
      expect(a.sessionId, 's1');
      expect(a.meta[AttemptMeta.heard], isTrue);
      expect(a.meta[AttemptMeta.prompted], isFalse);
      expect(a.meta[AttemptMeta.scored], isTrue);
      expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.played.name);
      expect(a.meta['romaji'], 'eki wa doko');
      final stat = t.words.statForItem(_station.progressId);
      expect(stat.isSeen, isTrue);
      expect(stat.correctCount, 1);
      expect(stat.srsLevel, 1);
      expect(stat.lastReviewedAt, now);

      expect(t.vm.index, 1);
      expect(t.vm.isRevealed, isFalse);
      expect(t.vm.blindHeard, isFalse);
      expect(notifications, 3);
      t.vm.dispose();
    },
  );

  test('a blind miss resets and is logged as a scored wrong', () async {
    final t = await makeVm(const [_station]);
    await t.words.recordAnswer(_station.progressId, correct: true, at: now);
    t.vm.noteHeard(itemIndex: 0, startedBlind: true);
    t.vm.reveal();
    t.vm.gradeBlind(correct: false);
    final stat = t.words.statForItem(_station.progressId);
    expect(stat.srsLevel, 0);
    expect(stat.wrongCount, 1);
    final a = (await t.log.all()).single;
    expect(a.correct, isFalse);
    expect(a.meta[AttemptMeta.scored], isTrue);
    expect(a.meta[AttemptMeta.prompted], isFalse);
    t.vm.dispose();
  });

  group('what a completed play means', () {
    test(
      'a play that started blind but finished after reveal is prompted',
      () async {
        final t = await makeVm(const [_station]);
        t.vm.reveal();
        t.vm.noteHeard(itemIndex: 0, startedBlind: true);
        expect(t.vm.blindHeard, isFalse);
        expect(t.vm.promptedHeard, isTrue);
        t.vm.dispose();
      },
    );

    test('a replay after reveal is prompted', () async {
      final t = await makeVm(const [_station]);
      t.vm.reveal();
      t.vm.noteHeard(itemIndex: 0, startedBlind: false);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.promptedHeard, isTrue);
      t.vm.dispose();
    });

    test('a completion for another item is stale and ignored', () async {
      final t = await makeVm(const [_station, _ticket]);
      t.vm.noteHeard(itemIndex: 1, startedBlind: true);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.promptedHeard, isFalse);

      t.vm.reveal();
      t.vm.skipUnheard();
      expect(t.vm.index, 1);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true); // the old item, late
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.promptedHeard, isFalse);
      t.vm.dispose();
    });

    test('a prompted hear cannot backfill a blind one', () async {
      final t = await makeVm(const [_station]);
      t.vm.reveal();
      t.vm.noteHeard(itemIndex: 0, startedBlind: false);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.promptedHeard, isTrue);
      t.vm.gradeBlind(correct: true); // ignored — not blind evidence
      expect(await t.log.all(), isEmpty);
      expect(t.words.statForItem(_station.progressId).isSeen, isFalse);
      t.vm.dispose();
    });
  });

  test(
    'prompted continue logs unscored practice and never moves SRS',
    () async {
      final t = await makeVm(const [_station]);
      t.vm.reveal();
      t.vm.noteHeard(itemIndex: 0, startedBlind: false);
      elapsed = 900;
      t.vm.continuePrompted();

      final a = (await t.log.all()).single;
      expect(a.correct, isFalse);
      expect(a.rtMs, 0);
      expect(a.meta[AttemptMeta.heard], isTrue);
      expect(a.meta[AttemptMeta.prompted], isTrue);
      expect(a.meta[AttemptMeta.scored], isFalse);
      final stat = t.words.statForItem(_station.progressId);
      expect(stat.isSeen, isFalse);
      expect(stat.srsLevel, 0);
      expect(t.vm.isFinished, isTrue);
      t.vm.dispose();
    },
  );

  test('skipping an unheard item records nothing', () async {
    final t = await makeVm(const [_station, _ticket]);
    t.vm.reveal();
    t.vm.skipUnheard();
    expect(await t.log.all(), isEmpty);
    expect(t.words.statForItem(_station.progressId).isSeen, isFalse);
    expect(t.vm.index, 1);
    t.vm.dispose();
  });

  test('commands that do not match the hearing state are ignored', () async {
    final t = await makeVm(const [_station]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);

    // Before reveal nothing advances.
    t.vm.noteHeard(itemIndex: 0, startedBlind: true);
    t.vm.gradeBlind(correct: true);
    t.vm.skipUnheard();
    t.vm.continuePrompted();
    expect(t.vm.index, 0);
    expect(t.vm.isFinished, isFalse);

    t.vm.reveal();
    // Blind evidence: skip and prompted-continue are not this item's exits.
    t.vm.skipUnheard();
    t.vm.continuePrompted();
    expect(t.vm.isFinished, isFalse);
    expect(await t.log.all(), isEmpty);
    expect(notifications, 2);
    t.vm.dispose();
  });

  group('reaction clock', () {
    test('interrupt after a hear keeps the evidence but untimes it', () async {
      final t = await makeVm(const [_station]);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      t.vm.noteInterrupted();
      elapsed = 604000;
      now = now.add(const Duration(minutes: 10, seconds: 4));
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);
      final a = (await t.log.all()).single;
      expect(a.rtMs, 0);
      expect(a.meta[AttemptMeta.heard], isTrue);
      expect(a.meta[AttemptMeta.scored], isTrue);
      expect(t.words.statForItem(_station.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('interrupt before the hear leaves a later replay untimed', () async {
      final t = await makeVm(const [_station]);
      t.vm.noteInterrupted();
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      expect(t.vm.blindHeard, isTrue);
      elapsed = 4000;
      now = now.add(const Duration(seconds: 4));
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);
      expect((await t.log.all()).single.rtMs, 0);
      expect(t.words.statForItem(_station.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('a same-item replay does not move the start', () async {
      final t = await makeVm(const [_station]);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      elapsed = 300;
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      elapsed = 500;
      now = now.add(const Duration(milliseconds: 500));
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);
      expect((await t.log.all()).single.rtMs, 500);
      t.vm.dispose();
    });

    test('the next item re-arms after an interrupted one', () async {
      final t = await makeVm(const [_kimi, _ticket]);
      t.vm.noteInterrupted();
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);

      elapsed = 1000;
      now = now.add(const Duration(seconds: 1));
      t.vm.noteHeard(itemIndex: 1, startedBlind: true);
      elapsed = 1500;
      now = now.add(const Duration(milliseconds: 500));
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);

      expect((await t.log.all()).map((a) => a.rtMs), [0, 500]);
      expect(t.words.statForItem('word:きみ').srsLevel, 1);
      expect(t.words.statForItem('word:きっぷ').srsLevel, 1);
      t.vm.dispose();
    });

    test('a backward wall clock is untimed, not negative', () async {
      final t = await makeVm(const [_station]);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      elapsed = 500;
      now = now.subtract(const Duration(hours: 1));
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);
      expect((await t.log.all()).single.rtMs, 0);
      t.vm.dispose();
    });
  });

  group('もう一回 grind gate', () {
    test(
      'wrap same id blind-correct does not climb; a new id still does',
      () async {
        final t = await makeVm(
          const [_station, _ticket],
          alreadyTransferredIds: {_station.progressId},
        );
        t.vm.noteHeard(itemIndex: 0, startedBlind: true);
        t.vm.reveal();
        t.vm.gradeBlind(correct: true);
        expect(t.words.statForItem(_station.progressId).srsLevel, 0);
        expect(t.words.statForItem(_station.progressId).isSeen, isFalse);
        // The attempt is still listening evidence; only the schedule is gated.
        expect((await t.log.all()).single.meta[AttemptMeta.scored], isTrue);

        t.vm.noteHeard(itemIndex: 1, startedBlind: true);
        t.vm.reveal();
        t.vm.gradeBlind(correct: true);
        expect(t.words.statForItem(_ticket.progressId).srsLevel, 1);
        expect(t.words.statForItem(_ticket.progressId).correctCount, 1);
        t.vm.dispose();
      },
    );

    test('wrap miss still resets', () async {
      final t = await makeVm(
        const [_station],
        alreadyTransferredIds: {_station.progressId},
      );
      await t.words.recordAnswer(_station.progressId, correct: true, at: now);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      t.vm.reveal();
      t.vm.gradeBlind(correct: false);
      expect(t.words.statForItem(_station.progressId).srsLevel, 0);
      expect(t.words.statForItem(_station.progressId).wrongCount, 1);
      t.vm.dispose();
    });
  });

  group('the close', () {
    test('finishes on the last item and ignores anything after', () async {
      final t = await makeVm(const [_station]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);
      expect(t.vm.isFinished, isTrue);
      expect(t.vm.index, 0);
      expect(notifications, 3);

      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      t.vm.reveal();
      t.vm.gradeBlind(correct: false);
      t.vm.skipUnheard();
      t.vm.continuePrompted();
      expect(notifications, 3);
      expect((await t.log.all()).length, 1);
      expect(t.words.statForItem(_station.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('the classical 余韻 waits on the kana owner\'s earned gate', () async {
      final fresh = await makeVm(const [_station], rng: _AlwaysShare());
      fresh.vm.reveal();
      fresh.vm.skipUnheard();
      expect(fresh.vm.isFinished, isTrue);
      expect(fresh.vm.share, isNull);
      fresh.vm.dispose();

      final earned = await makeVm(const [_station], rng: _AlwaysShare());
      for (final k in kHiraganaGojuon.take(16)) {
        await earned.kana.recordAnswer(k, correct: true, at: now);
      }
      earned.vm.reveal();
      earned.vm.skipUnheard();
      expect(earned.vm.share, isNotNull);
      earned.vm.dispose();
    });
  });

  test(
    'a failed save surfaces on the owner and retry flushes without re-climbing',
    () async {
      final fake = FakePreferencesService();
      final words = await WordProgressRepository.load(fake);
      fake.failWrites.add('word_stats_v1');
      final persist = ProgressPersistenceController(
        kanaFlush: () async {},
        kanjiFlush: () async {},
        wordFlush: words.flushPending,
      );
      final t = await makeVm(
        const [_ticket],
        words: words,
        persistence: persist,
      );

      t.vm.noteHeard(itemIndex: 0, startedBlind: true);
      t.vm.reveal();
      t.vm.gradeBlind(correct: true);
      expect(words.statForItem('word:きっぷ').srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(words.statForItem('word:きっぷ').srsLevel, 1);
      expect(words.statForItem('word:きっぷ').correctCount, 1);
      final reloaded = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForItem('word:きっぷ').srsLevel, 1);
      t.vm.dispose();
    },
  );
}
