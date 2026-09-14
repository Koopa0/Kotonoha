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
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/dictation/dictation_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fake_preferences_service.dart';

const _kimi = Word(kana: 'きみ', romaji: 'kimi', meaning: '你');
const _ame = Word(kana: 'あめ', romaji: 'ame', meaning: '雨');
const _kyaku = Word(kana: 'きゃく', romaji: 'kyaku', meaning: '客人');
const _kamera = Word(
  kana: 'カメラ',
  romaji: 'kamera',
  meaning: '相機',
  script: KanaScript.katakana,
);

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

/// Reads the dictation ViewModel's contract without pumping a widget or
/// any speech service: the tile board, the assembly and its auto-check,
/// what a reported play means, the assemble clock, the 「もう一回」 gate,
/// the close, and the persistence owner's failure / retry path.
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
      DictationViewModel vm,
      WordProgressRepository words,
      KanaProgressRepository kana,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm(
    List<Word> items, {
    Set<String> alreadyTransferredIds = const {},
    Random? rng,
    WordProgressRepository? words,
    ProgressPersistenceController? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final kana = await KanaProgressRepository.load();
    final resolvedWords = words ?? await WordProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final vm = DictationViewModel(
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

  /// Places the current word's own units in order — the board never
  /// duplicates them, so each tile is found by its unit.
  void assemble(DictationViewModel vm, List<String> units) {
    for (final unit in units) {
      vm.tapTile(vm.tiles.indexOf(unit));
    }
  }

  void hear(DictationViewModel vm, {int itemIndex = 0}) => vm.notePlayback(
    itemIndex: itemIndex,
    result: SpeechPlaybackResult.played,
    startedBlind: true,
  );

  group('the board', () {
    test('opens on the first word with its units plus 3 distractors', () async {
      final t = await makeVm(const [_kimi, _ame]);
      expect(t.vm.index, 0);
      expect(t.vm.total, 2);
      expect(t.vm.current, _kimi);
      expect(t.vm.targetUnits, ['き', 'み']);
      expect(t.vm.tiles, hasLength(2 + DictationViewModel.distractorCount));
      expect(t.vm.tiles.toSet(), hasLength(t.vm.tiles.length));
      expect(t.vm.tiles, containsAll(['き', 'み']));
      expect(t.vm.picked, isEmpty);
      expect(t.vm.slotUnit(0), isNull);
      expect(t.vm.isChecked, isFalse);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.lastPlay, isNull);
      expect(t.vm.isFinished, isFalse);
      t.vm.dispose();
    });

    test('a yōon stays one unit; distractors are single kana', () async {
      final t = await makeVm(const [_kyaku]);
      expect(t.vm.targetUnits, ['きゃ', 'く']);
      final distractors = t.vm.tiles.where(
        (u) => !t.vm.targetUnits.contains(u),
      );
      expect(distractors, hasLength(DictationViewModel.distractorCount));
      expect(distractors.every((u) => u.length == 1), isTrue);
      t.vm.dispose();
    });

    test('distractors come from the word\'s own script', () async {
      final katakana = kKatakanaGojuon.map((k) => k.character).toSet();
      final t = await makeVm(const [_kamera]);
      expect(t.vm.tiles.toSet().difference(katakana), isEmpty);

      final hira = await makeVm(const [_kimi]);
      final hiragana = kHiraganaGojuon.map((k) => k.character).toSet();
      expect(hira.vm.tiles.toSet().difference(hiragana), isEmpty);
      t.vm.dispose();
      hira.vm.dispose();
    });

    test('tapping fills the next slot; clear returns every tile', () async {
      final t = await makeVm(const [_kimi]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      final mi = t.vm.tiles.indexOf('み');
      t.vm.tapTile(mi);
      expect(t.vm.isTileUsed(mi), isTrue);
      expect(t.vm.picked, [mi]);
      expect(t.vm.slotUnit(0), 'み');
      expect(t.vm.slotUnit(1), isNull);
      expect(t.vm.isChecked, isFalse);
      t.vm.tapTile(mi); // already placed — ignored
      expect(t.vm.picked, [mi]);
      expect(notifications, 1);

      t.vm.clear();
      expect(t.vm.isTileUsed(mi), isFalse);
      expect(t.vm.picked, isEmpty);
      expect(notifications, 2);
      t.vm.clear(); // nothing to clear — silent
      expect(notifications, 2);
      expect(await t.log.all(), isEmpty);
      t.vm.dispose();
    });
  });

  group('the check', () {
    test(
      'a full board checks itself; unheard correct is logged unscored',
      () async {
        final t = await makeVm(const [_kimi]);
        elapsed = 1200;
        now = now.add(const Duration(milliseconds: 1200));
        assemble(t.vm, ['き', 'み']);
        expect(t.vm.isChecked, isTrue);
        expect(t.vm.wasCorrect, isTrue);
        expect(t.vm.correctCount, 1);

        final a = (await t.log.all()).single;
        expect(a.mode, PracticeMode.dictation.name);
        expect(a.itemType, ItemType.word);
        expect(a.itemId, 'きみ');
        expect(a.correct, isTrue);
        expect(a.rtMs, 1200);
        expect(a.sessionId, 's1');
        expect(a.meta['romaji'], 'kimi');
        expect(a.meta[AttemptMeta.heard], isFalse);
        expect(a.meta[AttemptMeta.prompted], isFalse);
        expect(a.meta[AttemptMeta.scored], isFalse);
        // No play was ever reported: the sound counts as interrupted.
        expect(
          a.meta[AttemptMeta.playback],
          SpeechPlaybackResult.interrupted.name,
        );
        expect(t.words.statForItem(_kimi.progressId).isSeen, isFalse);
        expect(t.words.statForItem(_kimi.progressId).srsLevel, 0);
        t.vm.dispose();
      },
    );

    test('a wrong order is graded wrong and keeps the reveal', () async {
      final t = await makeVm(const [_kimi]);
      assemble(t.vm, ['み', 'き']);
      expect(t.vm.isChecked, isTrue);
      expect(t.vm.wasCorrect, isFalse);
      expect(t.vm.correctCount, 0);
      expect(t.vm.slotUnit(0), 'み');
      expect(t.vm.slotUnit(1), 'き');
      expect((await t.log.all()).single.correct, isFalse);
      // A checked board is frozen: no more tiles, no clear.
      final free = t.vm.tiles.indexWhere((u) => !['き', 'み'].contains(u));
      t.vm.tapTile(free);
      t.vm.clear();
      expect(t.vm.picked, hasLength(2));
      expect(await t.log.all(), hasLength(1));
      t.vm.dispose();
    });

    test('a failed play is carried into the attempt', () async {
      final t = await makeVm(const [_kimi]);
      t.vm.notePlayback(
        itemIndex: 0,
        result: SpeechPlaybackResult.failed,
        startedBlind: true,
      );
      expect(t.vm.lastPlay, SpeechPlaybackResult.failed);
      expect(t.vm.blindHeard, isFalse);
      assemble(t.vm, ['き', 'み']);
      final a = (await t.log.all()).single;
      expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.failed.name);
      expect(a.meta[AttemptMeta.heard], isFalse);
      expect(a.meta[AttemptMeta.scored], isFalse);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 0);
      t.vm.dispose();
    });
  });

  group('what a completed play means', () {
    test('a blind hear then correct is scored and climbs SRS', () async {
      final t = await makeVm(const [_kimi]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      hear(t.vm);
      expect(t.vm.blindHeard, isTrue);
      expect(t.vm.lastPlay, SpeechPlaybackResult.played);
      expect(notifications, 1);

      elapsed = 900;
      now = now.add(const Duration(milliseconds: 900));
      assemble(t.vm, ['き', 'み']);
      final a = (await t.log.all()).single;
      expect(a.correct, isTrue);
      expect(a.rtMs, 900);
      expect(a.meta[AttemptMeta.heard], isTrue);
      expect(a.meta[AttemptMeta.scored], isTrue);
      expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.played.name);
      final stat = t.words.statForItem(_kimi.progressId);
      expect(stat.srsLevel, 1);
      expect(stat.correctCount, 1);
      expect(stat.lastReviewedAt, now);
      t.vm.dispose();
    });

    test('a heard miss resets and is logged as a scored wrong', () async {
      final t = await makeVm(const [_kimi]);
      await t.words.recordAnswer(_kimi.progressId, correct: true, at: now);
      hear(t.vm);
      assemble(t.vm, ['み', 'き']);
      final stat = t.words.statForItem(_kimi.progressId);
      expect(stat.srsLevel, 0);
      expect(stat.wrongCount, 1);
      final a = (await t.log.all()).single;
      expect(a.correct, isFalse);
      expect(a.meta[AttemptMeta.scored], isTrue);
      t.vm.dispose();
    });

    test('a fail then a successful replay before the check is blind', () async {
      final t = await makeVm(const [_kimi]);
      t.vm.notePlayback(
        itemIndex: 0,
        result: SpeechPlaybackResult.failed,
        startedBlind: true,
      );
      hear(t.vm);
      expect(t.vm.blindHeard, isTrue);
      assemble(t.vm, ['き', 'み']);
      expect((await t.log.all()).single.meta[AttemptMeta.scored], isTrue);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('a play that finished after the check cannot backfill', () async {
      final t = await makeVm(const [_kimi]);
      assemble(t.vm, ['き', 'み']);
      // Started before the check, completed after: the reveal replay.
      hear(t.vm);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.lastPlay, SpeechPlaybackResult.played);
      t.vm.notePlayback(
        itemIndex: 0,
        result: SpeechPlaybackResult.played,
        startedBlind: false,
      );
      expect(t.vm.blindHeard, isFalse);
      expect((await t.log.all()).single.meta[AttemptMeta.scored], isFalse);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 0);
      t.vm.dispose();
    });

    test('a completion for another word is stale and ignored', () async {
      final t = await makeVm(const [_kimi, _ame]);
      hear(t.vm, itemIndex: 1);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.lastPlay, isNull);

      assemble(t.vm, ['き', 'み']);
      t.vm.next();
      expect(t.vm.index, 1);
      hear(t.vm); // the old word (index 0), late
      expect(t.vm.blindHeard, isFalse);
      assemble(t.vm, ['あ', 'め']);
      final logged = await t.log.all();
      expect(logged, hasLength(2));
      expect(logged.last.itemId, 'あめ');
      expect(logged.last.meta[AttemptMeta.heard], isFalse);
      expect(t.words.statForItem(_ame.progressId).srsLevel, 0);
      t.vm.dispose();
    });
  });

  group('assemble clock', () {
    test('an interrupt keeps the hearing but untimes the word', () async {
      final t = await makeVm(const [_kimi]);
      hear(t.vm);
      t.vm.noteInterrupted();
      expect(t.vm.lastPlay, SpeechPlaybackResult.interrupted);
      expect(t.vm.blindHeard, isTrue);
      elapsed = 604000;
      now = now.add(const Duration(minutes: 10, seconds: 4));
      assemble(t.vm, ['き', 'み']);
      final a = (await t.log.all()).single;
      expect(a.rtMs, 0);
      expect(a.meta[AttemptMeta.heard], isTrue);
      expect(a.meta[AttemptMeta.scored], isTrue);
      expect(a.meta[AttemptMeta.playback], SpeechPlaybackResult.played.name);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('an interrupt before any play leaves a replay untimed', () async {
      final t = await makeVm(const [_kimi]);
      t.vm.noteInterrupted();
      hear(t.vm);
      expect(t.vm.blindHeard, isTrue);
      elapsed = 1200;
      now = now.add(const Duration(milliseconds: 1200));
      assemble(t.vm, ['き', 'み']);
      expect((await t.log.all()).single.rtMs, 0);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('the next word re-arms from its own show', () async {
      final t = await makeVm(const [_kimi, _ame]);
      t.vm.noteInterrupted();
      hear(t.vm);
      assemble(t.vm, ['き', 'み']);
      elapsed = 5000;
      now = now.add(const Duration(seconds: 5));
      t.vm.next();
      hear(t.vm, itemIndex: 1);
      elapsed = 5700;
      now = now.add(const Duration(milliseconds: 700));
      assemble(t.vm, ['あ', 'め']);
      expect((await t.log.all()).map((a) => a.rtMs), [0, 700]);
      t.vm.dispose();
    });

    test('a backward wall clock is untimed, not negative', () async {
      final t = await makeVm(const [_kimi]);
      elapsed = 500;
      now = now.subtract(const Duration(hours: 1));
      assemble(t.vm, ['き', 'み']);
      expect((await t.log.all()).single.rtMs, 0);
      t.vm.dispose();
    });
  });

  group('もう一回 grind gate', () {
    test('wrap same id heard-correct does not climb; a new id does', () async {
      final t = await makeVm(
        const [_kimi, _ame],
        alreadyTransferredIds: {_kimi.progressId},
      );
      hear(t.vm);
      assemble(t.vm, ['き', 'み']);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 0);
      expect(t.words.statForItem(_kimi.progressId).isSeen, isFalse);
      // The attempt is still dictation evidence; only the schedule is gated.
      expect((await t.log.all()).single.meta[AttemptMeta.scored], isTrue);

      t.vm.next();
      hear(t.vm, itemIndex: 1);
      assemble(t.vm, ['あ', 'め']);
      expect(t.words.statForItem(_ame.progressId).srsLevel, 1);
      expect(t.words.statForItem(_ame.progressId).correctCount, 1);
      t.vm.dispose();
    });

    test('wrap miss still resets', () async {
      final t = await makeVm(
        const [_kimi],
        alreadyTransferredIds: {_kimi.progressId},
      );
      await t.words.recordAnswer(_kimi.progressId, correct: true, at: now);
      hear(t.vm);
      assemble(t.vm, ['み', 'き']);
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 0);
      expect(t.words.statForItem(_kimi.progressId).wrongCount, 1);
      t.vm.dispose();
    });
  });

  group('next and the close', () {
    test('next is only an exit from a checked word', () async {
      final t = await makeVm(const [_kimi, _ame]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      t.vm.next();
      expect(t.vm.index, 0);
      expect(notifications, 0);
      t.vm.dispose();
    });

    test('next opens a fresh board and forgets the old hearing', () async {
      final t = await makeVm(const [_kimi, _ame]);
      hear(t.vm);
      assemble(t.vm, ['み', 'き']);
      t.vm.next();
      expect(t.vm.index, 1);
      expect(t.vm.current, _ame);
      expect(t.vm.targetUnits, ['あ', 'め']);
      expect(t.vm.picked, isEmpty);
      expect(t.vm.isChecked, isFalse);
      expect(t.vm.wasCorrect, isFalse);
      expect(t.vm.blindHeard, isFalse);
      expect(t.vm.lastPlay, isNull);
      expect(t.vm.correctCount, 0);
      expect(t.vm.isLastItem, isTrue);
      expect(t.vm.isFinished, isFalse);
      t.vm.dispose();
    });

    test('finishes after the last word and ignores anything after', () async {
      final t = await makeVm(const [_kimi]);
      var notifications = 0;
      t.vm.addListener(() => notifications++);
      hear(t.vm);
      assemble(t.vm, ['き', 'み']);
      t.vm.next();
      expect(t.vm.isFinished, isTrue);
      expect(t.vm.index, 0);
      expect(t.vm.correctCount, 1);
      // hear, one tile, the check, the close.
      expect(notifications, 4);

      hear(t.vm);
      t.vm.noteInterrupted();
      t.vm.tapTile(0);
      t.vm.clear();
      t.vm.next();
      expect(notifications, 4);
      expect(await t.log.all(), hasLength(1));
      expect(t.words.statForItem(_kimi.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('the classical 余韻 waits on the kana owner\'s earned gate', () async {
      final fresh = await makeVm(const [_kimi], rng: _AlwaysShare());
      assemble(fresh.vm, ['き', 'み']);
      fresh.vm.next();
      expect(fresh.vm.isFinished, isTrue);
      expect(fresh.vm.share, isNull);
      fresh.vm.dispose();

      final earned = await makeVm(const [_kimi], rng: _AlwaysShare());
      for (final k in kHiraganaGojuon.take(16)) {
        await earned.kana.recordAnswer(k, correct: true, at: now);
      }
      assemble(earned.vm, ['き', 'み']);
      earned.vm.next();
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
      final t = await makeVm(const [_kimi], words: words, persistence: persist);

      hear(t.vm);
      assemble(t.vm, ['き', 'み']);
      expect(words.statForItem('word:きみ').srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(words.statForItem('word:きみ').srsLevel, 1);
      expect(words.statForItem('word:きみ').correctCount, 1);
      final reloaded = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForItem('word:きみ').srsLevel, 1);
      t.vm.dispose();
    },
  );
}
