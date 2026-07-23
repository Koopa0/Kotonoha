// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:kotonoha/data/services/preferences_service.dart';

/// In-memory [PreferencesService] double modelled on the legacy
/// shared_preferences plugin (2.x): reads are served from [cache], which
/// mutates BEFORE the platform verdict, while [durable] — the platform's
/// disk — only changes when the platform acknowledges with `true`. After a
/// `false` ([failWrites] / [failRemoves]) or a throw ([throwWrites] /
/// [throwRemoves]) the two layers diverge exactly like the real plugin's
/// cache vs durable storage; a process restart rebuilds the cache from disk
/// ([FakePreferencesService.restarted]).
///
/// [writeLog] records platform-acknowledged writes only — commit order, not
/// cache state. [writeGates] / [removeGates] / [reloadGate] hold a
/// [PlatformGate] the fake parks on mid-operation (after the cache
/// mutation, before the verdict), letting tests freeze the platform
/// deterministically. Writes also yield once to the event loop so
/// interleaving bugs surface: [sawOverlap] flips if two writes are ever in
/// flight at once.
class FakePreferencesService implements PreferencesService {
  FakePreferencesService();

  /// The instance a fresh process would boot with: both layers rebuilt from
  /// [previous]'s durable platform state.
  FakePreferencesService.restarted(FakePreferencesService previous) {
    durable.addAll(previous.durable);
    cache.addAll(previous.durable);
  }

  final Map<String, String> cache = <String, String>{};
  final Map<String, String> durable = <String, String>{};
  final Set<String> failWrites = <String>{};
  final Set<String> failRemoves = <String>{};
  final Set<String> throwWrites = <String>{};
  final Set<String> throwRemoves = <String>{};

  /// Keys whose removal TAKES EFFECT on [durable] and only THEN throws — the
  /// real "native removal succeeded but the platform reply failed" case, where
  /// the caller sees an exception yet the data is genuinely gone. Distinct
  /// from [throwRemoves], which throws BEFORE touching durable storage.
  final Set<String> throwRemovesAfterEffect = <String>{};
  final Map<String, PlatformGate> writeGates = <String, PlatformGate>{};
  final Map<String, PlatformGate> removeGates = <String, PlatformGate>{};
  PlatformGate? reloadGate;
  bool throwReloads = false;
  final List<String> writeLog = <String>[];
  bool sawOverlap = false;
  int _inFlight = 0;

  /// Seeds a settled pre-existing value — cache and durable agree, as if the
  /// key had been written and acknowledged before the test began.
  void seed(String key, String value) {
    cache[key] = value;
    durable[key] = value;
  }

  @override
  String? readString(String key) => cache[key];

  @override
  Future<bool> writeString(String key, String value) async {
    cache[key] = value; // the legacy cache mutates before the verdict
    _inFlight++;
    if (_inFlight > 1) sawOverlap = true;
    await Future<void>.delayed(Duration.zero);
    final gate = writeGates[key];
    if (gate != null) await gate.pass();
    _inFlight--;
    if (throwWrites.contains(key)) throw StateError('write threw: $key');
    if (failWrites.contains(key)) return false;
    durable[key] = value;
    writeLog.add(key);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    cache.remove(key); // the legacy cache mutates before the verdict
    final gate = removeGates[key];
    if (gate != null) await gate.pass();
    if (throwRemoves.contains(key)) throw StateError('remove threw: $key');
    if (failRemoves.contains(key)) return false;
    durable.remove(key);
    if (throwRemovesAfterEffect.contains(key)) {
      throw StateError('remove threw after effect: $key');
    }
    return true;
  }

  /// Mirrors SharedPreferences.reload(): rebuilds the cache from the
  /// platform's durable state. The gate parks while the platform read is in
  /// flight — before the cache is rebuilt.
  @override
  Future<void> reload() async {
    final gate = reloadGate;
    if (gate != null) await gate.pass();
    if (throwReloads) throw StateError('reload threw');
    cache
      ..clear()
      ..addAll(durable);
  }
}

/// Two-phase gate for freezing a fake platform operation deterministically:
/// the operation completes [entered] once it reaches the platform boundary
/// (its cache mutation already applied, verdict still pending) and then
/// parks until [release]. Tests `await entered`, act while the operation is
/// frozen, then call [release] — no event-loop timing guesses.
class PlatformGate {
  final Completer<void> _entered = Completer<void>();
  final Completer<void> _released = Completer<void>();

  /// Completes when an operation has reached the gate.
  Future<void> get entered => _entered.future;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  /// Called by the fake: announce arrival, then park until released.
  Future<void> pass() async {
    if (!_entered.isCompleted) _entered.complete();
    await _released.future;
  }
}
