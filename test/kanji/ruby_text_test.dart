// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';
import 'package:kotonoha/kanji/ui/ruby_text.dart';

void main() {
  test('furigana opacity thins as the reading matures and is gone at the cap', () {
    expect(RubyText.furiganaOpacity(0), 1.0); // brand new — full
    expect(RubyText.furiganaOpacity(1), 0.7); // first recalls — thinning
    expect(RubyText.furiganaOpacity(2), 0.4); // one below the cap — faint
    // GONE at the untimed mastery ceiling — reachable by correct recall alone,
    // no timed beat needed (the coupling that once froze it at 0.42).
    expect(RubyText.furiganaOpacity(ReadingStat.kFuriganaFadeLevel), 0.0);
    expect(RubyText.furiganaOpacity(5), 0.0);
  });

  test('visible reading support follows the furigana still on the card', () {
    const phrase = KanjiPhrase(
      segments: [
        RubySegment(text: '山', furigana: 'やま'),
        RubySegment(text: 'を'),
        RubySegment(text: '見', furigana: 'み'),
        RubySegment(text: 'る'),
      ],
      romaji: 'yama o miru',
      meaning: '看山',
    );
    expect(RubyText.hasVisibleReadingSupport(phrase, (_) => 0), isTrue);
    expect(RubyText.hasVisibleReadingSupport(phrase, (_) => 2), isTrue);
    expect(
      RubyText.hasVisibleReadingSupport(
        phrase,
        (_) => ReadingStat.kFuriganaFadeLevel,
      ),
      isFalse,
    );
  });

  testWidgets('renders the kanji and its furigana', (tester) async {
    const phrase = KanjiPhrase(
      segments: [
        RubySegment(text: '山', furigana: 'やま'),
        RubySegment(text: 'を'),
      ],
      romaji: 'yama o',
      meaning: '山',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RubyText(phrase: phrase, srsLevelOf: (_) => 0),
        ),
      ),
    );
    expect(find.text('山'), findsOneWidget);
    expect(find.text('やま'), findsOneWidget); // furigana
    expect(find.text('を'), findsOneWidget);
  });
}
