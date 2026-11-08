import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/shell/fit_shell.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/features/fitpro/workout_timer.dart';
import 'package:trainhub/routes/route_names.dart';
import 'package:trainhub/services/navigation/navigation_service.dart';

/// Global floating mini-card for an in-progress workout.
///
/// Lives above pushed routes (program detail, etc.), not only inside [FitShell].
class ActiveWorkoutOverlay extends StatefulWidget {
  const ActiveWorkoutOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ActiveWorkoutOverlay> createState() => _ActiveWorkoutOverlayState();
}

class _ActiveWorkoutOverlayState extends State<ActiveWorkoutOverlay> {
  Timer? _tick;
  Duration _elapsed = Duration.zero;
  String _title = 'Тренировка';
  bool _paused = false;
  Map<String, dynamic>? _snap;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    WorkoutOfflineQueue.I.activeSession.addListener(_onActiveChanged);
    WorkoutOfflineQueue.I.suppressMiniCard.addListener(_onActiveChanged);
    WorkoutOfflineQueue.I.activeMetaEpoch.addListener(_onActiveChanged);
    _bootstrapActive();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _updateElapsed());
  }

  @override
  void dispose() {
    _tick?.cancel();
    WorkoutOfflineQueue.I.activeSession.removeListener(_onActiveChanged);
    WorkoutOfflineQueue.I.suppressMiniCard.removeListener(_onActiveChanged);
    WorkoutOfflineQueue.I.activeMetaEpoch.removeListener(_onActiveChanged);
    super.dispose();
  }

  Future<void> _bootstrapActive() async {
    await WorkoutOfflineQueue.I.restoreActiveSession();
    await _refreshActiveMeta();
    try {
      final active = await FitApi.activeSession();
      if (active != null) {
        final id = int.tryParse('${active['id']}') ?? 0;
        if (id > 0) {
          await WorkoutOfflineQueue.I.setActiveSessionId(id);
          await WorkoutOfflineQueue.I.saveSessionSnapshot(id, active);
        }
      } else {
        final local = await WorkoutOfflineQueue.I.activeSessionId();
        if (local != null) {
          await WorkoutOfflineQueue.I.clearSessionSnapshot(local);
        }
      }
    } catch (_) {}
    await _refreshActiveMeta();
  }

  void _onActiveChanged() {
    _refreshActiveMeta();
  }

  Future<void> _refreshActiveMeta() async {
    final id = WorkoutOfflineQueue.I.activeSession.value;
    if (id == null) {
      if (!mounted) return;
      setState(() {
        _snap = null;
        _elapsed = Duration.zero;
        _title = 'Тренировка';
        _paused = false;
      });
      return;
    }
    final snap = await WorkoutOfflineQueue.I.sessionSnapshot(id);
    final anchored = snap == null ? null : WorkoutTimer.withStartAnchor(snap);
    if (anchored != null && snap != null) {
      final hadMs = snap['started_at_ms'];
      final hadIso = snap['started_at'];
      if (hadMs == null || hadIso == null) {
        await WorkoutOfflineQueue.I.saveSessionSnapshot(id, anchored);
      }
    }
    String title = 'Тренировка';
    final kinds = anchored?['kinds'];
    if (kinds is List && kinds.isNotEmpty) {
      title = kinds.first.toString();
    }
    final dayTitle = anchored?['program_day_title'] ?? anchored?['day_title'] ?? anchored?['title'];
    if (dayTitle != null && dayTitle.toString().trim().isNotEmpty) {
      title = dayTitle.toString().trim();
    }
    if (!mounted) return;
    setState(() {
      _snap = anchored;
      _title = title.isEmpty ? 'Тренировка' : title;
      _paused = WorkoutTimer.isPaused(anchored);
      _elapsed = WorkoutTimer.elapsed(anchored);
    });
  }

  void _updateElapsed() {
    if (_snap == null) return;
    if (_paused) return;
    final next = WorkoutTimer.elapsed(_snap);
    if (next.inSeconds == _elapsed.inSeconds) return;
    if (mounted) setState(() => _elapsed = next);
  }

  void _openActive() {
    final id = WorkoutOfflineQueue.I.activeSession.value;
    if (id == null || id <= 0) return;
    if (WorkoutOfflineQueue.I.suppressMiniCard.value) return;
    getIt<NavigationService>().push(RouteNames.liveSession, extra: id);
  }

  Future<void> _togglePause() async {
    final id = WorkoutOfflineQueue.I.activeSession.value;
    if (id == null || id <= 0 || _toggling) return;
    setState(() => _toggling = true);
    try {
      if (_paused) {
        final local = await WorkoutOfflineQueue.I.resumeActiveLocally(id);
        try {
          final remote = await FitApi.resumeSession(id);
          await WorkoutOfflineQueue.I.saveSessionSnapshot(id, {...local, ...remote});
        } catch (_) {
          await WorkoutOfflineQueue.I.enqueue({'type': 'resume', 'session_id': id});
        }
      } else {
        final local = await WorkoutOfflineQueue.I.pauseActiveLocally(id);
        try {
          final remote = await FitApi.pauseSession(id);
          await WorkoutOfflineQueue.I.saveSessionSnapshot(id, {...local, ...remote});
        } catch (_) {
          await WorkoutOfflineQueue.I.enqueue({'type': 'pause', 'session_id': id});
        }
      }
      await _refreshActiveMeta();
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = WorkoutOfflineQueue.I.activeSession.value;
    final suppressed = WorkoutOfflineQueue.I.suppressMiniCard.value;
    final showMini = activeId != null && activeId > 0 && !suppressed;
    final bottomPad = FitShell.bottomGap(context) + FitShell.barHeight + 10;

    return Stack(
      children: [
        widget.child,
        if (showMini)
          Positioned(
            right: 16,
            bottom: bottomPad,
            child: _ActiveWorkoutMiniCard(
              title: _title,
              elapsed: WorkoutTimer.format(_elapsed),
              paused: _paused,
              busy: _toggling,
              onOpen: _openActive,
              onTogglePause: _togglePause,
            ),
          ),
      ],
    );
  }
}

class _ActiveWorkoutMiniCard extends StatelessWidget {
  const _ActiveWorkoutMiniCard({
    required this.title,
    required this.elapsed,
    required this.paused,
    required this.busy,
    required this.onOpen,
    required this.onTogglePause,
  });

  final String title;
  final String elapsed;
  final bool paused;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onTogglePause;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF1F3A24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: paused ? const Color(0xFFFFB020) : AppColors.accent,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: busy ? null : onTogglePause,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(
                  paused ? Icons.play_circle_fill : Icons.pause_circle_filled,
                  color: paused ? const Color(0xFFFFB020) : AppColors.accent,
                  size: 32,
                ),
              ),
              GestureDetector(
                onTap: onOpen,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            elapsed,
                            style: TextStyle(
                              color: paused ? const Color(0xFFFFB020) : AppColors.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (paused) ...[
                            const SizedBox(width: 6),
                            const Text(
                              'пауза',
                              style: TextStyle(
                                color: Color(0xFFFFB020),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
