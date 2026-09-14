// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/travel_scene_id.dart';

/// One scene the learner asked to keep preparing, with an optional date.
///
/// The date is a reminder the learner typed — never a countdown, never a
/// completion trigger, and never a personal itinerary baked into the app.
class TravelFocus {
  const TravelFocus({required this.scene, this.date});

  final TravelSceneId scene;

  /// Calendar day only. Time-of-day is ignored.
  final DateTime? date;

  Map<String, Object?> toJson() => <String, Object?>{
    'scene': scene.name,
    if (date != null) 'date': TravelFocusPlan.isoDay(date!),
  };

  static TravelFocus? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final scene = TravelFocusPlan.sceneNamed(raw['scene']);
    if (scene == null) return null;
    return TravelFocus(
      scene: scene,
      date: TravelFocusPlan.dayNamed(raw['date']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TravelFocus && other.scene == scene && other.date == date;

  @override
  int get hashCode => Object.hash(scene, date);
}

/// The learner's retained travel-prep choice and the quiet day-to-day cursor.
///
/// This is a plan, not mastery: clearing or swapping scenes never writes a
/// kana or 詞と句 stat. [kanaBoostOn] / [servedOn] only remember which short
/// Home step already ran, so tomorrow can continue the other scene.
///
/// [focuses] and [servedOn] are copied and sealed at construction so a caller
/// cannot mutate this snapshot — or the repository's canonical plan — through
/// the collections they passed in or the collections they read back.
class TravelFocusPlan {
  TravelFocusPlan({
    List<TravelFocus> focuses = const [],
    this.kanaBoostOn,
    Map<TravelSceneId, DateTime> servedOn = const {},
  }) : focuses = List<TravelFocus>.unmodifiable(List<TravelFocus>.of(focuses)),
       servedOn = Map<TravelSceneId, DateTime>.unmodifiable(
         Map<TravelSceneId, DateTime>.of(servedOn),
       );

  const TravelFocusPlan._empty()
    : focuses = const [],
      kanaBoostOn = null,
      servedOn = const {};

  /// Honest decode: drop unknown scenes and extra rows past [maxFocuses].
  /// Duplicate scenes keep the first. Corrupt dates are ignored, not invented.
  factory TravelFocusPlan.fromJson(Map<String, dynamic> json) {
    final focuses = <TravelFocus>[];
    final seen = <TravelSceneId>{};
    final rawFocuses = json['focuses'];
    if (rawFocuses is List<dynamic>) {
      for (final row in rawFocuses) {
        final parsed = TravelFocus.tryParse(row);
        if (parsed == null) continue;
        if (!seen.add(parsed.scene)) continue;
        focuses.add(parsed);
        if (focuses.length == maxFocuses) break;
      }
    }
    final served = <TravelSceneId, DateTime>{};
    final rawServed = json['served'];
    if (rawServed is Map) {
      rawServed.forEach((key, value) {
        if (key is! String) return;
        final scene = sceneNamed(key);
        final day = dayNamed(value);
        if (scene == null || day == null) return;
        served[scene] = day;
      });
    }
    return TravelFocusPlan(
      focuses: focuses,
      kanaBoostOn: dayNamed(json['kanaBoostOn']),
      servedOn: served,
    );
  }

  static const TravelFocusPlan empty = TravelFocusPlan._empty();

  static const int maxFocuses = 2;

  /// One or two scenes, in the order the learner picked them.
  /// Unmodifiable; the constructor copies the input first.
  final List<TravelFocus> focuses;

  /// Calendar day the Home travel path already ran today's one kana boost.
  final DateTime? kanaBoostOn;

  /// Calendar day each scene was last continued from the Home next step.
  /// Unmodifiable; the constructor copies the input first.
  final Map<TravelSceneId, DateTime> servedOn;

  bool get isActive => focuses.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'focuses': [for (final f in focuses) f.toJson()],
    if (kanaBoostOn != null) 'kanaBoostOn': isoDay(kanaBoostOn!),
    'served': <String, String>{
      for (final e in servedOn.entries) e.key.name: isoDay(e.value),
    },
  };

  TravelFocusPlan withFocuses(Iterable<TravelFocus> next) {
    final focuses = <TravelFocus>[];
    final seen = <TravelSceneId>{};
    for (final focus in next) {
      if (!seen.add(focus.scene)) continue;
      focuses.add(TravelFocus(scene: focus.scene, date: _dateOnly(focus.date)));
      if (focuses.length == maxFocuses) break;
    }
    return TravelFocusPlan(
      focuses: focuses,
      kanaBoostOn: kanaBoostOn,
      servedOn: servedOn,
    );
  }

  TravelFocusPlan markKanaBoost(DateTime now) => TravelFocusPlan(
    focuses: focuses,
    kanaBoostOn: dayOf(now),
    servedOn: servedOn,
  );

  TravelFocusPlan markServed(TravelSceneId scene, DateTime now) =>
      TravelFocusPlan(
        focuses: focuses,
        kanaBoostOn: kanaBoostOn,
        servedOn: {...servedOn, scene: dayOf(now)},
      );

  TravelFocusPlan cleared() => empty;

  static DateTime dayOf(DateTime now) => DateTime(now.year, now.month, now.day);

  static DateTime? _dateOnly(DateTime? date) =>
      date == null ? null : dayOf(date);

  static bool sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String isoDay(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? dayNamed(Object? raw) {
    if (raw is! String || raw.length < 10) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static TravelSceneId? sceneNamed(Object? raw) {
    if (raw is! String) return null;
    for (final scene in TravelSceneId.values) {
      if (scene.name == raw) return scene;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! TravelFocusPlan) return false;
    if (other.kanaBoostOn != kanaBoostOn) return false;
    if (other.focuses.length != focuses.length) return false;
    for (var i = 0; i < focuses.length; i++) {
      if (other.focuses[i] != focuses[i]) return false;
    }
    if (other.servedOn.length != servedOn.length) return false;
    for (final e in servedOn.entries) {
      if (other.servedOn[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(focuses),
    kanaBoostOn,
    Object.hashAll(servedOn.entries),
  );
}
