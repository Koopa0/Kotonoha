// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/models/progress_snapshot.dart';
import 'package:kotonoha/domain/models/word_stat.dart';
import 'package:kotonoha/kanji/domain/models/reading_stat.dart';

/// Typed reason a candidate snapshot was rejected. A caller never has to guess
/// from a bare `FormatException` / `StateError` why an import candidate failed.
enum SnapshotDecodeError {
  /// The bytes were not parseable JSON.
  malformedJson,

  /// The JSON parsed but the envelope shape (top-level object, exact key set,
  /// checksum sub-object, createdAt) is wrong.
  invalidEnvelope,

  /// `kind` is not exactly `kotonoha.progress`.
  wrongKind,

  /// `schemaVersion` is not the integer `2` (absent / 0 / 1 / negative /
  /// future / non-integer — never coerced). v1 is rejected too: no importer
  /// ever shipped for it, and the wire shape changed with the version.
  unsupportedSchemaVersion,

  /// The embedded checksum does not match the canonical payload — the bytes
  /// were (accidentally) altered.
  checksumMismatch,

  /// The envelope and checksum are sound but a payload entry violates a rule
  /// (wrong type, non-finite/negative/fractional number, out-of-range SRS level
  /// or timestamp, correct+wrong > seen, unknown field, non-string/duplicate/
  /// empty id, …).
  invalidPayload,
}

/// Outcome of [ProgressSnapshotCodec.decodeAndValidate].
sealed class SnapshotDecodeResult {
  const SnapshotDecodeResult();
}

/// A fully validated, immutable, deep-copied candidate ready for a future
/// transactional import to apply WITHOUT re-parsing untrusted raw JSON.
final class SnapshotDecodeSuccess extends SnapshotDecodeResult {
  const SnapshotDecodeSuccess(this.snapshot);

  final ProgressSnapshot snapshot;
}

/// A typed rejection. [detail] is a human-readable hint (never the enum's job).
final class SnapshotDecodeFailure extends SnapshotDecodeResult {
  const SnapshotDecodeFailure(this.error, [this.detail]);

  final SnapshotDecodeError error;
  final String? detail;
}

/// Thrown by [ProgressSnapshotCodec.encode] when a snapshot violates the
/// portable contract — a locally-lenient stat (e.g. a hand-seeded primary that
/// `KanaStat.fromJson` parses but the strict decoder would reject) that would
/// otherwise become a self-rejecting, un-importable backup.
///
/// encode fails LOUDLY here rather than emit bytes that its own decoder rejects.
/// It never modifies the snapshot, and never touches any repository or store —
/// it neither salvages nor discards local progress to force a pass.
class SnapshotEncodeException implements Exception {
  const SnapshotEncodeException(this.detail);

  final String detail;

  @override
  String toString() => 'SnapshotEncodeException: $detail';
}

/// Encodes/decodes the portable **Snapshot v2** envelope.
///
/// Envelope (canonical, compact, keys recursively sorted):
/// ```json
/// {
///   "kind": "kotonoha.progress",
///   "schemaVersion": 2,
///   "createdAt": "<UTC ISO-8601 ending in Z>",
///   "payload": {
///     "kanaStats": { "<id>": { s,c,w,l,sl,d,al,vl }, ... },
///     "learnedUnits": [ "<id>", ... ],
///     "seenUnlocks": [ "<id>", ... ],
///     "kanjiReadingStats": { "<id>": { s,c,w,l,sl,d }, ... },
///     "wordStats": { "<word:…|phrase:…>": { s,c,w,l,sl,d }, ... }
///   },
///   "checksum": { "algorithm": "sha256", "value": "<64 lowercase hex>" }
/// }
/// ```
///
/// v2 added `wordStats` (2026-08-27) and became the ONLY accepted version — a
/// v1 envelope is rejected as unsupported rather than upgraded, because no
/// importer ever shipped while v1 was current and two wire shapes must never
/// share a version number.
///
/// The checksum is a SHA-256 over the UTF-8 bytes of the CANONICAL envelope with
/// the `checksum` field removed. It only detects accidental corruption — not a
/// signature. Both [encode] and [decodeAndValidate] hash the SAME canonical form
/// ([_canonical]) of the declared bytes, so identical logical state + createdAt
/// is byte-identical and a canonical export decodes then re-encodes to the exact
/// same bytes.
///
/// Two non-negotiable contracts:
/// * **Self-importable** — [encode]/decode share ONE payload validator
///   ([_payloadError]). encode validates BEFORE hashing/output and throws a
///   typed [SnapshotEncodeException] rather than emit bytes its own
///   [decodeAndValidate] would reject.
/// * **Decoder exception firewall** — [decodeAndValidate] NEVER throws for ANY
///   raw input. Non-finite numbers, out-of-range epoch millis, overflowing
///   counts, and impossible calendar dates are all explicit typed failures, and
///   an outer barrier converts any unforeseen throw into a typed failure too.
///
/// Decode is STRICT and whole-file: any single bad entry rejects the entire
/// candidate — deliberately unlike the local `RecoverableStore`, which salvages
/// good entries from a damaged on-device store.
class ProgressSnapshotCodec {
  const ProgressSnapshotCodec();

