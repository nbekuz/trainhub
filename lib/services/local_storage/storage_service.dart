import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/storage/storage_keys.dart';

/// Local persistence layer backed by SharedPreferences.
///
/// Provides typed helpers for auth tokens and generic primitives.
class StorageService {
  /// Creates a [StorageService] wrapping an initialized [SharedPreferences].
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  // ── Auth token helpers ────────────────────────────────────────────────────

  /// Persists the auth Bearer token.
  Future<bool> saveToken(String token) =>
      _prefs.setString(StorageKeys.authToken, token);

  /// Returns the stored auth token, or null.
  String? getToken() => _prefs.getString(StorageKeys.authToken);

  /// Removes the auth token.
  Future<bool> removeToken() => _prefs.remove(StorageKeys.authToken);

  /// Persists the refresh token used to renew the access token.
  Future<bool> saveRefreshToken(String token) =>
      _prefs.setString(StorageKeys.refreshToken, token);

  /// Returns the stored refresh token, or null.
  String? getRefreshToken() => _prefs.getString(StorageKeys.refreshToken);

  /// Removes the refresh token.
  Future<bool> removeRefreshToken() => _prefs.remove(StorageKeys.refreshToken);

  /// Clears both access and refresh tokens.
  Future<void> clearAuth() async {
    await removeToken();
    await removeRefreshToken();
  }

  // ── Generic helpers ───────────────────────────────────────────────────────

  /// Saves a string value under [key].
  Future<bool> saveString(String key, String value) =>
      _prefs.setString(key, value);

  /// Reads a string value for [key].
  String? getString(String key) => _prefs.getString(key);

  /// Saves a boolean value under [key].
  Future<bool> saveBool(String key, bool value) => _prefs.setBool(key, value);

  /// Reads a boolean value for [key].
  bool? getBool(String key) => _prefs.getBool(key);

  /// Saves an integer value under [key].
  Future<bool> saveInt(String key, int value) => _prefs.setInt(key, value);

  /// Reads an integer value for [key].
  int? getInt(String key) => _prefs.getInt(key);

  /// Removes a single key.
  Future<bool> remove(String key) => _prefs.remove(key);

  /// Clears all stored values.
  Future<bool> clear() => _prefs.clear();
}
