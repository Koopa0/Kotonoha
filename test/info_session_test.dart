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

  test('each kind has two distinct values', () {
    for (final kind in InfoKind.values) {
      final drills = infoDrillsFor(kind);
      expect(drills, hasLength(2));
      expect(
        drills.map((d) => d.correctAnswer).toSet(),
        hasLength(2),
        reason: kind.name,
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

  test('compose prefers one drill per kind when all are ready', () {
    final session = InfoSession.compose(
      learnedChars: allChars,
      rng: Random(1),
      stats: statsForAll(),
    );
    expect(session, hasLength(6));
    expect(session.map((d) => d.kind).toSet(), InfoKind.values.toSet());
  });

  test('amount drill waits for さん／ぜん／えん before practice', () {
    final drill = kInfoDrills.firstWhere((d) => d.id == 'info:amount-3000');
    final partial = {'word:さん': seenAt(), 'word:ぜん': seenAt()};
    final view = InfoSession.inspect(learnedChars: allChars, stats: partial);
    expect(view.ready.map((d) => d.id), isNot(contains(drill.id)));
    expect(
      view.unreadRequired.map((i) => i.progressId),
      contains('word:えん'),
    );
  });
}
