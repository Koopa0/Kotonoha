// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/ui/kanji_sentence_viewmodel.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fake_preferences_service.dart';

const _yama = KanjiPhrase(
  segments: [
    RubySegment(text: '山', furigana: 'やま'),
    RubySegment(text: 'を'),
    RubySegment(text: '見', furigana: 'み'),
    RubySegment(text: 'る'),
  ],
  romaji: 'yama o miru',
  meaning: '看山',
);

const _kawa = KanjiPhrase(
  segments: [
    RubySegment(text: '川', furigana: 'かわ'),
    RubySegment(text: 'が'),
    RubySegment(text: '見', furigana: 'み'),
    RubySegment(text: 'える'),
  ],
  romaji: 'kawa ga mieru',
  meaning: '看得見河',
);

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 32 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'write did not settle');
}

/// Reads the kanji sentence ViewModel's contract without pumping a widget
/// or any speech service: the reveal and its commit, independence judged
/// against the ruby, the sentence schedule (never the per-reading one),
/// the 「もう一回」 gate, the close, and the persistence owner's failure /
/// retry path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 11, 12);

  ProgressPersistenceController owner() => ProgressPersistenceController(
    kanaFlush: () async {},
    kanjiFlush: () async {},
    wordFlush: () async {},
  );

  Future<
    ({
      KanjiSentenceViewModel vm,
      WordProgressRepository words,
      KanjiReadingRepository kanji,
      InMemoryAnalyticsLog log,
    })
  >
  makeVm(
    List<KanjiPhrase> phrases, {
    Set<String> alreadyTransferredIds = const {},
    WordProgressRepository? words,
    KanjiReadingRepository? kanji,
    ProgressPersistenceController? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final resolvedKanji = kanji ?? await KanjiReadingRepository.load();
    final resolvedWords = words ?? await WordProgressRepository.load();
    final log = InMemoryAnalyticsLog();
    final vm = KanjiSentenceViewModel(
      phrases: phrases,
      words: resolvedWords,
      kanji: resolvedKanji,
      persistence: persistence ?? owner(),
      analytics: log,
      sessionId: 's1',
      alreadyTransferredIds: alreadyTransferredIds,
      clock: () => now,
    );
    return (vm: vm, words: resolvedWords, kanji: resolvedKanji, log: log);
  }

  /// Matures every reading in [phrases] past the furigana fade, so the
  /// sentence offers no reading support.
  Future<void> fadeReadings(
    KanjiReadingRepository kanji,
    Iterable<KanjiPhrase> phrases,
  ) async {
    final ids = <String>{
      for (final phrase in phrases)
        for (final segment in phrase.segments)
          if (segment.unitId != null) segment.unitId!,
    };
    for (final id in ids) {
      for (var i = 0; i < ReadingStat.kFuriganaFadeLevel; i++) {
        await kanji.recordAnswer(id, correct: true, at: now);
      }
    }
  }

  test('opens unrevealed with full reading support on a fresh track', () async {
    final t = await makeVm(const [_yama, _kawa]);
    expect(t.vm.index, 0);
    expect(t.vm.total, 2);
    expect(t.vm.current, _yama);
    expect(t.vm.isRevealed, isFalse);
    expect(t.vm.unpromptedCommit, isFalse);
    expect(t.vm.hasVisibleReadingSupport, isTrue);
    expect(t.vm.srsLevelOf('unit:山#やま'), 0);
    expect(t.vm.correctCount, 0);
    expect(t.vm.isFinished, isFalse);
    expect(t.vm.isLastItem, isFalse);
    t.vm.dispose();
  });

  group('independence is judged against the ruby', () {
    test('unprompted 讀得出來 with the ruby faded climbs the sentence', () async {
      final t = await makeVm(const [_yama, _kawa]);
      await fadeReadings(t.kanji, const [_yama, _kawa]);
      expect(t.vm.hasVisibleReadingSupport, isFalse);
      var notifications = 0;
      t.vm.addListener(() => notifications++);

      t.vm.reveal(unpromptedCommit: true);
      expect(t.vm.isRevealed, isTrue);
      expect(t.vm.unpromptedCommit, isTrue);
      t.vm.grade(correct: true);

      final a = (await t.log.all()).single;
      expect(a.mode, PracticeMode.reading.name);
      expect(a.itemType, ItemType.kanji);
      expect(a.itemId, '山を見る');
      expect(a.correct, isTrue);
      expect(a.rtMs, 0);
      expect(a.sessionId, 's1');
      expect(a.meta['reading'], 'やまをみる');
      expect(a.meta[AttemptMeta.prompted], isFalse);
      final stat = t.words.statForItem(_yama.progressId);
      expect(stat.srsLevel, 1);
      expect(stat.correctCount, 1);
      expect(stat.lastReviewedAt, now);

      expect(t.vm.index, 1);
      expect(t.vm.isRevealed, isFalse);
      expect(t.vm.unpromptedCommit, isFalse);
      expect(t.vm.correctCount, 1);
      expect(notifications, 2);
      t.vm.dispose();
    });

    test('unprompted 讀得出來 under visible ruby is prompted intake', () async {
      final t = await makeVm(const [_yama]);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      final a = (await t.log.all()).single;
      expect(a.correct, isTrue);
      expect(a.meta[AttemptMeta.prompted], isTrue);
      final stat = t.words.statForItem(_yama.progressId);
      expect(stat.isSeen, isTrue);
      expect(stat.srsLevel, 0);
      expect(stat.correctCount, 0);
      t.vm.dispose();
    });

    test('a hinted confirm keeps intake without climbing', () async {
      final t = await makeVm(const [_yama]);
      await fadeReadings(t.kanji, const [_yama]);
      t.vm.reveal(unpromptedCommit: false);
      t.vm.grade(correct: true);
      expect((await t.log.all()).single.meta[AttemptMeta.prompted], isTrue);
      final stat = t.words.statForItem(_yama.progressId);
      expect(stat.isSeen, isTrue);
      expect(stat.srsLevel, 0);
      t.vm.dispose();
    });

    test('a supported confirm on a seen sentence writes nothing', () async {
      final t = await makeVm(const [_yama]);
      await t.words.recordAnswer(_yama.progressId, correct: true, at: now);
      final before = t.words.statForItem(_yama.progressId);
      t.vm.reveal(unpromptedCommit: false);
      t.vm.grade(correct: true);
      final after = t.words.statForItem(_yama.progressId);
      expect(after.srsLevel, before.srsLevel);
      expect(after.correctCount, before.correctCount);
      expect(after.lastReviewedAt, before.lastReviewedAt);
      t.vm.dispose();
    });

    test('a miss always resets, prompted or not', () async {
      final t = await makeVm(const [_yama, _kawa]);
      await fadeReadings(t.kanji, const [_yama, _kawa]);
      await t.words.recordAnswer(_yama.progressId, correct: true, at: now);
      await t.words.recordAnswer(_kawa.progressId, correct: true, at: now);

      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: false);
      expect(t.words.statForItem(_yama.progressId).srsLevel, 0);
      expect(t.words.statForItem(_yama.progressId).wrongCount, 1);

      t.vm.reveal(unpromptedCommit: false);
      t.vm.grade(correct: false);
      expect(t.words.statForItem(_kawa.progressId).srsLevel, 0);
      expect(t.words.statForItem(_kawa.progressId).wrongCount, 1);
      expect((await t.log.all()).map((a) => a.correct), [false, false]);
      expect(t.vm.correctCount, 0);
      t.vm.dispose();
    });

    test('the per-reading kanji schedule is never written', () async {
      final t = await makeVm(const [_yama]);
      final before = t.kanji.stats;
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.kanji.stats, before);
      t.vm.dispose();
    });
  });

  group('もう一回 grind gate', () {
    test('wrap same id independent-correct does not climb', () async {
      final t = await makeVm(
        const [_yama, _kawa],
        alreadyTransferredIds: {_yama.progressId},
      );
      await fadeReadings(t.kanji, const [_yama, _kawa]);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.words.statForItem(_yama.progressId).srsLevel, 0);
      expect(t.words.statForItem(_yama.progressId).isSeen, isFalse);

      // An uncovered id still climbs on its first independent confirm.
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(t.words.statForItem(_kawa.progressId).srsLevel, 1);
      t.vm.dispose();
    });

    test('wrap miss still resets', () async {
      final t = await makeVm(
        const [_yama],
        alreadyTransferredIds: {_yama.progressId},
      );
      await t.words.recordAnswer(_yama.progressId, correct: true, at: now);
      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: false);
      expect(t.words.statForItem(_yama.progressId).srsLevel, 0);
      expect(t.words.statForItem(_yama.progressId).wrongCount, 1);
      t.vm.dispose();
    });
  });

  test('commands off their step are ignored', () async {
    final t = await makeVm(const [_yama]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.grade(correct: true); // nothing revealed yet
    expect(t.vm.index, 0);
    expect(notifications, 0);

    t.vm.reveal(unpromptedCommit: true);
    t.vm.reveal(unpromptedCommit: false); // already revealed — keeps the commit
    expect(t.vm.unpromptedCommit, isTrue);
    expect(notifications, 1);
    expect(await t.log.all(), isEmpty);
    t.vm.dispose();
  });

  test('finishes on the last sentence and ignores anything after', () async {
    final t = await makeVm(const [_yama]);
    var notifications = 0;
    t.vm.addListener(() => notifications++);
    t.vm.reveal(unpromptedCommit: false);
    t.vm.grade(correct: true);
    expect(t.vm.isFinished, isTrue);
    expect(t.vm.index, 0);
    expect(t.vm.correctCount, 1);
    expect(notifications, 2);

    t.vm.reveal(unpromptedCommit: true);
    t.vm.grade(correct: false);
    expect(notifications, 2);
    expect(await t.log.all(), hasLength(1));
    expect(t.words.statForItem(_yama.progressId).wrongCount, 0);
    t.vm.dispose();
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
      final t = await makeVm(const [_yama], words: words, persistence: persist);
      await fadeReadings(t.kanji, const [_yama]);

      t.vm.reveal(unpromptedCommit: true);
      t.vm.grade(correct: true);
      expect(words.statForItem(_yama.progressId).srsLevel, 1);
      await _settle(() => persist.hasWriteFailure);

      fake.failWrites.clear();
      await persist.retry();
      expect(persist.hasWriteFailure, isFalse);
      expect(words.statForItem(_yama.progressId).srsLevel, 1);
      expect(words.statForItem(_yama.progressId).correctCount, 1);
      final reloaded = await WordProgressRepository.load(
        FakePreferencesService.restarted(fake),
      );
      expect(reloaded.statForItem(_yama.progressId).srsLevel, 1);
      t.vm.dispose();
    },
  );
}