  static const String kind = 'kotonoha.progress';
  static const int schemaVersion = 2;
  static const String _algorithm = 'sha256';

  static const Set<String> _topKeys = {
    'kind',
    'schemaVersion',
    'createdAt',
    'payload',
    'checksum',
  };
  static const Set<String> _checksumKeys = {'algorithm', 'value'};
  static const Set<String> _payloadKeys = {
    'kanaStats',
    'learnedUnits',
    'seenUnlocks',
    'kanjiReadingStats',
    'wordStats',
  };

  /// The complete set of wire field names either stat may carry. Kana uses
  /// `al`/`vl` (timed RT/CVRT) and `lm` (last mistake, independent of
  /// lastReviewed). Kanji tolerates the timed/mistake fields as unknown-to-it
  /// extras and ignores them when building its model. Any other field is
  /// rejected.
  static const Set<String> _statFields = {
    's',
    'c',
    'w',
    'l',
    'lm',
    'sl',
    'd',
    'al',
    'vl',
  };

  /// The wire-expressible SRS level range (7 Leitner intervals, indices 0..6).
  static const int _maxSrsLevel = 6;

  /// DateTime's representable range in epoch milliseconds (±271,821 years).
  /// A value outside this throws in `DateTime.fromMillisecondsSinceEpoch`, so a
  /// timestamp out of range is rejected as invalid payload BEFORE any model is
  /// constructed.
  static const int _maxEpochMillis = 8640000000000000;
  static const int _minEpochMillis = -8640000000000000;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  // --- Encode -------------------------------------------------------------

  /// Encodes [snapshot] into the canonical Snapshot v2 string.
  ///
  /// Throws [SnapshotEncodeException] if the snapshot violates the portable
  /// contract (the SAME rules the decoder enforces), so encode can never emit a
  /// self-rejecting, un-importable backup. Validation runs BEFORE the checksum
  /// and output; the snapshot is never modified.
  String encode(ProgressSnapshot snapshot) {
    final unsigned = _unsignedEnvelope(snapshot);
    final error = _payloadError(unsigned['payload']);
    if (error != null) {
      throw SnapshotEncodeException(error);
    }
    final full = <String, Object?>{
      ...unsigned,
      'checksum': <String, Object?>{
        'algorithm': _algorithm,
        'value': _checksum(unsigned),
      },
    };
    return jsonEncode(_canonical(full));
  }

  Map<String, Object?> _unsignedEnvelope(
    ProgressSnapshot s,
  ) => <String, Object?>{
    'kind': kind,
    'schemaVersion': schemaVersion,
    'createdAt': s.createdAtUtc.toIso8601String(),
    'payload': <String, Object?>{
      'kanaStats': <String, Object?>{
        for (final e in s.kanaStats.entries) e.key: e.value.toJson(),
      },
      'learnedUnits': s.learnedUnits.toList(),
      'seenUnlocks': s.seenUnlocks.toList(),
      'kanjiReadingStats': <String, Object?>{
        for (final e in s.kanjiReadingStats.entries) e.key: e.value.toJson(),
      },
      'wordStats': <String, Object?>{
        for (final e in s.wordStats.entries) e.key: e.value.toJson(),
      },
    },
  };

