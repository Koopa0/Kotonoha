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

  Future<void> writeString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
