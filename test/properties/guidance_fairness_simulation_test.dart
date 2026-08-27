// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/guidance.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/reading_set.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starvation guard for the ambient next-step line. The failure it exists to
/// catch is invisible to every unit test: with a fixed curriculum order in
/// branch E, the largest pool (300+ words) absorbs every introduction for
/// months and the tracks behind it — sentences, and the grammar spine the
/// learner actually asked for — never appear in the guidance line at all.
///
/// This drives the REAL `Guidance.nextStep` and the REAL `TrackDue.fromItems`
/// over 180 simulated days, doing exactly what the line tells it to, and
/// asserts every track is reached and keeps being reached.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('180 days of following the guidance line: no track is starved', () async {
    final store = await KanaProgressRepository.load();
    for (final lesson in Lessons.fromKana(store.allKana)) {
      await store.markUnitLearned(lesson.id);
    }

    // Every kana learned, so all three corpora are fully readable.
    final chars = store.allKana.map((k) => k.character).toSet();
    final words = ReadingSet.readable(kWords, chars);
    final phrases = ReadingSet.readable(kPhrases, chars);
    final sentences = ReadingSet.readable(kKanjiPhrases, chars);
    expect(words, isNotEmpty);
    expect(phrases, isNotEmpty);
    expect(sentences, isNotEmpty);

    final stats = <String, WordStat>{};
    final rng = Random(11);
    final start = DateTime(2026, 9, 1, 9);
    // Day each track first received an introduction (-1 = never).
    final firstReached = {'words': -1, 'phrases': -1, 'sentences': -1};

    void run(List<ReadingItem> pool, String label, DateTime at, int maxNew) {
      final session = ReadingSet.session(
        items: pool,
        learnedChars: chars,
        rng: rng,
        now: at,
        stats: stats,
        maxNew: maxNew,
      );
      for (final item in session) {
        final before = stats[item.progressId] ?? const WordStat();
        if (!before.isSeen && firstReached[label] == -1) {
          firstReached[label] = at.difference(start).inDays;
        }
        stats[item.progressId] = before.recordAnswer(
          correct: rng.nextDouble() >= 0.10,
          at: at,
        );
      }
    }

    for (var day = 0; day < 180; day++) {
      final now = start.add(Duration(days: day));
      final step = Guidance.nextStep(
        store,
        now: now,
        words: TrackDue.fromItems(words, stats, now),
        sentences: TrackDue.fromItems(phrases, stats, now),
        kanjiSentences: TrackDue.fromItems(sentences, stats, now),
      );
      switch (step.target) {
        // 渡し舟 introduces words; 文字起こし reviews them and never introduces.
        case GuidanceTarget.ferry:
          run(words, 'words', now, 3);
        case GuidanceTarget.dictation:
          run(words, 'words', now, 0);
        case GuidanceTarget.sentences:
          run(phrases, 'phrases', now, 3);
        case GuidanceTarget.kanjiSentences:
          run(sentences, 'sentences', now, 3);
        case GuidanceTarget.lessons:
        case GuidanceTarget.daily:
        case GuidanceTarget.kanji:
        case GuidanceTarget.rest:
          break; // nothing to simulate for this track here
      }
    }

    int met(List<ReadingItem> pool) => pool
        .where((i) => (stats[i.progressId] ?? const WordStat()).isSeen)
        .length;

    // Every track is reached — the starvation this guards against would leave
    // one of these at zero for the whole run.
    expect(met(words), greaterThan(0), reason: 'words never reached');
    expect(
      met(phrases),
      greaterThan(0),
      reason: 'kana sentences never reached',
    );
    expect(
      met(sentences),
      greaterThan(0),
      reason: 'the grammar-spine track never reached',
    );
    // And reached EARLY, not after the biggest pool drains: with fair rotation
    // every track sees its first introduction inside the first fortnight.
    for (final entry in firstReached.entries) {
      expect(
        entry.value,
        inInclusiveRange(0, 14),
        reason: '${entry.key} waited ${entry.value} days for a first meeting',
      );
    }
    // No track is left far behind the others once they are all running.
    final counts = [met(words), met(phrases), met(sentences)];
    expect(
      counts.every((c) => c >= 10),
      isTrue,
      reason: 'a track stalled after starting: $counts',
    );
  });
}
