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

  test(
    'compose prefers base and migration per kind when session is trimmed',
    () {
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
    },
  );

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
    expect(view.unreadRequired.map((i) => i.progressId), contains('word:さんぜん'));
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

  test('hotel time drills stay out of the global catalog', () {
    expect(
      kInfoDrills.map((d) => d.id),
      isNot(contains('info:hotel-breakfast-9am')),
    );
    expect(kHotelInfoDrills, hasLength(2));
    for (final drill in kHotelInfoDrills) {
      expect(drill.kind, InfoKind.time);
      expect(drill.sceneZh, isNot(contains(drill.correctAnswer)));
    }
  });

  test('hotel breakfast waits for scene phrase and time units', () {
    final drill = kHotelInfoDrills.firstWhere(
      (d) => d.id == 'info:hotel-breakfast-9am',
    );
    final partial = {
      'phrase:あさごはんは ありますか': seenAt(),
      'word:あさごはん': seenAt(),
      'word:ごぜん': seenAt(),
      'word:く': seenAt(),
    };
    final view = InfoSession.inspect(
      learnedChars: allChars,
      stats: partial,
      drills: kHotelInfoDrills,
    );
    expect(view.ready.map((d) => d.id), isNot(contains(drill.id)));
    expect(view.unreadRequired.map((i) => i.progressId), contains('word:じ'));
    final ready = InfoSession.inspect(
      learnedChars: allChars,
      stats: {...partial, 'word:じ': seenAt()},
      drills: kHotelInfoDrills,
    );
    expect(ready.ready.map((d) => d.id), contains(drill.id));
  });

  test('hotel checkout waits for tomorrow phrase and checkout word', () {
    final drill = kHotelInfoDrills.firstWhere(
      (d) => d.id == 'info:hotel-checkout-10am',
    );
    final partial = {
      'phrase:あした でます': seenAt(),
      'word:ごぜん': seenAt(),
      'word:じゅう': seenAt(),
      'word:じ': seenAt(),
    };
    final view = InfoSession.inspect(
      learnedChars: allChars,
      stats: partial,
      drills: kHotelInfoDrills,
    );
    expect(view.ready.map((d) => d.id), isNot(contains(drill.id)));
    expect(
      view.unreadRequired.map((i) => i.progressId),
      contains('word:チェックアウト'),
    );
  });

  test('hotel words seen still leave unread phrases for meet', () {
    final wordStats = {
      for (final drill in kHotelInfoDrills)
        for (final id in drill.requiredSeenIds)
          if (id.startsWith('word:')) id: seenAt(),
    };
    final view = InfoSession.inspect(
      learnedChars: allChars,
      stats: wordStats,
      drills: kHotelInfoDrills,
    );
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(
      InfoSession.unreadRequiredWords(
        learnedChars: allChars,
        stats: wordStats,
        drills: kHotelInfoDrills,
      ),
      isEmpty,
    );
    expect(
      InfoSession.unreadRequiredPhrases(
        learnedChars: allChars,
        stats: wordStats,
        drills: kHotelInfoDrills,
      ).map((i) => i.progressId),
      containsAll(['phrase:あさごはんは ありますか', 'phrase:あした でます']),
    );
    expect(
      kHotelInfoDrills.expand((d) => d.requiredSeenIds),
      containsAll(['phrase:あさごはんは ありますか', 'phrase:あした でます']),
    );
  });

  test('hotel phrases seen still leave unread words for meet', () {
    final phraseStats = {
      'phrase:あさごはんは ありますか': seenAt(),
      'phrase:あした でます': seenAt(),
    };
    final view = InfoSession.inspect(
      learnedChars: allChars,
      stats: phraseStats,
      drills: kHotelInfoDrills,
    );
    expect(view.canPractice, isFalse);
    expect(view.canMeet, isTrue);
    expect(
      InfoSession.unreadRequiredPhrases(
        learnedChars: allChars,
        stats: phraseStats,
        drills: kHotelInfoDrills,
      ),
      isEmpty,
    );
    expect(
      InfoSession.unreadRequiredWords(
        learnedChars: allChars,
        stats: phraseStats,
        drills: kHotelInfoDrills,
      ).map((i) => i.progressId),
      containsAll(['word:あさごはん', 'word:チェックアウト']),
    );
  });

  test('hotel compose stays on scoped time drills after gates are met', () {
    final stats = {
      for (final drill in kHotelInfoDrills)
        for (final id in drill.requiredSeenIds) id: seenAt(),
    };
    final view = InfoSession.inspect(
      learnedChars: allChars,
      stats: stats,
      drills: kHotelInfoDrills,
    );
    expect(view.canMeet, isFalse);
    expect(
      view.ready.map((d) => d.id),
      containsAll(['info:hotel-breakfast-9am', 'info:hotel-checkout-10am']),
    );
    final session = InfoSession.compose(
      learnedChars: allChars,
      rng: Random(1),
      stats: stats,
      drills: kHotelInfoDrills,
    );
    expect(session, hasLength(2));
    expect(session.map((d) => d.id), isNot(contains('info:amount-3000')));
    expect(session.map((d) => d.kind).toSet(), {InfoKind.time});
  });

  test('empty stats batches global info words eight then seven', () {
    final unread = InfoSession.unreadRequiredWords(
      learnedChars: allChars,
      stats: const {},
    );
    expect(unread, hasLength(15));
    expect(unread.every((item) => item.progressId.startsWith('word:')), isTrue);

    final first = InfoSession.composeIntroWords(
      learnedChars: allChars,
      stats: const {},
    );
    expect(first, hasLength(8));
    expect(first, unread.take(8));

    final afterFirst = {for (final word in first) word.progressId: seenAt()};
    final second = InfoSession.composeIntroWords(
      learnedChars: allChars,
      stats: afterFirst,
    );
    expect(second, hasLength(7));
    expect(
      second
          .map((w) => w.progressId)
          .toSet()
          .intersection(first.map((w) => w.progressId).toSet()),
      isEmpty,
    );
    expect(
      InfoSession.composeIntroPhrases(
        learnedChars: allChars,
        stats: afterFirst,
      ),
      isEmpty,
    );

    final afterAll = {for (final word in unread) word.progressId: seenAt()};
    final view = InfoSession.inspect(learnedChars: allChars, stats: afterAll);
    expect(view.canMeet, isFalse);
    expect(view.canPractice, isTrue);
    expect(
      InfoSession.composeIntroWords(learnedChars: allChars, stats: afterAll),
      isEmpty,
    );
  });

  test('hotel intro stays six words then two phrases, not global catalog', () {
    final words = InfoSession.composeIntroWords(
      learnedChars: allChars,
      stats: const {},
      drills: kHotelInfoDrills,
    );
    expect(words, hasLength(6));
    expect(words.map((w) => w.progressId), isNot(contains('word:さんぜん')));
    expect(
      words.map((w) => w.progressId).toSet(),
      containsAll({
        'word:あさごはん',
        'word:ごぜん',
        'word:く',
        'word:じ',
        'word:チェックアウト',
        'word:じゅう',
      }),
    );

    final phrases = InfoSession.composeIntroPhrases(
      learnedChars: allChars,
      stats: const {},
      drills: kHotelInfoDrills,
    );
    expect(phrases, hasLength(2));
    expect(
      phrases.map((p) => p.progressId),
      containsAll(['phrase:あさごはんは ありますか', 'phrase:あした でます']),
    );

    final afterWords = {for (final word in words) word.progressId: seenAt()};
    expect(
      InfoSession.composeIntroWords(
        learnedChars: allChars,
        stats: afterWords,
        drills: kHotelInfoDrills,
      ),
      isEmpty,
    );
    expect(
      InfoSession.composeIntroPhrases(
        learnedChars: allChars,
        stats: afterWords,
        drills: kHotelInfoDrills,
      ),
      hasLength(2),
    );
    final hotelView = InfoSession.inspect(
      learnedChars: allChars,
      stats: afterWords,
      drills: kHotelInfoDrills,
    );
    expect(hotelView.canPractice, isFalse);
    expect(hotelView.canMeet, isTrue);
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
