// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// How one kana was graded in an explicit prior-range check.
///
/// Independent and prompted-correct are distinct. Unknown is an explicit
/// "I don't know / I forgot" — not a missing record. A kana with no
/// [PlacementRecord] is unanswered and must stay that way.
enum PlacementOutcome { independent, prompted, unknown }

/// One completed check answer. Never written for a kana the learner has
/// not yet graded.
class PlacementRecord {
  const PlacementRecord({required this.kanaId, required this.outcome});

  final String kanaId;
  final PlacementOutcome outcome;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': kanaId,
    'out': outcome.name,
  };

  static PlacementRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final outcome = _outcomeNamed(raw['out']);
    if (outcome == null) return null;
    return PlacementRecord(kanaId: id, outcome: outcome);
  }
}

/// In-progress or finished explicit check. [pendingKanaIds] are unanswered;
/// [records] are only real grades. Leaving mid-way must not invent the rest.
///
/// [hintedKanaIds] is exposure, not a grade: a pending kana whose reading
/// was shown this check stays prompted-only across resume. Reloading must
/// not mint a first independent correct from a previously revealed card.
class PlacementDraft {
  const PlacementDraft({
    required this.lessonIds,
    required this.pendingKanaIds,
    required this.records,
    this.hintedKanaIds = const [],
  });

  /// Honest decode: drop corrupt rows, never invent an outcome. If the same
  /// id is both recorded and pending, pending wins (unanswered). Hinted ids
  /// that are no longer pending are dropped — a grade already settled them.
  factory PlacementDraft.fromJson(Map<String, dynamic> json) {
    final lessons = _stringList(json['lessons']);
    final pending = <String>[];
    final pendingSeen = <String>{};
    for (final id in _stringList(json['pending'])) {
      if (pendingSeen.add(id)) pending.add(id);
    }
    final records = <PlacementRecord>[];
    final recorded = <String>{};
    final rawRecords = json['records'];
    if (rawRecords is List<dynamic>) {
      for (final row in rawRecords) {
        final parsed = PlacementRecord.tryParse(row);
        if (parsed == null) continue;
        if (pendingSeen.contains(parsed.kanaId)) continue;
        if (!recorded.add(parsed.kanaId)) continue;
        records.add(parsed);
      }
    }
    final hinted = <String>[];
    final hintedSeen = <String>{};
    for (final id in _stringList(json['hinted'])) {
      if (!pendingSeen.contains(id)) continue;
      if (hintedSeen.add(id)) hinted.add(id);
    }
    return PlacementDraft(
      lessonIds: lessons,
      pendingKanaIds: pending,
      records: records,
      hintedKanaIds: hinted,
    );
  }

  static const PlacementDraft empty = PlacementDraft(
    lessonIds: [],
    pendingKanaIds: [],
    records: [],
  );

  /// Selected lesson ids, in the order the learner asked to check.
  final List<String> lessonIds;

  /// Unanswered kana ids, in session order. Resume asks only these.
  final List<String> pendingKanaIds;

  /// Completed grades. A kana is never both pending and recorded.
  final List<PlacementRecord> records;

  /// Pending kana whose reading was shown this check. Not an outcome.
  final List<String> hintedKanaIds;

  bool get hasSelection => lessonIds.isNotEmpty;

  bool get hasProgress => records.isNotEmpty || pendingKanaIds.isNotEmpty;

  bool get isInProgress => pendingKanaIds.isNotEmpty;

  bool get isComplete =>
      hasSelection && pendingKanaIds.isEmpty && records.isNotEmpty;

  bool isHinted(String kanaId) => hintedKanaIds.contains(kanaId);

  Map<String, Object?> toJson() => <String, Object?>{
    'lessons': lessonIds,
    'pending': pendingKanaIds,
    'records': [for (final r in records) r.toJson()],
    'hinted': hintedKanaIds,
  };
}

PlacementOutcome? _outcomeNamed(Object? raw) {
  if (raw is! String) return null;
  for (final value in PlacementOutcome.values) {
    if (value.name == raw) return value;
  }
  return null;
}

List<String> _stringList(Object? raw) {
  if (raw is! List<dynamic>) return const [];
  return [
    for (final e in raw)
      if (e is String && e.isNotEmpty) e,
  ];
}
