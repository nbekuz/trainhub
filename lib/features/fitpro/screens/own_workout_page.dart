import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/screens/trainer/create_program_page.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/routes/route_names.dart';

/// Client «Своя тренировка»: active sessions + own complexes + FAB create.
class OwnWorkoutPage extends StatefulWidget {
  const OwnWorkoutPage({super.key});

  @override
  State<OwnWorkoutPage> createState() => _OwnWorkoutPageState();
}

class _OwnWorkoutPageState extends State<OwnWorkoutPage> {
  List<Map<String, dynamic>> _active = const [];
  List<Map<String, dynamic>> _mine = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await WorkoutOfflineQueue.I.flush();
      final localActive = await WorkoutOfflineQueue.I.activeSessionId();

      List<Map<String, dynamic>> sessions = const [];
      try {
        sessions = await FitApi.clientSessions(force: true, sort: 'newest');
      } catch (_) {}

      final active = <Map<String, dynamic>>[
        for (final s in sessions)
          if (s['status']?.toString() == 'in_progress') s,
      ];

      if (active.isEmpty && localActive != null && localActive > 0) {
        final snap = await WorkoutOfflineQueue.I.sessionSnapshot(localActive);
        if (snap != null) {
          active.add({
            ...snap,
            'id': localActive,
            'status': 'in_progress',
            '_local': true,
          });
        } else {
          active.add({'id': localActive, 'status': 'in_progress', 'kinds': const ['solo']});
        }
      } else if (active.isNotEmpty) {
        final id = int.tryParse('${active.first['id']}') ?? 0;
        if (id > 0) await WorkoutOfflineQueue.I.setActiveSessionId(id);
      }

      List<Map<String, dynamic>> mine = const [];
      try {
        mine = await FitApi.myOwnPrograms(force: true);
      } catch (_) {
        // Fallback for older backends without /me/programs.
        try {
          mine = await FitApi.programs(source: 'user_copy', force: true);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _active = active;
        _mine = mine;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(e));
    }
  }

  Future<void> _openSession(int id) async {
    if (id <= 0) return;
    await WorkoutOfflineQueue.I.setActiveSessionId(id);
    if (!mounted) return;
    await context.push(RouteNames.liveSession, extra: id);
    if (mounted) _load();
  }

  Future<void> _createNew() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreateProgramPage(asOwnWorkout: true),
      ),
    );
    if (mounted) _load();
    if (ok == true && mounted) Toast.success('Тренировка сохранена');
  }

  Future<void> _editMine(Map<String, dynamic> program) async {
    final id = int.tryParse('${program['id']}') ?? 0;
    if (id <= 0) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateProgramPage(programId: id, asOwnWorkout: true),
      ),
    );
    if (mounted) _load();
  }

  String _sessionTitle(Map<String, dynamic> s) {
    final kinds = FitLabels.kinds(s['kinds'] ?? s['kind']);
    if (kinds.isNotEmpty && kinds != 'Тренировка') return kinds;
    final source = s['source']?.toString() ?? '';
    return switch (source) {
      'program' || 'catalog' || 'trainer' => 'Тренировка по программе',
      'user_copy' || 'solo' => 'Своя тренировка',
      _ => 'Тренировка в процессе',
    };
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Column(
            children: [
              const HubBackTitle(title: 'Своя тренировка'),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : RefreshIndicator(
                        color: AppColors.accent,
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(bottom: 88 + bottomPad),
                          children: [
                            if (_active.isNotEmpty) ...[
                              const Text(
                                'Сейчас идёт',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'В том числе начатые из готовых программ',
                                style: TextStyle(color: AppColors.fitGrey, fontSize: 12),
                              ),
                              const SizedBox(height: 10),
                              for (final s in _active) ...[
                                _ActiveSessionCard(
                                  title: _sessionTitle(s),
                                  subtitle: DateHelper.formatRuAny(
                                    s['started_at'] ?? s['created_at'],
                                    withTime: true,
                                  ),
                                  local: s['_local'] == true,
                                  onContinue: () {
                                    final id = int.tryParse('${s['id']}') ?? 0;
                                    _openSession(id);
                                  },
                                ),
                                const SizedBox(height: 10),
                              ],
                              const SizedBox(height: 12),
                            ],
                            const Text(
                              'Мои комплексы',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (_mine.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 28),
                                child: Text(
                                  'Пока нет своих комплексов — нажмите + внизу',
                                  style: TextStyle(color: AppColors.fitGrey),
                                ),
                              )
                            else
                              for (final p in _mine)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _OwnProgramCard(
                                    item: p,
                                    onTap: () => _editMine(p),
                                  ),
                                ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            right: 4,
            bottom: 12 + bottomPad,
            child: FloatingActionButton(
              onPressed: _createNew,
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              elevation: 2,
              child: const Icon(Icons.add, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnProgramCard extends StatelessWidget {
  const _OwnProgramCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  String _equipmentSubtitle(List<String> codes) {
    final lower = codes.map((e) => e.toLowerCase()).toList();
    if (lower.any((e) => e.contains('gym') || e.contains('machine') || e.contains('зал'))) {
      return '(С тренажёрами)';
    }
    if (lower.any((e) => e.contains('dumbbell') || e.contains('гантел'))) return '(С гантелями)';
    if (lower.any((e) => e.contains('body') || e.contains('нет') || e.contains('none'))) {
      return '(Без оборудования)';
    }
    return codes.isEmpty ? '' : '(С оборудованием)';
  }

  int _routinesCount() {
    final weeks = item['weeks'];
    if (weeks is List && weeks.isNotEmpty) {
      var n = 0;
      for (final w in weeks.whereType<Map>()) {
        final days = w['days'];
        if (days is List) n += days.length;
      }
      if (n > 0) return n;
    }
    final days = item['days'];
    if (days is List && days.isNotEmpty) return days.length;
    return int.tryParse('${item['workouts_per_week']}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final name = item['title']?.toString().trim();
    final title = (name == null || name.isEmpty) ? 'Тренировка' : name;
    final equipmentList = item['equipment'];
    final equipmentCodes = equipmentList is List
        ? equipmentList.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final subtitle = _equipmentSubtitle(equipmentCodes);
    final cover = FitMedia.url(item['cover_url']?.toString());
    final routines = _routinesCount();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF323232), width: 1.1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: const TextStyle(color: Color(0xFF979797), fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF292929),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF323232)),
                ),
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 99,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null && cover.isNotEmpty)
                          Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0xFF292929),
                              child: Center(
                                child: Icon(Icons.fitness_center_rounded, color: Color(0xFF555555), size: 36),
                              ),
                            ),
                          )
                        else
                          const ColoredBox(
                            color: Color(0xFF292929),
                            child: Center(
                              child: Icon(Icons.fitness_center_rounded, color: Color(0xFF555555), size: 36),
                            ),
                          ),
                        if (routines > 0)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF323232),
                                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                              ),
                              child: Text(
                                '$routines routines',
                                style: const TextStyle(color: Color(0xFF979797), fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({
    required this.title,
    required this.subtitle,
    required this.onContinue,
    this.local = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onContinue;
  final bool local;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onContinue,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1F3A24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.accent),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill, color: AppColors.accent, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (subtitle.isNotEmpty && subtitle != '—') 'Начато: $subtitle',
                      if (local) 'офлайн',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Text('Продолжить', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
