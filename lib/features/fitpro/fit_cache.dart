import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/exceptions/app_exceptions.dart';
import 'package:trainhub/core/logger/app_logger.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';

/// Durable cache with stale-while-revalidate + offline fallback.
///
/// - Within [freshFor]: return cache, no network.
/// - Within [keepFor] (or any disk age when offline): return cache immediately,
///   refresh silently in background when online.
/// - Network failure: return last cached value if present; otherwise rethrow.
class FitCache {
  FitCache._();
  static final FitCache I = FitCache._();

  static const _prefsKey = 'fit_cache_v2';

  final Map<String, _Entry> _mem = {};
  final Map<String, Future<dynamic>> _inflight = {};
  final _updates = StreamController<String>.broadcast();

  SharedPreferences? _prefs;
  bool _hydrated = false;
  Future<void>? _hydrateFuture;

  /// Emits cache key after a successful network write (or disk hydrate of that key).
  Stream<String> get updates => _updates.stream;

  Future<void> hydrate() {
    return _hydrateFuture ??= _doHydrate();
  }

  Future<void> _doHydrate() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final key = e.key.toString();
            final value = e.value;
            if (value is! Map) continue;
            final atMs = int.tryParse('${value['at']}') ?? 0;
            if (atMs <= 0) continue;
            _mem[key] = _Entry(value['data'], DateTime.fromMillisecondsSinceEpoch(atMs));
          }
        }
      }
    } catch (error, stack) {
      AppLogger.w('FitCache hydrate failed', error, stack);
    } finally {
      _hydrated = true;
    }
  }

  Future<void> _ensureHydrated() async {
    if (_hydrated) return;
    await hydrate();
  }

  T? peek<T>(String key) {
    final entry = _mem[key];
    if (entry == null) return null;
    return _coerce<T>(entry.data);
  }

  /// JSON round-trip loses generic List/Map types — coerce back for callers.
  static T? _coerce<T>(Object? data) {
    if (data is T) return data;
    if (data is Map) {
      final map = <String, dynamic>{
        for (final e in data.entries) e.key.toString(): e.value,
      };
      if (map is T) return map as T;
      try {
        return map as T;
      } catch (_) {}
    }
    if (data is List) {
      final maps = <Map<String, dynamic>>[
        for (final e in data)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      try {
        return maps as T;
      } catch (_) {}
      try {
        return List<dynamic>.from(data) as T;
      } catch (_) {}
    }
    return null;
  }

  /// Age of cached entry, or null if missing.
  Duration? ageOf(String key) {
    final entry = _mem[key];
    if (entry == null) return null;
    return DateTime.now().difference(entry.at);
  }

  Future<T> get<T>({
    required String key,
    required Future<T> Function() fetch,
    Duration freshFor = const Duration(minutes: 2),
    Duration keepFor = const Duration(hours: 24),
    bool force = false,
    bool persist = true,
  }) async {
    await _ensureHydrated();

    final pending = _inflight[key];
    if (pending != null) return await pending as T;

    if (!force) {
      final entry = _mem[key];
      final cached = entry == null ? null : _coerce<T>(entry.data);
      if (cached != null && entry != null) {
        final age = DateTime.now().difference(entry.at);
        if (age <= freshFor) return cached;
        if (age <= keepFor) {
          // Stale-while-revalidate: UI instantly, network silent in background.
          unawaited(_silentRefresh<T>(key, fetch, persist: persist));
          return cached;
        }
        // Very old: prefer network, but fall back to cache if offline.
        try {
          return await _runAwaiting<T>(key, fetch, persist: persist);
        } catch (_) {
          return cached;
        }
      }
    }

    return _runAwaiting<T>(key, fetch, persist: persist);
  }

  Future<void> _silentRefresh<T>(
    String key,
    Future<T> Function() fetch, {
    required bool persist,
  }) async {
    if (_inflight.containsKey(key)) return;
    try {
      await _runAwaiting<T>(key, fetch, persist: persist);
    } catch (_) {
      // Keep serving stale cache; ignore background failures.
    }
  }

  Future<T> _runAwaiting<T>(
    String key,
    Future<T> Function() fetch, {
    required bool persist,
  }) {
    final future = () async {
      try {
        final data = await fetch();
        await _putInternal(key, data, persist: persist);
        unawaited(WorkoutOfflineQueue.I.flush());
        return data;
      } catch (error) {
        final cached = _coerce<T>(_mem[key]?.data);
        if (cached != null) {
          AppLogger.i('FitCache offline fallback for $key: $error');
          return cached;
        }
        await _ensureHydrated();
        final again = _coerce<T>(_mem[key]?.data);
        if (again != null) return again;
        rethrow;
      } finally {
        _inflight.remove(key);
      }
    }();
    _inflight[key] = future;
    return future;
  }

  Future<void> _putInternal(String key, Object? data, {required bool persist}) async {
    _mem[key] = _Entry(data, DateTime.now());
    if (!_updates.isClosed) _updates.add(key);
    if (persist && _isJsonSafe(data)) {
      await _persistDisk();
    }
  }

  void put<T>(String key, T data, {bool persist = true}) {
    _mem[key] = _Entry(data, DateTime.now());
    if (!_updates.isClosed) _updates.add(key);
    if (persist && _isJsonSafe(data)) {
      unawaited(_persistDisk());
    }
  }

  Future<void> _persistDisk() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      for (final e in _mem.entries) {
        if (!_isJsonSafe(e.value.data)) continue;
        out[e.key] = {
          'at': e.value.at.millisecondsSinceEpoch,
          'data': e.value.data,
        };
      }
      await _prefs!.setString(_prefsKey, jsonEncode(out));
    } catch (error, stack) {
      AppLogger.w('FitCache persist failed', error, stack);
    }
  }

  static bool _isJsonSafe(Object? data) {
    try {
      jsonEncode(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Drop one key, a prefix (`chart` drops `chart.*`), or everything.
  void invalidate([String? keyOrPrefix]) {
    if (keyOrPrefix == null) {
      _mem.clear();
    } else {
      _mem.removeWhere((k, _) => k == keyOrPrefix || k.startsWith('$keyOrPrefix.'));
    }
    unawaited(_persistDisk());
  }

  void invalidateAll(Iterable<String> keys) {
    for (final key in keys) {
      _mem.removeWhere((k, _) => k == key || k.startsWith('$key.'));
    }
    unawaited(_persistDisk());
  }

  Future<void> clear() async {
    _mem.clear();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_prefsKey);
  }

  /// True when [error] looks like offline / unreachable.
  static bool isOfflineError(Object error) {
    if (error is NetworkException || error is TimeoutException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('failed host lookup');
  }
}

class _Entry {
  _Entry(this.data, this.at);
  final Object? data;
  final DateTime at;
}
