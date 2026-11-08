import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/workout_timer.dart';

/// Durable offline queue for live workout mutations (§41).
class WorkoutOfflineQueue {
  WorkoutOfflineQueue._();
  static final WorkoutOfflineQueue I = WorkoutOfflineQueue._();

  static const _opsKey = 'workout_offline_ops_v1';
  static const _snapPrefix = 'workout_session_snap_';
  static const _activeKey = 'workout_active_session_id_v1';

  /// Notifies shell mini-card when active live session changes.
  final ValueNotifier<int?> activeSession = ValueNotifier<int?>(null);

  /// Hide floating mini-card while the live session screen is open.
  final ValueNotifier<bool> suppressMiniCard = ValueNotifier<bool>(false);

  /// Bumps when snapshot / pause state changes so the mini-card timer refreshes.
  final ValueNotifier<int> activeMetaEpoch = ValueNotifier<int>(0);

  void _bumpMeta() => activeMetaEpoch.value = activeMetaEpoch.value + 1;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> setActiveSessionId(int? sessionId) async {
    final prefs = await _prefs;
    final next = (sessionId == null || sessionId <= 0) ? null : sessionId;
    if (next == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setInt(_activeKey, next);
    }
    if (activeSession.value != next) {
      activeSession.value = next;
    }
  }

  Future<int?> activeSessionId() async {
    final id = (await _prefs).getInt(_activeKey);
    if (id == null || id <= 0) return null;
    if (activeSession.value != id) activeSession.value = id;
    return id;
  }

  /// Hydrate notifier from disk (call on shell start).
  Future<int?> restoreActiveSession() async {
    final id = (await _prefs).getInt(_activeKey);
    final next = (id == null || id <= 0) ? null : id;
    if (activeSession.value != next) activeSession.value = next;
    return next;
  }

  Future<List<Map<String, dynamic>>> _loadOps() async {
    final raw = (await _prefs).getString(_opsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final item in decoded.whereType<Map>())
        Map<String, dynamic>.from(item),
    ];
  }

  Future<void> _saveOps(List<Map<String, dynamic>> ops) async {
    await (await _prefs).setString(_opsKey, jsonEncode(ops));
  }

  Future<void> saveSessionSnapshot(int sessionId, Map<String, dynamic> session) async {
    final anchored = WorkoutTimer.withStartAnchor(session);
    await (await _prefs).setString('$_snapPrefix$sessionId', jsonEncode(anchored));
    final status = anchored['status']?.toString();
    if (status == 'completed' || status == 'cancelled' || status == 'abandoned') {
      final active = await activeSessionId();
      if (active == sessionId) await setActiveSessionId(null);
    } else {
      await setActiveSessionId(sessionId);
    }
    _bumpMeta();
  }

  Future<Map<String, dynamic>> pauseActiveLocally(int sessionId) async {
    final snap = await sessionSnapshot(sessionId) ?? <String, dynamic>{'id': sessionId};
    final next = WorkoutTimer.withPause(snap);
    await saveSessionSnapshot(sessionId, next);
    return next;
  }

  Future<Map<String, dynamic>> resumeActiveLocally(int sessionId) async {
    final snap = await sessionSnapshot(sessionId) ?? <String, dynamic>{'id': sessionId};
    final next = WorkoutTimer.withResume(snap);
    await saveSessionSnapshot(sessionId, next);
    return next;
  }

  Future<Map<String, dynamic>?> sessionSnapshot(int sessionId) async {
    final raw = (await _prefs).getString('$_snapPrefix$sessionId');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> clearSessionSnapshot(int sessionId) async {
    await (await _prefs).remove('$_snapPrefix$sessionId');
    final active = await activeSessionId();
    if (active == sessionId) await setActiveSessionId(null);
  }

  /// Returns local snapshot of the active in-progress session, if any.
  Future<Map<String, dynamic>?> activeSessionSnapshot() async {
    final id = await activeSessionId();
    if (id == null) return null;
    return sessionSnapshot(id);
  }

  Future<int> pendingCount({int? sessionId}) async {
    final ops = await _loadOps();
    if (sessionId == null) return ops.length;
    return ops.where((o) => o['session_id'] == sessionId).length;
  }

  Future<void> enqueue(Map<String, dynamic> op) async {
    final ops = await _loadOps();
    ops.add(op);
    await _saveOps(ops);
  }

  /// Replay pending ops in order. Stops a session chain on first failure.
  Future<int> flush() async {
    final ops = await _loadOps();
    if (ops.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    final blockedSessions = <int>{};
    var synced = 0;
    for (final op in ops) {
      final sessionId = int.tryParse('${op['session_id']}') ?? 0;
      if (blockedSessions.contains(sessionId)) {
        remaining.add(op);
        continue;
      }
      try {
        await _apply(op);
        synced += 1;
      } catch (_) {
        remaining.add(op);
        if (sessionId != 0) blockedSessions.add(sessionId);
      }
    }
    await _saveOps(remaining);
    return synced;
  }

  Future<void> _apply(Map<String, dynamic> op) async {
    final type = op['type']?.toString();
    final sessionId = int.tryParse('${op['session_id']}') ?? 0;
    if (sessionId == 0) return;
    switch (type) {
      case 'add_exercise':
        await FitApi.addSessionExercise(
          sessionId,
          exerciseId: int.parse('${op['exercise_id']}'),
          restSec: op['rest_sec'] == null ? null : int.tryParse('${op['rest_sec']}'),
        );
      case 'add_set':
        await FitApi.addSessionSet(
          sessionId,
          int.parse('${op['se_id']}'),
          weightKg: op['weight_kg'] == null ? null : num.tryParse('${op['weight_kg']}'),
          reps: op['reps'] == null ? null : int.tryParse('${op['reps']}'),
          isWarmup: op['is_warmup'] == true,
          clientOpId: op['client_op_id']?.toString(),
        );
      case 'patch_set':
        await FitApi.patchSessionSet(
          sessionId,
          int.parse('${op['set_id']}'),
          weightKg: op['weight_kg'] == null ? null : num.tryParse('${op['weight_kg']}'),
          reps: op['reps'] == null ? null : int.tryParse('${op['reps']}'),
        );
      case 'complete':
        await FitApi.completeSession(sessionId);
        await clearSessionSnapshot(sessionId);
      case 'pause':
        final paused = await FitApi.pauseSession(sessionId);
        await saveSessionSnapshot(sessionId, paused);
      case 'resume':
        final resumed = await FitApi.resumeSession(sessionId);
        await saveSessionSnapshot(sessionId, resumed);
      default:
        break;
    }
  }
}
