// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/data/kanji_phrase_dataset.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_reading_quiz.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';

/// The honesty of the kanji track lives in these distractors. A 漢字-literate
/// adult reading 学校 already owns the meaning; the only thing that can be
/// tested is the SOUND, and the only wrong answer that actually tests it is
/// the one his own instinct produces — 学【ガク】+ 校【コウ】= がくこう.
void main() {
  const inventory = [
    KanjiEntry(
      char: '学',
      meaningZh: '學',
      readings: [Reading(text: 'ガク', kind: ReadingKind.on)],
    ),
    KanjiEntry(
      char: '校',
      meaningZh: '校',
      readings: [Reading(text: 'コウ', kind: ReadingKind.on)],
    ),
    KanjiEntry(
      char: '生',
      meaningZh: '生',
      readings: [
        Reading(text: 'セイ', kind: ReadingKind.on),
        Reading(text: 'ショウ', kind: ReadingKind.on),
        Reading(text: 'なま', kind: ReadingKind.kun),
        Reading(text: 'う', kind: ReadingKind.kun),
      ],
    ),
  ];

  KanjiPhrase phraseWith(String written, String reading, String tail) =>
      KanjiPhrase(
        segments: [
          RubySegment(text: written, furigana: reading),
          RubySegment(text: tail),
        ],
        romaji: 'x',
        meaning: 'x',
      );

  final gakkou = KanjiUnit(
    written: '学校',
    reading: 'がっこう',
    example: phraseWith('学校', 'がっこう', 'へ'),
  );
  final nama = KanjiUnit(
    written: '生',
    reading: 'なま',
    example: phraseWith('生', 'なま', 'の'),
  );

  test(
    'the naive character-by-character reading is offered as a distractor',
    () {
      // 学校 is がっこう, NOT がくこう — the sound change is exactly what a reader
      // reasoning from characters gets wrong, so it must be on the card.
      final q = const KanjiReadingQuiz().buildQuestion(
        gakkou,
        [gakkou, nama],
        inventory,
        Random(1),
      );

      expect(q.options, contains('がくこう'));
      expect(q.answer, 'がっこう');
      expect(q.options[q.correctIndex], 'がっこう');
    },
  );

  test('other readings of the same kanji are offered (one reading is not the kanji)', () {
    final q = const KanjiReadingQuiz().buildQuestion(
      nama,
      [gakkou, nama],
      inventory,
      Random(2),
    );

    // Knowing 生 reads なま somewhere must not answer 生 anywhere: its other
    // real readings stand next to it as options.
    expect(q.options, contains('せい'));
    expect(q.options.where((o) => o == 'なま'), hasLength(1));
  });

  test('on-readings are offered in hiragana, never as a katakana tell', () {
    final q = const KanjiReadingQuiz().buildQuestion(
      nama,
      [gakkou, nama],
      inventory,
      Random(3),
    );

    for (final option in q.options) {
      expect(
        option.runes.every((r) => r < 0x30a1 || r > 0x30f6),
        isTrue,
        reason: 'katakana option "$option" would stand out by script alone',
      );
    }
  });

  test('the answer appears exactly once and options never repeat', () {
    for (var seed = 0; seed < 40; seed++) {
      final q = const KanjiReadingQuiz().buildQuestion(
        gakkou,
        [gakkou, nama],
        inventory,
        Random(seed),
      );
      expect(q.options.where((o) => o == q.answer), hasLength(1));
      expect(q.options.toSet(), hasLength(q.options.length));
      expect(q.options[q.correctIndex], q.answer);
    }
  });

  test('deterministic under a seed', () {
    List<String> run() => const KanjiReadingQuiz()
        .buildQuestion(gakkou, [gakkou, nama], inventory, Random(7))
        .options;
    expect(run(), run());
  });

  test('a unit whose kanji the inventory does not know still gets options', () {
    // The corpus may use kanji the curriculum has not reached; the question
    // falls back to other units' readings rather than shipping a single option.
    final unknown = KanjiUnit(
      written: '喫茶',
      reading: 'きっさ',
      example: phraseWith('喫茶', 'きっさ', 'てん'),
    );
    final q = const KanjiReadingQuiz().buildQuestion(
      unknown,
      [unknown, gakkou, nama],
      inventory,
      Random(5),
    );

    expect(q.options.length, greaterThanOrEqualTo(2));
    expect(q.options, contains('きっさ'));
  });

  group('against the real corpus', () {
    final units = KanjiUnits.fromPhrases(kKanjiPhrases);

    test('every harvested unit builds a question with real choices', () {
      final rng = Random(11);
      for (final unit in units) {
        final q = const KanjiReadingQuiz().buildQuestion(
          unit,
          units,
          kKanji,
          rng,
        );
        expect(
          q.options.length,
          greaterThanOrEqualTo(3),
          reason: '${unit.written}: too few options to be a real question',
        );
        expect(q.options.where((o) => o == q.answer), hasLength(1));
      }
    });

    test('units are harvested from the corpus, deduped, with context', () {
      expect(units, isNotEmpty);
      expect(units.map((u) => u.id).toSet(), hasLength(units.length));
      for (final unit in units) {
        expect(unit.reading, isNotEmpty);
        expect(
          unit.example.segments.any(
            (s) => s.text == unit.written && s.furigana == unit.reading,
          ),
          isTrue,
          reason: '${unit.id}: its example does not contain it',
        );
      }
    });
  });
}
