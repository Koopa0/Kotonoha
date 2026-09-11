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
      for (final id in drill.requiredSeenIds) id: seenAt(),
  };

  test('catalog reuses shipped corpus ids only', () {
    final corpus = [...kWords, ...kPhrases];
    expect(kInfoDrills.map((d) => d.id).toSet(), hasLength(kInfoDrills.length));
    for (final drill in kInfoDrills) {
      for (final id in drill.requiredSeenIds) {
        expect(corpus.where((item) => item.progressId == id), hasLength(1));
      }
    }
  });

  test('each kind has taught values and one assembled combination', () {
    for (final kind in InfoKind.values) {
      final drills = infoDrillsFor(kind);
      expect(drills.length, greaterThanOrEqualTo(3), reason: kind.name);
      expect(
        drills.map((d) => d.correctAnswer).toSet(),
        hasLength(drills.length),
        reason: kind.name,
      );
      expect(
        drills.where((d) => d.assembledFromParts),
        isNotEmpty,
        reason: kind.name,
      );
    }
  });

  test('assembled combinations are not corpus words and wait on parts', () {
    final corpusKana = kWords.map((w) => w.kana).toSet();
    expect(corpusKana, isNot(contains('ぜん')));
    expect(corpusKana, isNot(contains('よ')));
    expect(corpusKana, isNot(contains('ごせん')));
    expect(corpusKana, isNot(contains('さんにん')));
    expect(corpusKana, isNot(contains('ごにん')));
    expect(corpusKana, containsAll(['ご', 'にん', 'よにん', 'さんぜん']));

    final amount = kInfoDrills.firstWhere((d) => d.id == 'info:amount-5000');
    expect(amount.assembledFromParts, isTrue);
    expect(amount.requiredSeenIds, ['word:ご', 'word:せん', 'word:えん']);
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {'word:ご': seenAt(), 'word:えん': seenAt()},
      ).ready.map((d) => d.id),
      isNot(contains(amount.id)),
    );
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {
          'word:ご': seenAt(),
          'word:せん': seenAt(),
          'word:えん': seenAt(),
        },
      ).ready.map((d) => d.id),
      contains(amount.id),
    );

    final time = kInfoDrills.firstWhere((d) => d.id == 'info:time-10pm');
    expect(time.assembledFromParts, isTrue);
    expect(time.requiredSeenIds, ['word:ごご', 'word:じゅう', 'word:じ']);
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {
          'word:ごご': seenAt(),
          'word:じゅう': seenAt(),
          'word:じ': seenAt(),
        },
      ).ready.map((d) => d.id),
      contains(time.id),
    );

    final three = kInfoDrills.firstWhere((d) => d.id == 'info:person-3');
    final five = kInfoDrills.firstWhere((d) => d.id == 'info:person-5');
    expect(three.assembledFromParts, isTrue);
    expect(five.assembledFromParts, isTrue);
    expect(three.requiredSeenIds, ['word:さん', 'word:にん']);
    expect(five.requiredSeenIds, ['word:ご', 'word:にん']);
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {'word:さん': seenAt()},
      ).ready.map((d) => d.id),
      isNot(contains(three.id)),
    );
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {'word:さん': seenAt(), 'word:にん': seenAt()},
      ).unreadRequired.map((i) => i.progressId),
      isNot(contains('word:さんにん')),
    );
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {'word:さん': seenAt(), 'word:にん': seenAt()},
      ).ready.map((d) => d.id),
      contains(three.id),
    );
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {'word:ご': seenAt(), 'word:にん': seenAt()},
      ).ready.map((d) => d.id),
      contains(five.id),
    );

    final four = kInfoDrills.firstWhere((d) => d.id == 'info:person-4');
    expect(four.assembledFromParts, isFalse);
    expect(four.requiredSeenIds, ['word:よにん']);
    expect(
      InfoSession.inspect(
        learnedChars: allChars,
        stats: {'word:にん': seenAt()},
      ).ready.map((d) => d.id),
      isNot(contains(four.id)),
    );
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

  test('compose prefers one drill per kind when all are ready', () {
    final session = InfoSession.compose(
      learnedChars: allChars,
      rng: Random(1),
      stats: statsForAll(),
    );
    expect(session, hasLength(6));
    expect(session.map((d) => d.kind).toSet(), InfoKind.values.toSet());
    expect(
      session.where((d) => d.assembledFromParts).map((d) => d.kind).toSet(),
      InfoKind.values.toSet(),
    );
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
}