  String _checksum(Map<String, Object?> unsigned) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(unsigned)))).toString();

  // --- Decode -------------------------------------------------------------

  /// Strictly validates [raw] and returns a typed result. Pure and
  /// side-effect-free: it touches no Preferences, no repository memory, and
  /// never mints a last-good / quarantine copy.
  ///
  /// **Never throws.** Every anticipated failure is a typed
  /// [SnapshotDecodeFailure]; an outer barrier turns any unforeseen exception
  /// into one too, so no untrusted input can escape as a raw exception.
  SnapshotDecodeResult decodeAndValidate(String raw) {
    try {
      return _decodeStrict(raw);
    } catch (error) {
      // Last-line firewall. _decodeStrict already types every anticipated
      // failure; this only catches the genuinely unexpected, and never rethrows.
      return SnapshotDecodeFailure(
        SnapshotDecodeError.invalidPayload,
        'unexpected decode error: ${error.runtimeType}',
      );
    }
  }

  SnapshotDecodeResult _decodeStrict(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return const SnapshotDecodeFailure(SnapshotDecodeError.malformedJson);
    }
    if (parsed is! Map<String, dynamic>) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidEnvelope,
        'top level is not a JSON object',
      );
    }
    final top = parsed;

    // kind — absent / wrong-type / wrong-value all read as the wrong kind.
    if (top['kind'] != kind) {
      return const SnapshotDecodeFailure(SnapshotDecodeError.wrongKind);
    }
    // schemaVersion — the integer 2 only; anything else (v1 included) is
    // unsupported.
    final version = top['schemaVersion'];
    if (version is! int || version != schemaVersion) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.unsupportedSchemaVersion,
      );
    }
    // Exact top-level key set (no unknown or missing fields).
    if (!_exactKeys(top, _topKeys)) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidEnvelope,
        'unexpected top-level keys',
      );
    }
    // Checksum envelope: {algorithm: sha256, value: 64 lowercase hex}.
    final checksum = top['checksum'];
    if (checksum is! Map<String, dynamic> ||
        !_exactKeys(checksum, _checksumKeys) ||
        checksum['algorithm'] != _algorithm) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidEnvelope,
        'checksum envelope',
      );
    }
    final checksumValue = checksum['value'];
    if (checksumValue is! String || !_hex64.hasMatch(checksumValue)) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidEnvelope,
        'checksum value',
      );
    }
    // createdAt — a strict, canonical UTC instant. It must end in Z, parse, and
    // round-trip byte-for-byte, so an impossible calendar date (e.g. Feb 29 of a
    // common year) that DateTime.parse silently rolls over is rejected, not
    // normalised.
    final createdAtRaw = top['createdAt'];
    if (createdAtRaw is! String || !createdAtRaw.endsWith('Z')) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidEnvelope,
        'createdAt is not a UTC ISO-8601 string',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null ||
        createdAt.toUtc().toIso8601String() != createdAtRaw) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidEnvelope,
        'createdAt is not a canonical calendar instant',
      );
    }

    final unsigned = Map<String, Object?>.of(top)..remove('checksum');
    // A non-finite number (e.g. 1e309 → Infinity) cannot be canonicalised —
    // jsonEncode throws on Infinity/NaN — so reject it here, before the
    // checksum, as a payload fault rather than let the hash step throw.
    if (_containsNonFinite(unsigned)) {
      return const SnapshotDecodeFailure(
        SnapshotDecodeError.invalidPayload,
        'non-finite number',
      );
    }
    // Integrity BEFORE payload semantics: a payload/createdAt change with a
    // stale checksum reads as checksumMismatch even when the change is itself
    // structurally invalid.
    if (_checksum(unsigned) != checksumValue) {
      return const SnapshotDecodeFailure(SnapshotDecodeError.checksumMismatch);
    }

    // Payload — the SAME strict validator encode uses.
    final payload = top['payload'];
    final payloadError = _payloadError(payload);
    if (payloadError != null) {
      return SnapshotDecodeFailure(
        SnapshotDecodeError.invalidPayload,
        payloadError,
      );
    }

    // Bounds are validated, so model construction cannot throw.
    final p = payload as Map<String, dynamic>;
    final kanaStats = <String, KanaStat>{
      for (final e in (p['kanaStats'] as Map<String, dynamic>).entries)
        e.key: KanaStat.fromJson(e.value as Map<String, dynamic>),
    };
    final kanjiStats = <String, ReadingStat>{
      for (final e in (p['kanjiReadingStats'] as Map<String, dynamic>).entries)
        e.key: ReadingStat.fromJson(e.value as Map<String, dynamic>),
    };
    final wordStats = <String, WordStat>{
      for (final e in (p['wordStats'] as Map<String, dynamic>).entries)
        e.key: WordStat.fromJson(e.value as Map<String, dynamic>),
    };
    final learnedUnits = <String>{
      for (final e in (p['learnedUnits'] as List)) e as String,
    };
    final seenUnlocks = <String>{
      for (final e in (p['seenUnlocks'] as List)) e as String,
    };

    return SnapshotDecodeSuccess(
      ProgressSnapshot(
        createdAt: createdAt,
        kanaStats: kanaStats,
        learnedUnits: learnedUnits,
        seenUnlocks: seenUnlocks,
        kanjiReadingStats: kanjiStats,
        wordStats: wordStats,
      ),
    );
  }

  // --- Shared payload validation (single source of truth) -----------------

  /// The single portable-contract validator, run by BOTH [encode] (on the
  /// payload it is about to sign) and [decodeAndValidate] (on the parsed
  /// payload), so neither side can drift from the other. Returns an error
  /// detail, or null when the payload satisfies the contract.
  String? _payloadError(Object? payload) {
    if (payload is! Map || !_exactKeys(payload, _payloadKeys)) {
      return 'payload sections';
    }
    return _statMapError(payload['kanaStats'], 'kanaStats') ??
        _statMapError(payload['kanjiReadingStats'], 'kanjiReadingStats') ??
        _statMapError(payload['wordStats'], 'wordStats') ??
        _idListError(payload['learnedUnits'], 'learnedUnits') ??
        _idListError(payload['seenUnlocks'], 'seenUnlocks');
  }

  String? _statMapError(Object? raw, String label) {
    if (raw is! Map) return '$label is not an object';
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        return '$label has an empty or non-string id';
      }
      final err = _statError(key, entry.value);
      if (err != null) return err;
    }
    return null;
  }

  /// Strict per-stat validation shared by kana and (legacy-tolerant) kanji
  /// stats: identical allowed field set and numeric constraints — kanji simply
  /// drops `al`/`vl` when building its model. Enforces integer types (no
  /// fractions/strings), non-negative counts/latency/variance, SRS level in
  /// 0..6, in-range integer epoch-millis timestamps, and an OVERFLOW-SAFE
  /// correct+wrong <= seen.
  String? _statError(String id, Object? raw) {
    if (raw is! Map) return 'stat "$id" is not an object';
    for (final key in raw.keys) {
      if (key is! String || !_statFields.contains(key)) {
        return 'unknown stat field "$key" on "$id"';
      }
    }
    for (final key in _statFields) {
      final err = _checkIntType(raw, key, id);
      if (err != null) return err;
    }
    final s = (raw['s'] as int?) ?? 0;
    final c = (raw['c'] as int?) ?? 0;
    final w = (raw['w'] as int?) ?? 0;
    final sl = (raw['sl'] as int?) ?? 0;
    final al = (raw['al'] as int?) ?? 0;
    final vl = (raw['vl'] as int?) ?? 0;
    final l = raw['l'] as int?;
    final lm = raw['lm'] as int?;
    final d = raw['d'] as int?;

    if (s < 0 || c < 0 || w < 0 || al < 0 || vl < 0) {
      return 'negative count on "$id"';
    }
    if (sl < 0 || sl > _maxSrsLevel) return 'srs level out of range on "$id"';
    // Overflow-safe correct + wrong <= seen (operands already non-negative), so
    // int64-max counts can never wrap the comparison into a false pass.
    if (c > s || w > s - c) return 'correct + wrong exceeds seen on "$id"';
    if (l != null && !_epochInRange(l)) {
      return 'lastReviewed timestamp out of range on "$id"';
    }
    if (lm != null && !_epochInRange(lm)) {
      return 'lastMistake timestamp out of range on "$id"';
    }
    if (d != null && !_epochInRange(d)) {
      return 'due timestamp out of range on "$id"';
    }
    return null;
  }

  String? _checkIntType(Map<dynamic, dynamic> raw, String key, String id) {
    if (!raw.containsKey(key)) return null;
    if (raw[key] is! int) return '"$key" must be an integer on "$id"';
    return null;
  }

  String? _idListError(Object? raw, String label) {
    if (raw is! List) return '$label is not a list';
    final seen = <String>{};
    for (final element in raw) {
      if (element is! String) return '$label contains a non-string';
      if (element.isEmpty) return '$label contains an empty id';
      if (!seen.add(element)) return '$label contains a duplicate: "$element"';
    }
    return null;
  }

  bool _epochInRange(int millis) =>
      millis >= _minEpochMillis && millis <= _maxEpochMillis;

  bool _exactKeys(Map<dynamic, dynamic> m, Set<String> expected) {
    if (m.length != expected.length) return false;
    for (final key in expected) {
      if (!m.containsKey(key)) return false;
    }
    return true;
  }

  /// Whether [value] contains a non-finite number anywhere. Such a value cannot
  /// be JSON-encoded, so it is detected before canonicalisation/checksum.
  bool _containsNonFinite(Object? value) {
    if (value is double) return !value.isFinite;
    if (value is Map) {
      for (final v in value.values) {
        if (_containsNonFinite(v)) return true;
      }
      return false;
    }
    if (value is List) {
      for (final v in value) {
        if (_containsNonFinite(v)) return true;
      }
      return false;
    }
    return false;
  }

  /// Rebuilds [value] into canonical form for byte-stable encoding and
  /// checksum: object keys sorted lexicographically (recursively) and arrays
  /// sorted by their elements' canonical JSON, so the output never depends on
  /// Map/Set insertion order.
  ///
  /// MUST NOT throw on malformed input. It runs on untrusted parsed JSON to
  /// VERIFY the checksum BEFORE payload validation, so a fractional number
  /// where an int belongs, a non-string in a set, or a stat that is not an
  /// object must all pass through untouched — payload validation, not this, is
  /// what rejects them. (Non-finite numbers are the one thing it cannot encode,
  /// so they are screened out by [_containsNonFinite] first.)
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
}
