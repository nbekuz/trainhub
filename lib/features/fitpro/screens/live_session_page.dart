import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/features/fitpro/workout_timer.dart';
import 'package:trainhub/routes/route_names.dart';

/// Live workout: sets with +/- steppers, previous results, offline queue.
class LiveSessionPage extends StatefulWidget {
  const LiveSessionPage({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> with WidgetsBindingObserver {
  Map<String, dynamic> _session = const {};
  List<Map<String, dynamic>> _catalog = const [];
  final Map<String, List<Map<String, dynamic>>> _previousByExercise = {};
  final Map<int, Timer> _patchTimers = {};
  int? _selectedClientId;
  bool _loading = true;
  bool _busy = false;
  bool _offline = false;
  int _pendingOps = 0;
  final Map<int, int> _activeIndexByClient = {};

  // Elapsed workout clock + offline sync
  Timer? _elapsedTimer;
  Timer? _syncTimer;
  Duration _elapsed = Duration.zero;

  /// Exercises of every participant.
  List<Map<String, dynamic>> get _allExercises {
    final raw = _session['exercises'] ?? _session['items'] ?? _session['session_exercises'];
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  /// Exercises on the selected client's screen; `client_id` null = shared by everyone.
  List<Map<String, dynamic>> get _exercises => _allExercises.where((ex) {
    final owner = int.tryParse('${ex['client_id']}');
    return owner == null || _selectedClientId == null || owner == _selectedClientId;
  }).toList();

  int get _activeExerciseIndex => _activeIndexByClient[_selectedClientId ?? 0] ?? 0;
  set _activeExerciseIndex(int value) => _activeIndexByClient[_selectedClientId ?? 0] = value;

  Map<String, dynamic>? get _activeExercise {
    final list = _exercises;
    if (list.isEmpty) return null;
    if (_activeExerciseIndex >= list.length) return list.last;
    return list[_activeExerciseIndex];
  }

  static bool _setDone(Map<String, dynamic> set) {
    if (set['completed_at'] != null) return true;
    final w = set['weight_kg'];
    if (w == null) return false;
    final text = w.toString().trim();
    return text.isNotEmpty && text != 'null';
  }

  /// First name; adds the surname initial when another participant has the same first name.
  String _clientLabel(Map<String, dynamic> client) {
    final first = client['first_name']?.toString().trim() ?? '';
    final last = client['last_name']?.toString().trim() ?? '';
    final namesakes = _clients.where((c) => (c['first_name']?.toString().trim() ?? '') == first).length;
    return namesakes > 1 && last.isNotEmpty ? '$first\u00A0${last[0]}.' : first;
  }

  List<Map<String, dynamic>> get _clients {
    final raw = _session['clients'];
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  static List<Map<String, dynamic>> _setsOf(Map<String, dynamic>? ex) {
    final raw = ex?['sets'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  static String _exerciseName(Map<String, dynamic>? ex) =>
      ex?['name']?.toString() ?? ex?['exercise_name']?.toString() ?? ex?['title']?.toString() ?? 'Упражнение';

  static String _fmtKg(Object? raw) {
    final v = num.tryParse('$raw');
    if (v == null) return '—';
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  String _prevKey(int exerciseId) => '${_selectedClientId ?? 0}:$exerciseId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WorkoutOfflineQueue.I.suppressMiniCard.value = true;
    WorkoutOfflineQueue.I.setActiveSessionId(widget.sessionId);
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickElapsed());
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) => _tryAutoSync());
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WorkoutOfflineQueue.I.suppressMiniCard.value = false;
    _elapsedTimer?.cancel();
    _syncTimer?.cancel();
    // Leaving via the bottom menu must not drop set edits still waiting for the debounce.
    for (final setId in _patchTimers.keys.toList()) {
      _patchTimers[setId]?.cancel();
      for (final ex in _allExercises) {
        for (final s in _setsOf(ex)) {
          if ('${s['id']}' != '$setId') continue;
          unawaited(_sendSetPatch(setId, num.tryParse('${s['weight_kg']}') ?? 0, int.tryParse('${s['reps']}') ?? 0));
        }
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryAutoSync();
      _tickElapsed();
    }
  }

  bool get _timerPaused => WorkoutTimer.isPaused(_session);

  void _tickElapsed() {
    if (!mounted || _session.isEmpty) return;
    if (_timerPaused) {
      final frozen = WorkoutTimer.elapsed(_session);
      if (frozen.inSeconds != _elapsed.inSeconds) {
        setState(() => _elapsed = frozen);
      }
      return;
    }
    final next = WorkoutTimer.elapsed(_session);
    if (next.inSeconds == _elapsed.inSeconds) return;
    setState(() => _elapsed = next);
  }

  Future<void> _pauseWorkout() async {
    if (_timerPaused || _session.isEmpty) return;
    final local = WorkoutTimer.withPause(_session);
    setState(() {
      _session = local;
      _elapsed = WorkoutTimer.elapsed(local);
    });
    await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, local);
    try {
      final remote = await FitApi.pauseSession(widget.sessionId);
      final merged = WorkoutTimer.withStartAnchor({...local, ...remote});
      if (!mounted) return;
      setState(() {
        _session = merged;
        _elapsed = WorkoutTimer.elapsed(merged);
        _offline = false;
      });
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, merged);
    } catch (_) {
      await WorkoutOfflineQueue.I.enqueue({'type': 'pause', 'session_id': widget.sessionId});
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _resumeWorkout() async {
    if (!_timerPaused || _session.isEmpty) return;
    final local = WorkoutTimer.withResume(_session);
    setState(() {
      _session = local;
      _elapsed = WorkoutTimer.elapsed(local);
    });
    await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, local);
    try {
      final remote = await FitApi.resumeSession(widget.sessionId);
      final merged = WorkoutTimer.withStartAnchor({...local, ...remote});
      if (!mounted) return;
      setState(() {
        _session = merged;
        _elapsed = WorkoutTimer.elapsed(merged);
        _offline = false;
      });
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, merged);
    } catch (_) {
      await WorkoutOfflineQueue.I.enqueue({'type': 'resume', 'session_id': widget.sessionId});
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _toggleWorkoutPause() async {
    if (_busy) return;
    if (_timerPaused) {
      await _resumeWorkout();
    } else {
      await _pauseWorkout();
    }
  }

  Future<void> _tryAutoSync() async {
    if (!mounted || _busy) return;
    final pending = await WorkoutOfflineQueue.I.pendingCount(sessionId: widget.sessionId);
    if (pending == 0 && !_offline) return;
    try {
      final synced = await WorkoutOfflineQueue.I.flush();
      if (!mounted) return;
      if (synced > 0) {
        await _reload();
        if (mounted && !_offline) Toast.success('Синхронизировано');
      } else if (_offline) {
        // Still offline — keep local snapshot.
        final count = await WorkoutOfflineQueue.I.pendingCount(sessionId: widget.sessionId);
        if (mounted) setState(() => _pendingOps = count);
      }
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    await WorkoutOfflineQueue.I.flush();
    await _reload();
    _tickElapsed();
  }

  /// Back / system pop: silent minimize — mini-card resumes later.
  Future<void> _minimizeAndLeave() async {
    await WorkoutOfflineQueue.I.setActiveSessionId(widget.sessionId);
    if (_session.isNotEmpty) {
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, _session);
    }
    await WorkoutOfflineQueue.I.flush();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final session = await FitApi.session(widget.sessionId);
      List<Map<String, dynamic>> catalog = _catalog;
      try {
        catalog = await FitApi.exercises();
      } catch (_) {}
      final status = session['status']?.toString() ?? '';
      if (status == 'abandoned' || status == 'cancelled' || status == 'completed') {
        await WorkoutOfflineQueue.I.clearSessionSnapshot(widget.sessionId);
        if (!mounted) return;
        setState(() => _loading = false);
        if (status == 'abandoned') {
          Toast.info('Тренировка закрыта: больше часа без активности');
        }
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      final anchored = WorkoutTimer.withStartAnchor(session);
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, anchored);
      final pending = await WorkoutOfflineQueue.I.pendingCount(sessionId: widget.sessionId);
      if (!mounted) return;
      setState(() {
        _session = anchored;
        _catalog = catalog;
        _offline = false;
        _pendingOps = pending;
        _loading = false;
        _elapsed = WorkoutTimer.elapsed(anchored);
        final ids = _clients.map((c) => int.tryParse('${c['id']}')).whereType<int>().toList();
        if (_selectedClientId == null || !ids.contains(_selectedClientId)) {
          _selectedClientId = int.tryParse('${anchored['lead_client_id']}') ?? (ids.isEmpty ? null : ids.first);
        }
      });
      await _loadPreviousForActive();
    } catch (error) {
      final snap = await WorkoutOfflineQueue.I.sessionSnapshot(widget.sessionId);
      if (!mounted) return;
      if (snap != null) {
        setState(() {
          _session = snap;
          _offline = true;
          _loading = false;
        });
        Toast.info('Офлайн-режим: изменения сохранятся локально');
      } else {
        setState(() => _loading = false);
        Toast.error(FitApi.messageOf(error));
      }
    }
  }

  Future<void> _loadPreviousForActive() async {
    final ex = _activeExercise;
    if (ex == null) return;
    final exerciseId = int.tryParse('${ex['exercise_id']}') ?? 0;
    final key = _prevKey(exerciseId);
    if (exerciseId == 0 || _previousByExercise.containsKey(key)) return;
    try {
      final prev = await FitApi.previousExerciseSets(widget.sessionId, exerciseId, clientId: _selectedClientId);
      if (!mounted) return;
      setState(() => _previousByExercise[key] = prev);
    } catch (_) {}
  }

  /// Values for a new set: copy the exercise's last set, else the last set of the previous workout.
  ({num weight, int reps}) _nextSetValues(Map<String, dynamic> ex) {
    final sets = _setsOf(ex);
    final exerciseId = int.tryParse('${ex['exercise_id']}') ?? 0;
    final previous = _previousByExercise[_prevKey(exerciseId)] ?? const [];
    final source = sets.isNotEmpty ? sets.last : (previous.isNotEmpty ? previous.last : null);
    return (weight: num.tryParse('${source?['weight_kg']}') ?? 40, reps: int.tryParse('${source?['reps']}') ?? 10);
  }

  Future<void> _selectClient(int clientId) async {
    if (_selectedClientId == clientId) return;
    setState(() => _selectedClientId = clientId);
    await _loadPreviousForActive();
  }

  Future<void> _addClient() async {
    final user = ProviderScope.containerOf(context, listen: false).read(fitSessionProvider).user;
    if (user?.role != FitRole.trainer) {
      Toast.info('Добавлять клиентов может только тренер');
      return;
    }
    List<FitClient> all;
    try {
      all = await FitApi.trainerClients();
    } catch (e) {
      Toast.error(FitApi.messageOf(e));
      return;
    }
    final inSession = _clients.map((c) => int.tryParse('${c['id']}')).whereType<int>().toSet();
    final candidates = all.where((c) => !inSession.contains(c.userId)).toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      Toast.info('Все клиенты уже в тренировке');
      return;
    }
    final picked = await showBlurredModalBottomSheet<FitClient>(
      context: context,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 72,
              height: 5,
              decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Добавить клиента',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: candidates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = candidates[i];
                  return Material(
                    color: const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onTap: () => Navigator.pop(ctx, c),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF3A3A3A),
                        child: Text(
                          c.initials,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text('${c.name} ${c.surname}'.trim(), style: const TextStyle(color: Colors.white)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final session = await FitApi.addSessionClient(widget.sessionId, picked.userId);
      await _applySession(WorkoutTimer.withStartAnchor(session));
      if (!mounted) return;
      Toast.success('Клиент добавлен');
      await _selectClient(picked.userId);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sets stay editable: optimistic local update, debounced PATCH (queued offline).
  void _editSet(Map<String, dynamic> set, {num? weight, int? reps}) {
    final setId = int.tryParse('${set['id']}') ?? 0;
    final exercises = _allExercises;
    num? newWeight;
    int? newReps;
    for (final ex in exercises) {
      final sets = _setsOf(ex);
      final idx = sets.indexWhere((s) => '${s['id']}' == '${set['id']}');
      if (idx < 0) continue;
      final current = sets[idx];
      newWeight = weight ?? num.tryParse('${current['weight_kg']}') ?? 0;
      newReps = reps ?? int.tryParse('${current['reps']}') ?? 0;
      sets[idx] = {...current, 'weight_kg': newWeight, 'reps': newReps};
      ex['sets'] = sets;
      break;
    }
    if (newWeight == null || newReps == null) return;
    setState(() => _session = {..._session, 'exercises': exercises});
    if (setId <= 0) return;
    final w = newWeight;
    final r = newReps;
    _patchTimers[setId]?.cancel();
    _patchTimers[setId] = Timer(const Duration(milliseconds: 600), () => _sendSetPatch(setId, w, r));
  }

  Future<void> _sendSetPatch(int setId, num weight, int reps) async {
    _patchTimers.remove(setId);
    try {
      await FitApi.patchSessionSet(widget.sessionId, setId, weightKg: weight, reps: reps);
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, _session);
    } catch (_) {
      await WorkoutOfflineQueue.I.enqueue({
        'type': 'patch_set',
        'session_id': widget.sessionId,
        'set_id': setId,
        'weight_kg': weight,
        'reps': reps,
      });
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, _session);
      if (mounted) {
        setState(() {
          _offline = true;
          _pendingOps += 1;
        });
      }
    }
  }

  Future<void> _deleteSet(Map<String, dynamic> set) async {
    final setId = int.tryParse('${set['id']}') ?? 0;
    if (setId <= 0) {
      Toast.info('Сначала синхронизируйте подход');
      return;
    }
    _patchTimers.remove(setId)?.cancel();
    setState(() => _busy = true);
    try {
      final session = await FitApi.deleteSessionSet(widget.sessionId, setId);
      await _applySession(WorkoutTimer.withStartAnchor(session));
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applySession(Map<String, dynamic> session) async {
    await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, session);
    final pending = await WorkoutOfflineQueue.I.pendingCount(sessionId: widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _pendingOps = pending;
      _offline = false;
    });
  }

  Future<void> _deleteActiveExercise() async {
    final ex = _activeExercise;
    if (ex == null) return;
    final seId = int.tryParse('${ex['id']}') ?? 0;
    if (seId <= 0) {
      Toast.info('Сначала синхронизируйте упражнение');
      return;
    }
    final name = ex['name']?.toString() ?? ex['exercise_name']?.toString() ?? 'упражнение';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Убрать упражнение?', style: TextStyle(color: Colors.white)),
        content: Text('«$name» будет удалено из этой тренировки.', style: const TextStyle(color: AppColors.fitGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Убрать', style: TextStyle(color: Color(0xFFFD6565))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final session = await FitApi.deleteSessionExercise(widget.sessionId, seId);
      await _applySession(session);
      final list = _exercises;
      setState(() {
        _activeExerciseIndex = list.isEmpty ? 0 : _activeExerciseIndex.clamp(0, list.length - 1);
      });
      await _loadPreviousForActive();
      if (mounted) Toast.success('Упражнение убрано');
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExercise() async {
    if (_catalog.isEmpty) {
      try {
        _catalog = await FitApi.exercises();
      } catch (_) {}
    }
    if (!mounted) return;
    if (_catalog.isEmpty) {
      Toast.info('Каталог упражнений пуст');
      return;
    }
    var query = '';
    final selected = await showBlurredModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? _catalog
              : _catalog.where((item) {
                  final name = (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
                  final muscle = FitLabels.muscle((item['primary_muscle'] ?? item['muscle'])?.toString()).toLowerCase();
                  final desc = (item['description'] ?? item['technique'] ?? '').toString().toLowerCase();
                  return name.contains(q) || muscle.contains(q) || desc.contains(q);
                }).toList();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.78,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 72,
                  height: 5,
                  decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Добавить упражнение',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await context.push(RouteNames.createExercise);
                          try {
                            final catalog = await FitApi.exercises();
                            if (mounted) setState(() => _catalog = catalog);
                          } catch (_) {}
                        },
                        child: const Text(
                          'Создать',
                          style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    autofocus: false,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Найти упражнение',
                      hintStyle: const TextStyle(color: Color(0xFF979797)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF979797)),
                      filled: true,
                      fillColor: const Color(0xFF232323),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF323232)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF323232)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.accent),
                      ),
                    ),
                    onChanged: (value) => setModal(() => query = value),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('Ничего не найдено', style: TextStyle(color: AppColors.fitGrey)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final item = filtered[i];
                            final name = item['name']?.toString() ?? item['title']?.toString() ?? 'Упражнение';
                            final muscle = FitLabels.muscle((item['primary_muscle'] ?? item['muscle'])?.toString());
                            final desc = (item['description'] ?? item['technique'] ?? '').toString().trim();
                            return Material(
                              color: const Color(0xFF2C2C2C),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(ctx, item),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FitExerciseThumb.fromExercise(item, size: 48),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                            ),
                                            if (muscle.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF292929),
                                                  borderRadius: BorderRadius.circular(111),
                                                  border: Border.all(color: const Color(0xFF323232)),
                                                ),
                                                child: Text(
                                                  muscle,
                                                  style: const TextStyle(color: Color(0xFF979797), fontSize: 12),
                                                ),
                                              ),
                                            ],
                                            if (desc.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                desc,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.fitGrey,
                                                  fontSize: 12,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (selected == null) return;
    final id = int.tryParse('${selected['id']}') ?? 0;
    if (id == 0) return;
    setState(() => _busy = true);
    var added = false;
    final clientId = _selectedClientId;
    try {
      final session = await FitApi.addSessionExercise(
        widget.sessionId,
        exerciseId: id,
        restSec: 90,
        clientId: clientId,
      );
      await _applySession(session);
      setState(() => _activeExerciseIndex = _exercises.length - 1);
      await _loadPreviousForActive();
      added = true;
      if (mounted) Toast.success('Упражнение добавлено');
    } catch (_) {
      await WorkoutOfflineQueue.I.enqueue({
        'type': 'add_exercise',
        'session_id': widget.sessionId,
        'exercise_id': id,
        'rest_sec': 90,
        if (clientId != null) 'client_id': clientId,
      });
      // Optimistic local append
      final local = Map<String, dynamic>.from(_session);
      final list = [
        ..._allExercises,
        {
          'id': -DateTime.now().millisecondsSinceEpoch,
          'exercise_id': id,
          'name': selected['name'] ?? selected['title'] ?? 'Упражнение',
          'rest_sec': 90,
          'client_id': clientId,
          'sets': <Map<String, dynamic>>[],
          '_local': true,
        },
      ];
      local['exercises'] = list;
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, local);
      if (!mounted) return;
      setState(() {
        _session = local;
        _offline = true;
        _activeExerciseIndex = _exercises.length - 1;
        _pendingOps += 1;
      });
      Toast.info('Сохранено офлайн');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // A new exercise starts with one editable set.
    if (added && mounted) await _addSet();
  }

  /// Adds an editable set to the active exercise.
  Future<void> _addSet() async {
    final ex = _activeExercise;
    if (ex == null) return;
    final seId = int.tryParse('${ex['id']}') ?? 0;
    if (seId <= 0) {
      Toast.info('Сначала синхронизируйте упражнение');
      return;
    }
    final (:weight, :reps) = _nextSetValues(ex);
    setState(() => _busy = true);
    final opId = 'set_${widget.sessionId}_${seId}_${DateTime.now().microsecondsSinceEpoch}';
    try {
      final session = await FitApi.addSessionSet(
        widget.sessionId,
        seId,
        weightKg: weight,
        reps: reps,
        clientOpId: opId,
      );
      await _applySession(session);
    } catch (_) {
      await WorkoutOfflineQueue.I.enqueue({
        'type': 'add_set',
        'session_id': widget.sessionId,
        'se_id': seId,
        'weight_kg': weight,
        'reps': reps,
        'is_warmup': false,
        'client_op_id': opId,
      });
      final local = Map<String, dynamic>.from(_session);
      final exercises = _allExercises.map((e) => Map<String, dynamic>.from(e)).toList();
      final idx = exercises.indexWhere((e) => '${e['id']}' == '${ex['id']}');
      if (idx < 0) return;
      final existing = (exercises[idx]['sets'] is List)
          ? (exercises[idx]['sets'] as List).whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList()
          : <Map<String, dynamic>>[];
      final pendingIdx = existing.indexWhere((s) => s['completed_at'] == null && s['weight_kg'] == null);
      if (pendingIdx >= 0) {
        existing[pendingIdx] = {
          ...existing[pendingIdx],
          'weight_kg': weight,
          'reps': reps,
          'completed_at': DateTime.now().toIso8601String(),
          '_local': true,
        };
      } else {
        existing.add({
          'id': -DateTime.now().millisecondsSinceEpoch,
          'weight_kg': weight,
          'reps': reps,
          'set_index': existing.length + 1,
          'completed_at': DateTime.now().toIso8601String(),
          '_local': true,
        });
      }
      final sets = existing;
      exercises[idx]['sets'] = sets;
      local['exercises'] = exercises;
      await WorkoutOfflineQueue.I.saveSessionSnapshot(widget.sessionId, local);
      if (!mounted) return;
      setState(() {
        _session = local;
        _offline = true;
        _pendingOps += 1;
      });
      Toast.info('Подход сохранён офлайн');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      await WorkoutOfflineQueue.I.flush();
      await _reload();
      if (mounted && !_offline) Toast.success('Синхронизировано');
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeExercise() async {
    final ex = _activeExercise;
    final seId = int.tryParse('${ex?['id']}') ?? 0;
    if (seId <= 0) return;
    final sets = ex != null && ex['sets'] is List
        ? (ex['sets'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final doneSets = sets.where(_setDone).length;
    if (doneSets == 0) {
      Toast.info('Добавьте хотя бы один подход');
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await FitApi.completeSessionExercise(widget.sessionId, seId);
      if (!mounted) return;
      setState(() {
        _session = updated;
        _busy = false;
      });
      Toast.success('Упражнение завершено');
      // Move to next incomplete exercise if any.
      final list = _exercises;
      final next = list.indexWhere((e) => (e['status']?.toString() ?? '') != 'done');
      if (next >= 0) {
        setState(() => _activeExerciseIndex = next);
        await _loadPreviousForActive();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        Toast.error(FitApi.messageOf(e));
      }
    }
  }

  Future<void> _complete({bool confirm = true}) async {
    if (confirm) {
      final incomplete = _allExercises.where((e) => (e['status']?.toString() ?? '') != 'done').length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.fitCard,
          title: const Text('Закончить тренировку?', style: TextStyle(color: Colors.white)),
          content: Text(
            incomplete > 0
                ? 'Есть незавершённые упражнения ($incomplete). Всё равно завершить тренировку?'
                : 'Сохранить результаты и открыть итоги?',
            style: const TextStyle(color: AppColors.fitGrey),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Вернуться')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Закончить', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await WorkoutOfflineQueue.I.flush();
      await FitApi.completeSession(widget.sessionId);
      await WorkoutOfflineQueue.I.clearSessionSnapshot(widget.sessionId);
      if (!mounted) return;
      Toast.success('Тренировка завершена');
      // Show summary, then leave.
      if (mounted) {
        await context.push(RouteNames.sessionDetail, extra: widget.sessionId);
      }
      if (mounted) context.pop(true);
    } catch (_) {
      await WorkoutOfflineQueue.I.enqueue({'type': 'complete', 'session_id': widget.sessionId});
      if (!mounted) return;
      Toast.info('Завершение сохранится при появлении сети');
      if (mounted) context.pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _cardBg = Color(0xFF232323);
  static const _innerBg = Color(0xFF292929);
  static const _chipBg = Color(0xFF323232);
  static const _danger = Color(0xFFFD6565);

  @override
  Widget build(BuildContext context) {
    final ex = _activeExercise;
    final exerciseId = int.tryParse('${ex?['exercise_id']}') ?? 0;
    final previous = _previousByExercise[_prevKey(exerciseId)] ?? const <Map<String, dynamic>>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _minimizeAndLeave();
      },
      child: FitScaffold(
        child: Column(
          children: [
            _buildClientsHeader(),
            const Divider(height: 1, thickness: 1, color: _chipBg),
            if (_offline || _pendingOps > 0) _buildSyncBanner(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        Container(
                          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(24)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCardTopRow(ex),
                              if (ex == null) _buildEmptyExercise() else _buildExerciseCard(ex, previous),
                              ..._buildOtherExercises(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _LiveButton.outlined(title: '+ Добавить упражнения', onPressed: _busy ? null : _addExercise),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientsHeader() {
    final clients = _clients;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: _minimizeAndLeave,
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: clients.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final c = clients[i];
                  final id = int.tryParse('${c['id']}') ?? 0;
                  return _ClientAvatar(
                    name: c['first_name']?.toString() ?? '',
                    surname: c['last_name']?.toString() ?? '',
                    label: _clientLabel(c),
                    avatarUrl: FitMedia.url(c['avatar_url']?.toString()),
                    selected: id == _selectedClientId,
                    onTap: () => _selectClient(id),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _cardBg,
            shape: const CircleBorder(side: BorderSide(color: _chipBg)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _busy ? null : _addClient,
              child: const SizedBox(width: 46, height: 46, child: Icon(Icons.add, color: Colors.white, size: 24)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(_offline ? Icons.cloud_off : Icons.cloud_upload_outlined, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _offline ? 'Офлайн · в очереди $_pendingOps' : 'Ожидает синхронизации: $_pendingOps',
              style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _syncNow,
            child: const Text('Синхр.', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTopRow(Map<String, dynamic>? ex) {
    final muscle = FitLabels.muscle((ex?['primary_muscle'] ?? ex?['muscle'])?.toString());
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(111),
                  onTap: _busy ? null : _toggleWorkoutPause,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: _chipBg, borderRadius: BorderRadius.circular(111)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _timerPaused ? Icons.pause_circle_outline : Icons.timer_outlined,
                          color: _timerPaused ? const Color(0xFFFFB020) : AppColors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          WorkoutTimer.format(_elapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: muscle.isEmpty ? 'Мышцы' : muscle,
              child: const Icon(Icons.accessibility_new_rounded, color: Colors.white, size: 56),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _busy ? null : _complete,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: const BorderSide(color: AppColors.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(111)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Закончить',
                    style: TextStyle(color: AppColors.accent, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyExercise() {
    final clients = _clients;
    final selected = clients.where((c) => int.tryParse('${c['id']}') == _selectedClientId).firstOrNull;
    final name = selected == null ? '' : _clientLabel(selected);
    final forWhom = clients.length > 1 && name.isNotEmpty ? ' для $name' : '';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _innerBg, borderRadius: BorderRadius.circular(24)),
      child: Text(
        'Добавьте первое упражнение$forWhom, чтобы начать записывать подходы',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.fitGrey, fontSize: 15),
      ),
    );
  }

  Widget _buildExerciseCard(Map<String, dynamic> ex, List<Map<String, dynamic>> previous) {
    final sets = _setsOf(ex);
    final done = (ex['status']?.toString() ?? '') == 'done';
    String? prevDate;
    if (previous.isNotEmpty) {
      final raw = previous.first['finished_at']?.toString();
      final dt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
      if (dt != null) {
        prevDate = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _innerBg, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _exerciseName(ex),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              if (done)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle, color: AppColors.accent, size: 20),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Убрать упражнение',
                onPressed: _busy ? null : _deleteActiveExercise,
                icon: const Icon(Icons.delete_outline, color: AppColors.fitGrey, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Подходы:', style: TextStyle(color: AppColors.fitGrey, fontSize: 16)),
          if (sets.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _SetHeader(),
            const SizedBox(height: 8),
            for (var i = 0; i < sets.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SetRow(
                  index: int.tryParse('${sets[i]['set_index']}') ?? i + 1,
                  weight: num.tryParse('${sets[i]['weight_kg']}') ?? 0,
                  reps: int.tryParse('${sets[i]['reps']}') ?? 0,
                  offline: sets[i]['_local'] == true,
                  onWeight: (v) => _editSet(sets[i], weight: v),
                  onReps: (v) => _editSet(sets[i], reps: v),
                  onDelete: _busy ? null : () => _deleteSet(sets[i]),
                ),
              ),
          ],
          const SizedBox(height: 8),
          _LiveButton.filled(title: '+ Добавить подход', loading: _busy, onPressed: _busy ? null : _addSet),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: _chipBg),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Прошлая тренировка',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              if (prevDate != null) Text(prevDate, style: const TextStyle(color: AppColors.fitGrey, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          if (previous.isEmpty)
            const Text('Нет предыдущих результатов', style: TextStyle(color: AppColors.fitGrey, fontSize: 14))
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final w = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < previous.length; i++)
                      SizedBox(
                        width: w,
                        child: _PreviousChip(
                          index: int.tryParse('${previous[i]['set_index']}') ?? i + 1,
                          weight: _fmtKg(previous[i]['weight_kg']),
                          reps: previous[i]['reps']?.toString() ?? '—',
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: _chipBg),
          const SizedBox(height: 16),
          _LiveButton.filled(
            title: done ? 'Упражнение завершено' : 'Завершить упражнение',
            color: done ? const Color(0xFF1F3A24) : _danger,
            foreground: done ? AppColors.accent : Colors.white,
            onPressed: _busy || done ? null : _completeExercise,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOtherExercises() {
    final list = _exercises;
    if (list.length < 2) return const [SizedBox(height: 0)];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('Упражнения тренировки', style: TextStyle(color: AppColors.fitGrey, fontSize: 14)),
      ),
      for (var i = 0; i < list.length; i++)
        if (i != _activeExerciseIndex.clamp(0, list.length - 1))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: _innerBg,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  setState(() => _activeExerciseIndex = i);
                  await _loadPreviousForActive();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      FitExerciseThumb(url: list[i]['photo_url']?.toString(), size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _exerciseName(list[i]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${_setsOf(list[i]).length} подх.',
                        style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        (list[i]['status']?.toString() ?? '') == 'done' ? Icons.check_circle : Icons.chevron_right,
                        color: (list[i]['status']?.toString() ?? '') == 'done' ? AppColors.accent : AppColors.fitGrey,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      const SizedBox(height: 8),
    ];
  }
}

class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({
    required this.name,
    required this.surname,
    required this.label,
    required this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String surname;
  final String label;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = '${name.isNotEmpty ? name[0] : ''}${surname.isNotEmpty ? surname[0] : ''}'.toUpperCase();
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, maxWidth: 72),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.accent : Colors.transparent, width: 2),
              ),
              child: ClipOval(
                child: avatarUrl == null
                    ? ColoredBox(
                        color: const Color(0xFF3A3A3A),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      )
                    : Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: const Color(0xFF3A3A3A),
                          child: Center(
                            child: Text(initials, style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected ? Colors.white : AppColors.fitGrey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onMinus, required this.onPlus});

  static const height = 36.0;

  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: const Color(0xFF323232), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _StepIcon(icon: Icons.remove, onTap: onMinus, size: height),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          _StepIcon(icon: Icons.add, onTap: onPlus, size: height),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.onTap, required this.size});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

/// Column titles aligned with [_SetRow].
class _SetHeader extends StatelessWidget {
  const _SetHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.fitGrey, fontSize: 14);
    return const Row(
      children: [
        SizedBox(width: 28),
        Expanded(flex: 6, child: Text('Вес', style: style)),
        SizedBox(width: 8),
        Expanded(flex: 5, child: Text('Повторы', style: style)),
        SizedBox(width: 32),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.weight,
    required this.reps,
    required this.offline,
    required this.onWeight,
    required this.onReps,
    required this.onDelete,
  });

  final int index;
  final num weight;
  final int reps;
  final bool offline;
  final ValueChanged<num> onWeight;
  final ValueChanged<int> onReps;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final kg = weight % 1 == 0 ? weight.toInt().toString() : weight.toStringAsFixed(1);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$index',
            style: TextStyle(
              color: offline ? AppColors.fitGrey : AppColors.accent,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: _Stepper(
            value: '$kg кг',
            onMinus: () => onWeight((weight - 2.5).clamp(0, 500)),
            onPlus: () => onWeight((weight + 2.5).clamp(0, 500)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: _Stepper(
            value: '$reps',
            onMinus: () => onReps((reps - 1).clamp(0, 100)),
            onPlus: () => onReps((reps + 1).clamp(0, 100)),
          ),
        ),
        SizedBox(
          width: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Удалить подход',
            onPressed: onDelete,
            icon: const Icon(Icons.close, color: AppColors.fitGrey, size: 18),
          ),
        ),
      ],
    );
  }
}

class _PreviousChip extends StatelessWidget {
  const _PreviousChip({required this.index, required this.weight, required this.reps});

  final int index;
  final String weight;
  final String reps;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFF323232), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text('Подход $index:', style: const TextStyle(color: AppColors.fitGrey, fontSize: 14)),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                children: [
                  Text('$weight кг', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.close, color: AppColors.fitGrey, size: 16),
                  ),
                  Text(reps, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveButton extends StatelessWidget {
  const _LiveButton.filled({
    required this.title,
    required this.onPressed,
    this.loading = false,
    this.color = AppColors.accent,
    this.foreground = Colors.black,
  }) : outlined = false;

  const _LiveButton.outlined({required this.title, required this.onPressed})
    : outlined = true,
      loading = false,
      color = AppColors.accent,
      foreground = AppColors.accent;

  final String title;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const text = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    final child = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: foreground))
        : Text(title);
    if (outlined) {
      return SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: onPressed == null ? AppColors.fitBorder : color),
            shape: shape,
            textStyle: text,
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          disabledBackgroundColor: color.withValues(alpha: 0.5),
          disabledForegroundColor: foreground.withValues(alpha: 0.8),
          shape: shape,
          textStyle: text,
        ),
        child: child,
      ),
    );
  }
}
