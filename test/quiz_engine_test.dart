// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';

void main() {
  const engine = QuizEngine();
  const all = kHiraganaGojuon;

  group('buildQuestion', () {
    test('kana→romaji: 4 distinct options containing the answer', () {
      final target = all.firstWhere((k) => k.character == 'し');
      final q = engine.buildQuestion(
        target,
        QuizDirection.kanaToRomaji,
        all,
        Random(1),
      );
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4, reason: 'no duplicate options');
      expect(q.options[q.correctIndex], 'shi');
      expect(q.prompt, 'し');
      expect(q.options.contains('shi'), isTrue);
    });

    test('romaji→kana: 4 distinct options containing the answer', () {
      final target = all.firstWhere((k) => k.character == 'き');
      final q = engine.buildQuestion(
        target,
        QuizDirection.romajiToKana,
        all,
        Random(2),
      );
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4);
      expect(q.options[q.correctIndex], 'き');
      expect(q.prompt, 'ki');
    });

    test('distractors never equal the answer', () {
      for (final target in all) {
        final q = engine.buildQuestion(
          target,
          QuizDirection.kanaToRomaji,
          all,
          Random(target.character.hashCode),
        );
        final distractors = [...q.options]..removeAt(q.correctIndex);
        expect(distractors.contains(target.romaji), isFalse);
      }
    });

    test('same-sound kana never co-occur (ぢ vs じ are both "ji")', () {
      final dji = kHiraganaDakuten.firstWhere((k) => k.character == 'ぢ');
      final q = engine.buildQuestion(
        dji,
        QuizDirection.romajiToKana,
        kHiraganaDakuten, // contains both じ and ぢ
        Random(1),
      );
      expect(q.options.contains('ぢ'), isTrue);
      expect(q.options.contains('じ'), isFalse); // じ also reads 'ji'
    });

    test('kanaRecall: no options, prompt is the glyph, answer is romaji', () {
      final target = all.firstWhere((k) => k.character == 'し');
      final q = engine.buildQuestion(
        target,
        QuizDirection.kanaRecall,
        all,
        Random(1),
      );
      expect(q.options, isEmpty);
      expect(q.prompt, 'し');
      expect(q.correctAnswer, 'shi');
      expect(q.isCorrect(0), isTrue);
      expect(q.isCorrect(1), isFalse);
    });

    test('soundToKana: options are kana, answer is the target kana', () {
      final target = all.firstWhere((k) => k.character == 'す');
      final q = engine.buildQuestion(
        target,
        QuizDirection.soundToKana,
        all,
        Random(5),
      );
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4);
      expect(q.options[q.correctIndex], 'す');
      // Every option is a kana glyph from the set (no romaji leaks in).
      expect(q.options.every((o) => all.any((k) => k.character == o)), isTrue);
    });
  });

  group('generateSession', () {
    test('produces exactly the requested length', () {
      for (final n in const [5, 10, 20]) {
        final session = engine.generateSession(
          targets: all,
          allKana: all,
          length: n,
          random: Random(7),
        );
        expect(session.length, n);
      }
    });

    test('every question is well-formed', () {
      final session = engine.generateSession(
        targets: all,
        allKana: all,
        length: 20,
        random: Random(3),
      );
      for (final q in session) {
        expect(q.options.length, 4);
        expect(q.options.toSet().length, 4);
        expect(q.correctIndex, inInclusiveRange(0, 3));
        expect(q.options[q.correctIndex], q.correctAnswer);
      }
    });

    test('is deterministic for a fixed seed', () {
      List<String> run() => engine
          .generateSession(
            targets: all,
            allKana: all,
            length: 10,
            random: Random(42),
          )
          .map((q) => '${q.prompt}->${q.correctAnswer}@${q.correctIndex}')
          .toList();
      expect(run(), run());
    });

    test('handles a small target pool (weak review) without crashing', () {
      final small = all.take(3).toList();
      final session = engine.generateSession(
        targets: small,
        allKana: all,
        length: 10,
        random: Random(9),
      );
      expect(session.length, 10);
      for (final q in session) {
        expect(small.map((k) => k.id).contains(q.target.id), isTrue);
        expect(q.options.length, 4);
      }
    });

    test('empty targets yields empty session', () {
      expect(
        engine.generateSession(targets: const [], allKana: all, length: 10),
        isEmpty,
      );
    });

    test(
      'mixed-script pool: a hiragana target gets no katakana distractor',
      () {
        final ka = all.firstWhere((k) => k.character == 'か');
        final session = engine.generateSession(
          targets: [ka],
          allKana: [...kHiraganaGojuon, ...kKatakanaGojuon], // mixed
          length: 1,
          random: Random(1),
        );
        for (final o in session.first.options) {
          expect(o.runes.any((r) => r >= 0x30A0 && r <= 0x30FF), isFalse);
        }
      },
    );
  });
}
