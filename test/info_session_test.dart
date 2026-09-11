// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/phrase_dataset.dart';
import 'package:kotonoha/domain/data/word_dataset.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/domain/use_cases/info_session.dart';

void main() {
  final allChars = {for (final kana in kAllKana) kana.character};

  WordStat seenAt() => WordStat.fromJson({'s': 1, 'c': 0, 'w': 0});

  Map<String, WordStat> statsForAll() => {
    for (final drill in kInfoDrills)
      for (final id in [...drill.requiredSeenIds, ...drill.requiredPartIds])
        id: seenAt(),
  };

  test('catalog reuses shipped corpus ids only', () {
    final corpus = [...kWords, ...kPhrases];
    expect(kInfoDrills.map((d) => d.id).toSet(), hasLength(kInfoDrills.length));
    for (final drill in kInfoDrills) {
      for (final id in [...drill.requiredSeenIds, ...drill.requiredPartIds]) {
        expect(corpus.where((item) => item.progressId == id), hasLength(1));
      }
    }
  });

  test('each kind has a base pair plus one migration combo', () {
    for (final kind in InfoKind.values) {
      final drills = infoDrillsFor(kind);
      expect(drills, hasLength(3));
      final base = drills.where((d) => !d.isMigration).toList();
      final migration = drills.where((d) => d.isMigration).toList();
      expect(base, hasLength(2));
      expect(migration, hasLength(1));
      expect(
        base.map((d) => d.correctAnswer).toSet(),
        hasLength(2),
        reason: kind.name,
      );
      expect(
        migration.single.correctAnswer,
        isNot(isIn(base.map((d) => d.correctAnswer))),
      );
    }
  });

  test('distractors stay within the same kind', () {
    for (final drill in kInfoDrills) {
      for (final wrong in drill.wrongAnswers) {
        expect(wrong, isNot(equals(drill.correctAnswer)));
        if (drill.kind == InfoKind.amount) {
          expect(wrong, contains('日圓'));
          expect(wrong, isNot(contains('點')));
          expect(wrong, isNot(contains('位')));
        }
        if (drill.kind == InfoKind.time) {
          expect(wrong, anyOf(contains('上午'), contains('下午')));
          expect(wrong, isNot(contains('日圓')));
          expect(wrong, isNot(contains('位')));
        }
        if (drill.kind == InfoKind.personCount) {
          expect(wrong, contains('位'));
          expect(wrong, isNot(contains('日圓')));
          expect(wrong, isNot(contains('點')));
        }
      }
    }
  });

  test('scene text is background only and does not leak the answer label', () {
    for (final drill in kInfoDrills) {
      expect(drill.sceneZh, isNot(contains(drill.correctAnswer)));
      expect(drill.sceneZh, isNot(contains(drill.promptMeaning)));
      for (final option in drill.answerChoices) {
        expect(drill.sceneZh, isNot(contains(option)));
      }
    }
  });

  test('unmet readable drills offer meet items, not cold practice', () {
    final view = InfoSession.inspect(learnedChars: allChars, stats: {});
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(view.unreadRequired, isNotEmpty);
  });

  test('compose prefers base and migration per kind when session is trimmed', () {
    final session = InfoSession.compose(
      learnedChars: allChars,
      rng: Random(1),
      stats: statsForAll(),
      sessionLength: 6,
    );
    expect(session, hasLength(6));
    for (final kind in InfoKind.values) {
      final kindDrills = session.where((d) => d.kind == kind).toList();
      expect(kindDrills.where((d) => !d.isMigration), hasLength(1));
      expect(kindDrills.where((d) => d.isMigration), hasLength(1));
    }
  });

  test('compose returns full catalog when all nine drills are ready', () {
    final session = InfoSession.compose(
      learnedChars: allChars,
      rng: Random(1),
      stats: statsForAll(),
    );
    expect(session, hasLength(9));
  });

  test('amount-3000 waits for さんぜん as a whole, not isolated ぜん', () {
    final drill = kInfoDrills.firstWhere((d) => d.id == 'info:amount-3000');
    expect(drill.requiredSeenIds, ['word:さんぜん', 'word:えん']);
    expect(kWords.map((w) => w.kana), isNot(contains('ぜん')));
    final partial = {'word:さん': seenAt(), 'word:えん': seenAt()};
    final view = InfoSession.inspect(learnedChars: allChars, stats: partial);
    expect(view.ready.map((d) => d.id), isNot(contains(drill.id)));
    expect(
      view.unreadRequired.map((i) => i.progressId),
      contains('word:さんぜん'),
    );
  });

  test('amount-5000 unlocks from parts without a whole ごせん word', () {
    final drill = kInfoDrills.firstWhere((d) => d.id == 'info:amount-5000');
    expect(drill.isMigration, isTrue);
    expect(drill.requiredPartIds, ['word:ご', 'word:せん', 'word:えん']);
    expect(kWords.map((w) => w.kana), isNot(contains('ごせん')));
    final stats = {
      'word:ご': seenAt(),
      'word:せん': seenAt(),
      'word:えん': seenAt(),
    };
    final view = InfoSession.inspect(learnedChars: allChars, stats: stats);
    expect(view.ready.map((d) => d.id), contains(drill.id));
  });

  test('person-3 unlocks from さん and にん, not ひとり/ふたり whole words', () {
    final drill = kInfoDrills.firstWhere((d) => d.id == 'info:person-3');
    final stats = {'word:さん': seenAt(), 'word:にん': seenAt()};
    final view = InfoSession.inspect(learnedChars: allChars, stats: stats);
    expect(view.ready.map((d) => d.id), contains(drill.id));
    expect(
      view.unreadRequired.map((i) => i.progressId),
      isNot(contains('word:さんにん')),
    );
  });

  test('compose can pair amount-3000 with amount-5000 in one session', () {
    final session = InfoSession.compose(
      learnedChars: allChars,
      rng: Random(0),
      stats: statsForAll(),
    );
    expect(
      session.map((d) => d.id),
      containsAll(['info:amount-3000', 'info:amount-5000']),
    );
  });
}
