// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over the shared_preferences data source. Keeps the storage
/// mechanism behind a small seam so repositories don't depend on the plugin
/// directly (Flutter official architecture: Service wraps the data source).
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  static Future<PreferencesService> create() async =>
      PreferencesService(await SharedPreferences.getInstance());

  String? readString(String key) => _prefs.getString(key);

  /// True when the platform store accepted the write. shared_preferences
  /// reports failure as a `false` return, not an exception, so callers must
  /// check the result (see `RecoverableStore`).
  Future<bool> writeString(String key, String value) =>
      _prefs.setString(key, value);

  /// True when the platform store accepted the removal.
  Future<bool> remove(String key) => _prefs.remove(key);

  /// Re-reads the platform's durable state into the plugin cache. The legacy
  /// shared_preferences API serves reads from a cache that mutates BEFORE
  /// the platform verdict, so after a failed write/remove the cache can run
  /// ahead of disk — reads are only trustworthy again after this.
  Future<void> reload() => _prefs.reload();

  /// Called before a restore transaction writes primaries. In-flight platform
  /// writes that resume after this must not commit to durable storage.
  void invalidateInFlightWrites() {}
}
