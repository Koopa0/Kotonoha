// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/confusable.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

void main() {
  const all = kHiraganaGojuon;
  const engine = QuizEngine();

  test('members include kana from the confusable sets', () {
    final m = Confusable.members(all).map((k) => k.character).toSet();
    expect(m.containsAll(['ね', 'れ', 'わ']), isTrue);
    expect(m.containsAll(['る', 'ろ']), isTrue);
  });

  test('groupFor returns the look-alike group', () {
    final g = Confusable.groupFor('ね', all).map((k) => k.character).toList();
    expect(g, containsAll(['ね', 'れ', 'わ']));
  });

  test('session has the requested length and well-formed questions', () {
    final s = Confusable.session(
      allKana: all,
      length: 12,
      engine: engine,
      rng: Random(1),
    );
    expect(s.length, 12);
    for (final q in s) {
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4);
      expect(q.options[q.correctIndex], q.correctAnswer);
    }
  });

  test('every session target is a confusable member', () {
    final memberIds = Confusable.members(all).map((k) => k.id).toSet();
    final s = Confusable.session(
      allKana: all,
      length: 20,
      engine: engine,
      rng: Random(4),
    );
    for (final q in s) {
      expect(memberIds.contains(q.target.id), isTrue);
    }
  });

  test('first-row learned pool never targets unlearned kana', () {
    final learned = all.take(5).toList(); // あいうえお
    final learnedIds = learned.map((k) => k.id).toSet();
    expect(Confusable.isReady(learned), isTrue);
    final s = Confusable.session(
      allKana: learned,
      length: 12,
      engine: engine,
      rng: Random(0),
    );
    expect(s, isNotEmpty);
    for (final q in s) {
      expect(learnedIds.contains(q.target.id), isTrue);
      expect(q.options.length, 4);
      if (q.direction == QuizDirection.romajiToKana) {
        for (final o in q.options) {
          expect(learnedIds.contains(o), isTrue);
        }
      }
    }
  });

  test('too-small learned pool is not ready and composes nothing', () {
    final onlyA = all.take(1).toList();
    expect(Confusable.isReady(onlyA), isFalse);
    expect(
      Confusable.session(
        allKana: onlyA,
        length: 12,
        engine: engine,
        rng: Random(1),
      ),
      isEmpty,
    );
  });
}
