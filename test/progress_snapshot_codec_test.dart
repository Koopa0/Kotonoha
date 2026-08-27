// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/services/progress_snapshot_codec.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/progress_snapshot.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

// ---------------------------------------------------------------------------
// Test-side fixture signer. An INDEPENDENT (crypto-backed) re-implementation of
// the codec's canonical checksum, used to hand-sign fixtures — including
// deliberately invalid ones — so a test can prove the codec ACCEPTS a
// correctly-checksummed file and only THEN judges its payload. It is pinned to
// the codec's own canonicalization by the hand-written v1 fixture test: if this
// diverged, that fixture would fail on checksum, not decode.
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k as String).toList()..sort();
    return {for (final k in keys) k: _canonical(value[k])};
  }
  if (value is List) {
    return value.map(_canonical).toList()
      ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  }
  return value;
}

String _sign(Map<String, Object?> unsigned) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(unsigned)))).toString();

/// Assembles a full v1 envelope with a VALID checksum over [unsigned].
String _file(Map<String, Object?> unsigned) => jsonEncode(<String, Object?>{
  ...unsigned,
  'checksum': <String, Object?>{
    'algorithm': 'sha256',
    'value': _sign(unsigned),
  },
});

/// A well-formed unsigned envelope with overridable parts, for crafting both
/// valid and deliberately broken fixtures.
Map<String, Object?> _unsigned({
  String kind = 'kotonoha.progress',
  Object? schemaVersion = 1,
  String createdAt = '2026-07-24T12:00:00.000Z',
  Map<String, Object?>? kanaStats,
  List<Object?>? learnedUnits,
  List<Object?>? seenUnlocks,
  Map<String, Object?>? kanjiReadingStats,
}) => <String, Object?>{
  'kind': kind,
  'schemaVersion': schemaVersion,
  'createdAt': createdAt,
  'payload': <String, Object?>{
    'kanaStats': kanaStats ?? <String, Object?>{},
    'learnedUnits': learnedUnits ?? <Object?>[],
    'seenUnlocks': seenUnlocks ?? <Object?>[],
    'kanjiReadingStats': kanjiReadingStats ?? <String, Object?>{},
  },
};

ProgressSnapshot _populated() => ProgressSnapshot(
  createdAt: DateTime.utc(2026, 6, 15, 9, 45, 30),
  kanaStats: {
    'あ': KanaStat(
      seenCount: 5,
      correctCount: 4,
      wrongCount: 1,
      lastReviewedAt: DateTime.fromMillisecondsSinceEpoch(1748509200000),
      srsLevel: 2,
      dueAt: DateTime.fromMillisecondsSinceEpoch(1748595600000),
      avgLatencyMs: 620,
      varLatencyMs2: 800,
    ),
    'い': const KanaStat(seenCount: 2, correctCount: 2),
  },
  learnedUnits: {'hira_row_0', 'hira_row_1'},
  seenUnlocks: {'words', 'phrases'},
  kanjiReadingStats: {
    'reading:人#ジン': const ReadingStat(
      seenCount: 3,
      correctCount: 3,
      srsLevel: 3,
    ),
    'reading:日#ニチ': const ReadingStat(seenCount: 1, wrongCount: 1),
  },
);

