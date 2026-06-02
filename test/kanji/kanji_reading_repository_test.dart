// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 1, 12);
  const id = 'reading:人#ジン';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty and knows the full kanji set', () async {
    final repo = await KanjiReadingRepository.load();
    expect(repo.seenReadingCount, 0);
    expect(repo.allKanji.length, 82);
    expect(repo.statForReading(id).isSeen, isFalse);
  });

  test('records an answer and persists across reloads', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    expect(repo.statForReading(id).correctCount, 1);
    expect(repo.seenReadingCount, 1);

    final reloaded = await KanjiReadingRepository.load();
    expect(reloaded.statForReading(id).correctCount, 1);
    expect(reloaded.statForReading(id).lastReviewedAt, now);
  });

  test('wrong answer resets the level; correct advances it', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    expect(repo.statForReading(id).srsLevel, 1);
    await repo.recordAnswer(id, correct: false, at: now);
    expect(repo.statForReading(id).srsLevel, 0);
  });

  test('dueReadingIds returns due readings earliest-first', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now); // due ~1 day later
    // Nothing is due at recording time.
    expect(repo.dueReadingIds(now), isEmpty);
    // A week later it's due.
    expect(repo.dueReadingIds(now.add(const Duration(days: 7))), [id]);
  });

  test('reset clears everything', () async {
    final repo = await KanjiReadingRepository.load();
    await repo.recordAnswer(id, correct: true, at: now);
    await repo.reset();
    expect(repo.seenReadingCount, 0);
  });
}