void main() {
  const codec = ProgressSnapshotCodec();

  ProgressSnapshot decoded(String raw) {
    final r = codec.decodeAndValidate(raw);
    expect(
      r,
      isA<SnapshotDecodeSuccess>(),
      reason: 'expected success for: $raw',
    );
    return (r as SnapshotDecodeSuccess).snapshot;
  }

  SnapshotDecodeError failure(String raw) {
    final r = codec.decodeAndValidate(raw);
    expect(
      r,
      isA<SnapshotDecodeFailure>(),
      reason: 'expected failure for: $raw',
    );
    return (r as SnapshotDecodeFailure).error;
  }

  group('canonicalization & determinism', () {
    test('same logical state + createdAt encodes byte-identically regardless '
        'of Map/Set insertion order', () {
      final createdAt = DateTime.utc(2026, 5, 1, 8, 30);
      const k1 = KanaStat(seenCount: 3, correctCount: 2, wrongCount: 1);
      const k2 = KanaStat(seenCount: 1, correctCount: 1);
      const r1 = ReadingStat(seenCount: 2, correctCount: 2);
      const r2 = ReadingStat(seenCount: 1, wrongCount: 1);

      // A: keys inserted あ,い / ジン,ニチ; sets one way.
      final a = ProgressSnapshot(
        createdAt: createdAt,
        kanaStats: {'あ': k1, 'い': k2},
        learnedUnits: {'hira_row_0', 'kata_row_1'},
        seenUnlocks: {'words', 'phrases'},
        kanjiReadingStats: {'reading:人#ジン': r1, 'reading:日#ニチ': r2},
      );
      // B: every insertion order reversed.
      final b = ProgressSnapshot(
        createdAt: createdAt,
        kanaStats: {'い': k2, 'あ': k1},
        learnedUnits: {'kata_row_1', 'hira_row_0'},
        seenUnlocks: {'phrases', 'words'},
        kanjiReadingStats: {'reading:日#ニチ': r2, 'reading:人#ジン': r1},
      );
      expect(codec.encode(a), codec.encode(b));
    });

    test('the emitted checksum is a lowercase 64-hex sha256', () {
      final m = jsonDecode(codec.encode(_populated())) as Map<String, dynamic>;
      final cs = m['checksum'] as Map<String, dynamic>;
      expect(cs['algorithm'], 'sha256');
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(cs['value'] as String), isTrue);
    });
  });

  group('round trips', () {
    test('a populated export decodes then re-encodes byte-identically', () {
      final bytes = codec.encode(_populated());
      expect(codec.encode(decoded(bytes)), bytes);
    });

    test('a legal empty snapshot round-trips', () {
      final s = ProgressSnapshot(
        createdAt: DateTime.utc(2026),
        kanaStats: const {},
        learnedUnits: const {},
        seenUnlocks: const {},
        kanjiReadingStats: const {},
      );
      final bytes = codec.encode(s);
      final back = decoded(bytes);
      expect(back.kanaStats, isEmpty);
      expect(back.learnedUnits, isEmpty);
      expect(back.seenUnlocks, isEmpty);
      expect(back.kanjiReadingStats, isEmpty);
      expect(codec.encode(back), bytes);
    });

    test('every kana wire field round-trips', () {
      final full = KanaStat(
        seenCount: 9,
        correctCount: 5,
        wrongCount: 4,
        lastReviewedAt: DateTime.fromMillisecondsSinceEpoch(1748509200000),
        srsLevel: 6,
        dueAt: DateTime.fromMillisecondsSinceEpoch(1748595600000),
        avgLatencyMs: 650,
        varLatencyMs2: 1200,
      );
      final back = decoded(
        codec.encode(
          ProgressSnapshot(
            createdAt: DateTime.utc(2026, 4, 4),
            kanaStats: {'き': full},
            learnedUnits: const {},
            seenUnlocks: const {},
            kanjiReadingStats: const {},
          ),
        ),
      ).kanaStats['き']!;
      expect(back.seenCount, 9);
      expect(back.correctCount, 5);
      expect(back.wrongCount, 4);
      expect(
        back.lastReviewedAt,
        DateTime.fromMillisecondsSinceEpoch(1748509200000),
      );
      expect(back.srsLevel, 6);
      expect(back.dueAt, DateTime.fromMillisecondsSinceEpoch(1748595600000));
      expect(back.avgLatencyMs, 650);
      expect(back.varLatencyMs2, 1200);
    });

    test('every kanji reading wire field round-trips', () {
      final full = ReadingStat(
        seenCount: 4,
        correctCount: 3,
        wrongCount: 1,
        lastReviewedAt: DateTime.fromMillisecondsSinceEpoch(1748509200000),
        srsLevel: 3,
        dueAt: DateTime.fromMillisecondsSinceEpoch(1748595600000),
      );
      final back = decoded(
        codec.encode(
          ProgressSnapshot(
            createdAt: DateTime.utc(2026, 4, 4),
            kanaStats: const {},
            learnedUnits: const {},
            seenUnlocks: const {},
            kanjiReadingStats: {'reading:人#ジン': full},
          ),
        ),
      ).kanjiReadingStats['reading:人#ジン']!;
      expect(back.seenCount, 4);
      expect(back.correctCount, 3);
      expect(back.wrongCount, 1);
      expect(
        back.lastReviewedAt,
        DateTime.fromMillisecondsSinceEpoch(1748509200000),
      );
      expect(back.srsLevel, 3);
      expect(back.dueAt, DateTime.fromMillisecondsSinceEpoch(1748595600000));
    });

    test('unknown but well-formed ids are preserved verbatim, never filtered '
        'against the current dataset', () {
      final s = ProgressSnapshot(
        createdAt: DateTime.utc(2026, 2, 2),
        kanaStats: {
          'retired_kana_x': const KanaStat(seenCount: 1, correctCount: 1),
        },
        learnedUnits: {'legacy_unit_removed_2099'},
        seenUnlocks: {'unlock_from_the_future'},
        kanjiReadingStats: {'reading:𠀀#みず': const ReadingStat(seenCount: 1)},
      );
      final back = decoded(codec.encode(s));
      expect(back.kanaStats.keys, contains('retired_kana_x'));
      expect(back.learnedUnits, contains('legacy_unit_removed_2099'));
      expect(back.seenUnlocks, contains('unlock_from_the_future'));
      expect(back.kanjiReadingStats.keys, contains('reading:𠀀#みず'));
    });
  });

  group('scope — only canonical progress, none of the store machinery', () {
    test('the envelope carries no analytics / last-good / quarantine / health '
        'or their fixed key names', () {
      final bytes = codec.encode(_populated());
      for (final forbidden in const [
        'analytics',
        'last_good',
        'lastGood',
        'quarantine',
        'health',
        'StoreHealth',
        'preservationPending',
        'recoveryRequired',
        'kana_stats_v1',
        'kanji_stats_v1',
        'learned_units_v1',
        'seen_unlocks_v1',
        'appVersion',
        'contentVersion',
        'deviceId',
      ]) {
        expect(bytes.contains(forbidden), isFalse, reason: forbidden);
      }
      expect(bytes.contains('kotonoha.progress'), isTrue);
      expect(bytes.contains('schemaVersion'), isTrue);
      expect(bytes.contains('checksum'), isTrue);
    });
  });

  group('strict typed decode failures', () {
    test('malformed and truncated json are malformedJson', () {
      expect(failure('{not json'), SnapshotDecodeError.malformedJson);
      final bytes = codec.encode(_populated());
      expect(
        failure(bytes.substring(0, bytes.length - 5)),
        SnapshotDecodeError.malformedJson,
      );
      expect(
        failure('42'),
        SnapshotDecodeError.invalidEnvelope,
      ); // valid json, not an object
    });

    test('a wrong kind is wrongKind', () {
      expect(
        failure(_file(_unsigned(kind: 'evil.app'))),
        SnapshotDecodeError.wrongKind,
      );
    });

    test(
      'absent, zero, negative and future schema versions are unsupported',
      () {
        final absent = _unsigned()..remove('schemaVersion');
        expect(
          failure(_file(absent)),
          SnapshotDecodeError.unsupportedSchemaVersion,
        );
        for (final v in const [0, -1, 2, 99]) {
          expect(
            failure(_file(_unsigned(schemaVersion: v))),
            SnapshotDecodeError.unsupportedSchemaVersion,
          );
        }
      },
    );

    test(
      'there is no schema v0 — a zero version is rejected, not migrated',
      () {
        expect(
          failure(_file(_unsigned(schemaVersion: 0))),
          SnapshotDecodeError.unsupportedSchemaVersion,
        );
      },
    );

    test('a structurally valid change with a stale checksum is '
        'checksumMismatch', () {
      final valid = _file(
        _unsigned(
          kanaStats: {
            'あ': const <String, Object?>{'s': 3, 'c': 2, 'w': 1},
          },
        ),
      );
      // Bump seenCount 3 -> 4: still structurally valid (c+w <= s), only the
      // checksum is now stale. (Structurally valid on purpose so the
      // skip-checksum sentinel reddens to a Success, not an invalidPayload.)
      final m1 = jsonDecode(valid) as Map<String, dynamic>;
      (((m1['payload'] as Map)['kanaStats'] as Map)['あ'] as Map)['s'] = 4;
      expect(failure(jsonEncode(m1)), SnapshotDecodeError.checksumMismatch);
      // Shift createdAt to another valid Z instant, keep the old checksum.
      final m2 = jsonDecode(valid) as Map<String, dynamic>;
      m2['createdAt'] = '2030-01-01T00:00:00.000Z';
      expect(failure(jsonEncode(m2)), SnapshotDecodeError.checksumMismatch);
    });

    test('a wrong checksum algorithm, length, or case is invalidEnvelope', () {
      final valid = jsonDecode(_file(_unsigned())) as Map<String, dynamic>;
      final good = (valid['checksum'] as Map)['value'] as String;

      final wrongAlg = jsonDecode(_file(_unsigned())) as Map<String, dynamic>;
      (wrongAlg['checksum'] as Map)['algorithm'] = 'md5';
      expect(
        failure(jsonEncode(wrongAlg)),
        SnapshotDecodeError.invalidEnvelope,
      );

      final wrongLen = jsonDecode(_file(_unsigned())) as Map<String, dynamic>;
      (wrongLen['checksum'] as Map)['value'] = 'abc123';
      expect(
        failure(jsonEncode(wrongLen)),
        SnapshotDecodeError.invalidEnvelope,
      );

      final wrongCase = jsonDecode(_file(_unsigned())) as Map<String, dynamic>;
      (wrongCase['checksum'] as Map)['value'] = good.toUpperCase();
      expect(
        failure(jsonEncode(wrongCase)),
        SnapshotDecodeError.invalidEnvelope,
      );
    });

    test('a valid checksum over a semantically invalid payload is '
        'invalidPayload', () {
      // stat is not an object
      expect(
        failure(_file(_unsigned(kanaStats: {'あ': 42}))),
        SnapshotDecodeError.invalidPayload,
      );
      // fractional count
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 3, 'c': 1.5, 'w': 0},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // negative count
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': -1},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // correct + wrong exceeds seen
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 1, 'c': 1, 'w': 1},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // srs level beyond the wire-expressible 0..6
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 1, 'c': 1, 'w': 0, 'sl': 7},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // fractional timestamp
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 1, 'l': 1.5},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // unknown stat field
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 1, 'x': 9},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // empty id key
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                '': const <String, Object?>{'s': 1},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      // non-string / empty / duplicate set members
      expect(
        failure(_file(_unsigned(learnedUnits: [1]))),
        SnapshotDecodeError.invalidPayload,
      );
      expect(
        failure(_file(_unsigned(learnedUnits: ['']))),
        SnapshotDecodeError.invalidPayload,
      );
      expect(
        failure(_file(_unsigned(seenUnlocks: ['words', 'words']))),
        SnapshotDecodeError.invalidPayload,
      );
      // unknown payload section
      final extraSection = _unsigned();
      (extraSection['payload']! as Map)['bogus'] = 1;
      expect(failure(_file(extraSection)), SnapshotDecodeError.invalidPayload);
      // legacy kanji al/vl present but negative is still rejected
      expect(
        failure(
          _file(
            _unsigned(
              kanjiReadingStats: {
                'reading:人#ジン': const <String, Object?>{'s': 1, 'al': -5},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
    });

    test('one corrupt entry rejects the ENTIRE snapshot — no per-entry '
        'salvage (unlike the local RecoverableStore)', () {
      final r = codec.decodeAndValidate(
        _file(
          _unsigned(
            kanaStats: {
              'あ': const <String, Object?>{'s': 3, 'c': 2, 'w': 1}, // valid
              'い': const <String, Object?>{'s': 1, 'c': 5, 'w': 0}, // c+w > s
              'う': const <String, Object?>{'s': 2, 'c': 1, 'w': 0}, // valid
            },
          ),
        ),
      );
      expect(r, isA<SnapshotDecodeFailure>());
      expect(
        (r as SnapshotDecodeFailure).error,
        SnapshotDecodeError.invalidPayload,
      );
    });
  });

  group('hand-written v1 fixture', () {
    test('kana s/c/w/l only, kanji with retired al/vl — decodes and tolerates '
        'the retired fields', () {
      // Payload literals TYPED BY HAND — not produced by the encoder or by
      // any model.toJson — so the wire format itself stays pinned.
      final unsigned = <String, Object?>{
        'kind': 'kotonoha.progress',
        'schemaVersion': 1,
        'createdAt': '2026-03-04T05:06:07.000Z',
        'payload': <String, Object?>{
          'kanaStats': <String, Object?>{
            'あ': <String, Object?>{'s': 3, 'c': 2, 'w': 1, 'l': 1748509200000},
          },
          'learnedUnits': <Object?>['hira_row_0'],
          'seenUnlocks': <Object?>['words'],
          'kanjiReadingStats': <String, Object?>{
            'reading:人#ジン': <String, Object?>{
              's': 2,
              'c': 2,
              'w': 0,
              'l': 1748509200000,
              'sl': 2,
              'd': 1748595600000,
              'al': 700, // retired timed field — must be tolerated + ignored
              'vl': 900,
            },
          },
        },
      };
      final s = decoded(_file(unsigned));

      final a = s.kanaStats['あ']!;
      expect(a.seenCount, 3);
      expect(a.correctCount, 2);
      expect(a.wrongCount, 1);
      expect(
        a.lastReviewedAt,
        DateTime.fromMillisecondsSinceEpoch(1748509200000),
      );
      expect(a.srsLevel, 0); // absent → model default
      expect(a.avgLatencyMs, 0); // absent → model default
      expect(s.learnedUnits, {'hira_row_0'});
      expect(s.seenUnlocks, {'words'});
      expect(s.createdAtUtc, DateTime.utc(2026, 3, 4, 5, 6, 7));

      final jin = s.kanjiReadingStats['reading:人#ジン']!;
      expect(jin.seenCount, 2);
      expect(jin.correctCount, 2);
      expect(jin.srsLevel, 2);
      expect(jin.dueAt, DateTime.fromMillisecondsSinceEpoch(1748595600000));

      // The retired al/vl were tolerated but dropped by ReadingStat, so a
      // re-encode omits them entirely.
      final reenc = jsonDecode(codec.encode(s)) as Map<String, dynamic>;
      final jinOut =
          ((reenc['payload'] as Map)['kanjiReadingStats']
                  as Map)['reading:人#ジン']
              as Map;
      expect(jinOut.containsKey('al'), isFalse);
      expect(jinOut.containsKey('vl'), isFalse);
    });
  });

  group('immutable, deep-copied candidate', () {
    test('snapshot collections are unmodifiable and isolated from their '
        'sources; the decoded candidate is too', () {
      final kana = {'あ': const KanaStat(seenCount: 1, correctCount: 1)};
      final learned = {'hira_row_0'};
      final s = ProgressSnapshot(
        createdAt: DateTime.utc(2026),
        kanaStats: kana,
        learnedUnits: learned,
        seenUnlocks: const {},
        kanjiReadingStats: const {},
      );
      expect(() => s.kanaStats['い'] = const KanaStat(), throwsUnsupportedError);
      expect(() => s.learnedUnits.add('x'), throwsUnsupportedError);
      expect(() => s.seenUnlocks.add('x'), throwsUnsupportedError);
      expect(
        () => s.kanjiReadingStats['r'] = const ReadingStat(),
        throwsUnsupportedError,
      );
      // Mutating the SOURCE after construction must not touch the snapshot.
      kana['う'] = const KanaStat(seenCount: 9);
      learned.add('kata_row_0');
      expect(s.kanaStats.containsKey('う'), isFalse);
      expect(s.learnedUnits.contains('kata_row_0'), isFalse);

      final back = decoded(codec.encode(s));
      expect(
        () => back.kanaStats['x'] = const KanaStat(),
        throwsUnsupportedError,
      );
      expect(() => back.learnedUnits.add('x'), throwsUnsupportedError);
    });
  });

  // -----------------------------------------------------------------------
  // Acceptance repair #1: self-importable export + decoder exception firewall
  // -----------------------------------------------------------------------

  group('repair A — encode rejects self-unimportable snapshots', () {
    // A local store loaded leniently (RecoverableStore accepts a hand-seeded
    // primary that KanaStat.fromJson parses) can hold values the STRICT portable
    // contract forbids. encode must fail loudly (typed) rather than emit bytes
    // that its own decoder would reject.
    ProgressSnapshot withKana(KanaStat stat) => ProgressSnapshot(
      createdAt: DateTime.utc(2026, 7, 24, 12),
      kanaStats: {'あ': stat},
      learnedUnits: const {},
      seenUnlocks: const {},
      kanjiReadingStats: const {},
    );

    test('correct + wrong exceeds seen → SnapshotEncodeException', () {
      expect(
        () => codec.encode(
          withKana(
            const KanaStat(seenCount: 1, correctCount: 1, wrongCount: 1),
          ),
        ),
        throwsA(isA<SnapshotEncodeException>()),
      );
    });

    test('a negative count → SnapshotEncodeException', () {
      expect(
        () => codec.encode(withKana(const KanaStat(seenCount: -1))),
        throwsA(isA<SnapshotEncodeException>()),
      );
    });

    test('an SRS level past the portable cap → SnapshotEncodeException', () {
      expect(
        () => codec.encode(
          withKana(const KanaStat(seenCount: 1, correctCount: 1, srsLevel: 7)),
        ),
        throwsA(isA<SnapshotEncodeException>()),
      );
    });

    test('an empty learned unit id → SnapshotEncodeException', () {
      expect(
        () => codec.encode(
          ProgressSnapshot(
            createdAt: DateTime.utc(2026),
            kanaStats: const {},
            learnedUnits: {''},
            seenUnlocks: const {},
            kanjiReadingStats: const {},
          ),
        ),
        throwsA(isA<SnapshotEncodeException>()),
      );
    });

    test('an empty seen unlock id → SnapshotEncodeException', () {
      expect(
        () => codec.encode(
          ProgressSnapshot(
            createdAt: DateTime.utc(2026),
            kanaStats: const {},
            learnedUnits: const {},
            seenUnlocks: {''},
            kanjiReadingStats: const {},
          ),
        ),
        throwsA(isA<SnapshotEncodeException>()),
      );
    });

    test(
      'a fully valid snapshot encodes AND decodes back (self-importable)',
      () {
        final s = withKana(
          const KanaStat(seenCount: 3, correctCount: 2, wrongCount: 1),
        );
        final bytes = codec.encode(s);
        expect(codec.decodeAndValidate(bytes), isA<SnapshotDecodeSuccess>());
      },
    );
  });

  group('repair B — decoder exception firewall (any raw input → typed)', () {
    test('an epoch-millis just past the DateTime range → invalidPayload, never '
        'a thrown RangeError', () {
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 1, 'l': 8640000000000001},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
      expect(
        failure(
          _file(
            _unsigned(
              kanjiReadingStats: {
                'reading:人#ジン': const <String, Object?>{
                  's': 1,
                  'd': 8640000000000001,
                },
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
    });

    test('an int64-max epoch-millis → invalidPayload, never a thrown '
        'RangeError', () {
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{'s': 1, 'l': 9223372036854775807},
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
    });

    test('a non-finite payload number (1e309 → Infinity) → invalidPayload, '
        'never a thrown JsonUnsupportedObjectError', () {
      // Hand-written raw: 1e309 parses to double Infinity, which cannot be
      // canonicalised (jsonEncode throws on Infinity), so no correct checksum
      // is computable — the decoder must reject BEFORE checksum. The checksum
      // value here is a syntactically valid but unused placeholder.
      const raw =
          '{"kind":"kotonoha.progress","schemaVersion":1,'
          '"createdAt":"2026-07-24T12:00:00.000Z","payload":{'
          '"kanaStats":{"あ":{"s":1,"l":1e309}},"learnedUnits":[],'
          '"seenUnlocks":[],"kanjiReadingStats":{}},'
          '"checksum":{"algorithm":"sha256","value":'
          '"0000000000000000000000000000000000000000000000000000000000000000"}}';
      expect(failure(raw), SnapshotDecodeError.invalidPayload);
    });
  });

  group('repair C — overflow-safe count invariant', () {
    test('seen 0 with int64-max correct and wrong → invalidPayload (no signed '
        'overflow)', () {
      expect(
        failure(
          _file(
            _unsigned(
              kanaStats: {
                'あ': const <String, Object?>{
                  's': 0,
                  'c': 9223372036854775807,
                  'w': 9223372036854775807,
                },
              },
            ),
          ),
        ),
        SnapshotDecodeError.invalidPayload,
      );
    });
  });

  group('repair D — strict canonical createdAt', () {
    test('an impossible calendar date is invalidEnvelope, never silently '
        'rolled over', () {
      expect(
        failure(_file(_unsigned(createdAt: '2026-02-29T00:00:00.000Z'))),
        SnapshotDecodeError.invalidEnvelope,
      );
      expect(
        failure(_file(_unsigned(createdAt: '2026-02-31T00:00:00.000Z'))),
        SnapshotDecodeError.invalidEnvelope,
      );
    });

    test('a real leap day is accepted', () {
      final r = codec.decodeAndValidate(
        _file(_unsigned(createdAt: '2024-02-29T00:00:00.000Z')),
      );
      expect(r, isA<SnapshotDecodeSuccess>());
    });

    test('a non-UTC createdAt is normalised to a canonical Z instant and stays '
        'deterministic', () {
      final local = DateTime(2026, 7, 24, 21, 30); // local, not UTC
      final s = ProgressSnapshot(
        createdAt: local,
        kanaStats: const {},
        learnedUnits: const {},
        seenUnlocks: const {},
        kanjiReadingStats: const {},
      );
      final bytes = codec.encode(s);
      final createdAt = (jsonDecode(bytes) as Map)['createdAt'] as String;
      expect(createdAt.endsWith('Z'), isTrue);
      final back = decoded(bytes);
      expect(back.createdAtUtc, local.toUtc()); // same instant
      expect(back.createdAtUtc.isUtc, isTrue);
      expect(codec.encode(back), bytes); // deterministic
    });
  });
}
