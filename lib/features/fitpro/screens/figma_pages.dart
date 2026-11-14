import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_cache.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/push.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/screens/client_workouts_tab.dart';
import 'package:trainhub/features/fitpro/screens/measurements_ui.dart';
import 'package:trainhub/features/fitpro/screens/progress_ui.dart';
import 'package:trainhub/features/fitpro/screens/robokassa_pay.dart';
import 'package:trainhub/features/fitpro/widgets/contact_actions.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/features/fitpro/widgets/weight_dynamics_chart.dart';
import 'package:trainhub/routes/route_names.dart';

const _up = Color(0xFF3DDC97);
const _down = Color(0xFFFF5C5C);

class TrainerHomePage extends ConsumerStatefulWidget {
  const TrainerHomePage({super.key});

  @override
  ConsumerState<TrainerHomePage> createState() => _TrainerHomePageState();
}

class _TrainerHomePageState extends ConsumerState<TrainerHomePage> {
  int _clients = 0;
  int _todayDone = 0;
  int _todayPlanned = 0;
  int _monthSessions = 0;
  int _attentionCount = 0;
  int _unread = 0;
  List<FitCalendarEvent> _soon = const [];
  List<FitAttentionItem> _alerts = const [];
  StreamSubscription<String>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _applyDash(FitCache.I.peek<Map<String, dynamic>>('trainer.dashboard'));
    _cacheSub = FitCache.I.updates.listen((key) {
      if (!mounted) return;
      if (key == 'trainer.dashboard') {
        _applyDash(FitCache.I.peek<Map<String, dynamic>>('trainer.dashboard'));
      }
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => PushRegistration.askOnHome());
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  void _applyDash(Map<String, dynamic>? dash) {
    if (dash == null) return;
    setState(() {
      _clients = int.tryParse('${dash['clients_count']}') ?? _clients;
      _todayDone = int.tryParse('${dash['today_done']}') ?? _todayDone;
      _todayPlanned = int.tryParse('${dash['today_planned']}') ?? _todayPlanned;
      _monthSessions = int.tryParse('${dash['month_sessions']}') ?? _monthSessions;
      _attentionCount = int.tryParse('${dash['attention_count']}') ?? _attentionCount;
    });
  }

  Future<void> _load({bool force = false}) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 1));
    try {
      final dash = await FitApi.trainerDashboard(force: force);
      final soon = await FitApi.trainerCalendar(from: from, to: to, force: force);
      final alerts = await FitApi.trainerAttention(force: force);
      final unread = await FitApi.unreadCount();
      if (!mounted) return;
      setState(() {
        _clients = int.tryParse('${dash['clients_count']}') ?? 0;
        _todayDone = int.tryParse('${dash['today_done']}') ?? 0;
        _todayPlanned = int.tryParse('${dash['today_planned']}') ?? 0;
        _monthSessions = int.tryParse('${dash['month_sessions']}') ?? 0;
        _attentionCount = int.tryParse('${dash['attention_count']}') ?? 0;
        _soon = soon.take(3).toList();
        _alerts = alerts.take(3).toList();
        _unread = unread;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(fitSessionProvider).user;
    final name = user == null ? '' : '${user.name} ${user.surname}'.trim();
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onRefresh: () => _load(force: true),
      child: ListView(
        physics: fitAlwaysScroll,
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _UserHeader(name: name.isEmpty ? 'Тренер' : name, id: user?.uuid ?? '', badge: _unread > 0),
          const SizedBox(height: 16),
          Column(
            children: [
              IntrinsicHeight(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _StatCard(
                      asset: 'assets/icons/quick-action/users.svg',
                      title: 'Список клиентов',
                      value: '$_clients',
                      caption: 'Всего клиентов',
                      captionColor: _up,
                      onTap: () => context.push(RouteNames.clients),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      asset: 'assets/icons/quick-action/dumbell.svg',
                      title: 'Тренировок сегодня',
                      value: '$_todayDone из $_todayPlanned',
                      caption: 'План на сегодня',
                      onTap: () => context.push(RouteNames.todayPlan),
                    ),
                  ),
                ],
                ),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _StatCard(
                      asset: 'assets/icons/quick-action/time.svg',
                      title: 'Отчет по тренировкам',
                      value: '$_monthSessions',
                      caption: 'За этот месяц',
                      onTap: () => context.push(RouteNames.report),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      asset: _attentionCount > 0 ? 'assets/icons/quick-action/sad.svg' : 'assets/icons/quick-action/happy.svg',
                      assetWidth: _attentionCount > 0 ? 20 : 24,
                      assetHeight: _attentionCount > 0 ? 20 : 24,
                      tint: _attentionCount > 0 ? null : const Color(0xFF3DDC97),
                      title: 'Требуют внимание',
                      value: '$_attentionCount',
                      caption: 'Проверьте детали',
                      captionColor: _attentionCount > 0 ? _down : _up,
                      onTap: () => context.push(RouteNames.attention),
                    ),
                  ),
                ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          HubSectionTitle(title: 'Ближайшие тренировки', onSeeAll: () => context.push(RouteNames.todayPlan)),
          const SizedBox(height: 10),
          HubCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _soon.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('На сегодня тренировок нет', style: TextStyle(color: AppColors.fitGrey)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _soon.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: Color(0xFF333333)),
                        _SessionRow(
                          name: _soon[i].name,
                          meta: _soon[i].tags.join(', '),
                          place: _soon[i].place,
                          time: _soon[i].time.split(' - ').first,
                          onTap: () => context.push(RouteNames.calendarEventDetail, extra: _soon[i].id),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 22),
          HubSectionTitle(title: 'Требуют внимания', onSeeAll: () => context.push(RouteNames.attention)),
          const SizedBox(height: 10),
          HubCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            border: Border.all(color: const Color(0xFF323232)),
            child: _alerts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Сейчас никто не требует внимания', style: TextStyle(color: AppColors.fitGrey)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _alerts.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: Color(0xFF333333)),
                        _AlertRow(
                          name: _alerts[i].name,
                          days: 'Не был ${_alerts[i].days} дней',
                          hot: _alerts[i].days >= 14,
                          onTap: () => context.push(
                            RouteNames.attentionDetail,
                            extra: AttentionClient(
                              name: _alerts[i].name,
                              days: 'Не был ${_alerts[i].days} дней',
                              count: _alerts[i].days,
                              place: _alerts[i].place,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

}

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.name, required this.id, this.badge = false, this.streak});

  final String name;
  final String id;
  final bool badge;
  final int? streak;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF232323),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF292929)),
          ),
          child: Text(
            letter,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (id.isNotEmpty) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF242424), borderRadius: BorderRadius.circular(111)),
                  child: Text('ID$id', style: const TextStyle(color: Color(0xFF979797), fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        if (streak != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/icons/usefull/fire.svg', width: 24, height: 24),
                const SizedBox(width: 4),
                Text('$streak', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        GestureDetector(
          onTap: () => context.push(RouteNames.notifications),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF292929)),
            ),
            child: SizedBox(
              width: 15,
              height: 17,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SvgPicture.asset('assets/icons/usefull/ring.svg', width: 15, height: 17),
                  if (badge)
                    const Positioned(
                      top: -1,
                      right: -3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
                        child: SizedBox(width: 8, height: 8),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.asset,
    required this.title,
    required this.value,
    required this.caption,
    required this.onTap,
    this.assetWidth = 20,
    this.assetHeight = 20,
    this.tint,
    this.captionColor = AppColors.fitGrey,
  });

  final String asset;
  final double assetWidth;
  final double assetHeight;
  final Color? tint;
  final String title;
  final String value;
  final String caption;
  final Color captionColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: HubCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        border: Border.all(color: const Color(0xFF323232)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFF323232), borderRadius: BorderRadius.circular(14)),
                  child: SvgPicture.asset(
                    asset,
                    width: assetWidth,
                    height: assetHeight,
                    colorFilter: tint == null ? null : ColorFilter.mode(tint!, BlendMode.srcIn),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.north_east, color: Colors.black, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 15 * 1.15 * 2,
              width: double.infinity,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.15, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.05),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: captionColor, fontSize: 13, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.name,
    required this.meta,
    required this.place,
    required this.time,
    required this.onTap,
  });

  final String name;
  final String meta;
  final String place;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            HubAvatar(letter: name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MetaPill(label: meta),
                      _MetaPill(label: place),
                      _MetaPill(
                        label: time,
                        icon: const Icon(Icons.access_time, size: 14, color: AppColors.fitGrey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.icon});

  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 4)],
          Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.name, required this.days, required this.hot, required this.onTap});

  final String name;
  final String days;
  final bool hot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = hot ? const Color(0xFFFD6565) : const Color(0xFFFEB94B);
    final asset = hot ? 'assets/icons/quick-action/sad.svg' : 'assets/icons/quick-action/none-action.svg';
    return ListTile(
      onTap: onTap,
      leading: HubAvatar(letter: name, size: 50),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Row(
        children: [
          SvgPicture.asset(
            asset,
            width: hot ? 20 : 24,
            height: hot ? 20 : 24,
            colorFilter: hot ? null : ColorFilter.mode(color, BlendMode.srcIn),
          ),
          const SizedBox(width: 6),
          Text(days, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white),
    );
  }
}

class ClientDetailPage extends StatefulWidget {
  const ClientDetailPage({super.key, this.linkId, this.name = ''});

  final int? linkId;
  final String name;

  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
  Map<String, dynamic> _card = const {};
  List<WeightPoint> _weights = const [];
  List<Map<String, dynamic>> _sessions = const [];
  Map<String, dynamic> _lastDetail = const {};
  List<Map<String, dynamic>> _measurements = const [];
  Map<String, dynamic> _stats = const {};
  Map<String, dynamic> _home = const {};
  int _tab = 0;
  int _refreshGen = 0;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _assignCourseToClient(BuildContext context, int linkId) async {
    if (linkId == 0) return;
    List<Map<String, dynamic>> programs = [];
    try {
      programs = await FitApi.trainerPrograms();
      if (programs.isEmpty) {
        programs = await FitApi.programs(source: 'trainer');
      }
    } catch (e) {
      if (context.mounted) Toast.error(FitApi.messageOf(e));
      return;
    }
    if (!context.mounted) return;
    if (programs.isEmpty) {
      Toast.info('Сначала создайте курс');
      return;
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Назначить курс', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final p in programs)
            ListTile(
              title: Text(p['title']?.toString() ?? 'Курс', style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                '${p['status'] ?? ''} · ${p['level'] ?? ''}',
                style: const TextStyle(color: AppColors.fitGrey),
              ),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final programId = int.tryParse('${selected['id']}') ?? 0;
    if (programId == 0) return;
    try {
      await FitApi.assignProgram(programId, linkId: linkId);
      if (context.mounted) Toast.success('Курс назначен');
    } catch (e) {
      if (context.mounted) Toast.error(FitApi.messageOf(e));
    }
  }

  static Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load({bool force = false}) async {
    final id = widget.linkId;
    if (id == null || id == 0) return;
    final results = await Future.wait<Object?>([
      _safe(FitApi.clientCard(id)),
      _safe(FitApi.measurementChart('weight_kg', linkId: id, force: force)),
      _safe(FitApi.linkSessions(id)),
      _safe(FitApi.linkMeasurements(id)),
      _safe(FitApi.linkStats(id)),
    ]);
    if (!mounted) return;
    final card = results[0] as Map<String, dynamic>?;
    final chart = results[1] as List<({DateTime at, double value})>?;
    final sessions = results[2] as List<Map<String, dynamic>>?;
    final lastDone = sessions?.firstWhere((s) => s['status'] == 'completed', orElse: () => const {}) ?? const {};
    final lastId = int.tryParse('${lastDone['id']}') ?? 0;
    final detail = lastId > 0 ? await _safe(FitApi.session(lastId)) : null;
    if (!mounted) return;
    setState(() {
      if (card != null) _card = card;
      if (chart != null) {
        _weights = [for (final p in chart) (at: p.at.toLocal(), value: p.value)]..sort((a, b) => a.at.compareTo(b.at));
      }
      if (sessions != null) _sessions = sessions;
      _lastDetail = detail ?? const {};
      _measurements = (results[3] as List<Map<String, dynamic>>?) ?? _measurements;
      _stats = (results[4] as Map<String, dynamic>?) ?? _stats;
      _home = _buildHome(lastDone);
    });
  }

  Future<void> _refresh() async {
    await _load(force: true);
    if (mounted) setState(() => _refreshGen++);
  }

  /// Same shape as `/client/home`, so the client «Обзор» widgets render the trainer view.
  Map<String, dynamic> _buildHome(Map<String, dynamic> lastDone) {
    final current = double.tryParse('${_card['weight_kg']}') ?? (_weights.isEmpty ? null : _weights.last.value);
    final goal = double.tryParse('${_card['target_weight_kg'] ?? _card['weight_goal_kg']}');
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final recent = [
      for (final p in _weights)
        if (!p.at.isBefore(monthAgo)) p,
    ];
    final start = _weights.isEmpty ? null : _weights.first.value;
    double? progress;
    if (current != null && goal != null && start != null && goal != start) {
      progress = ((current - start) / (goal - start) * 100).clamp(0, 100).toDouble();
    }

    Map<String, dynamic>? last;
    if (lastDone.isNotEmpty) {
      final exercises = _lastDetail['exercises'] is List
          ? (_lastDetail['exercises'] as List).whereType<Map>().toList()
          : const <Map>[];
      final top = <Map<String, dynamic>>[];
      for (final ex in exercises) {
        final sets = ex['sets'] is List ? (ex['sets'] as List).whereType<Map>() : const <Map>[];
        num? bestW;
        num? bestR;
        for (final s in sets) {
          final w = num.tryParse('${s['weight_kg']}');
          final r = num.tryParse('${s['reps']}');
          if (w != null && (bestW == null || w > bestW)) bestW = w;
          if (r != null && (bestR == null || r > bestR)) bestR = r;
        }
        if (bestW == null) continue;
        top.add({
          'name': ex['name'] ?? ex['exercise_name'] ?? 'Упражнение',
          'weight_kg': bestW % 1 == 0 ? bestW.toInt() : bestW,
          'reps': bestR,
        });
      }
      top.sort((a, b) => (b['weight_kg'] as num).compareTo(a['weight_kg'] as num));
      last = {
        ...lastDone,
        'exercises_count': exercises.isEmpty ? null : exercises.length,
        'top_sets': top.take(3).toList(),
      };
    }

    return {
      'weight_kg': current,
      'weight_goal_kg': goal,
      'progress_pct': progress,
      'weight_delta_30d': recent.isEmpty ? null : recent.last.value - recent.first.value,
      'weight_chart': [
        for (final p in _weights) {'date': p.at.toIso8601String(), 'weight_kg': p.value},
      ],
      'attendance_30d': _card['attendance_30d'],
      'trainer_notes': _card['notes'],
      'last_session': last,
      'streak': _streak(),
    };
  }

  int _streak() {
    final days = <DateTime>{};
    for (final s in _sessions) {
      if (s['status'] != 'completed') continue;
      final at = DateHelper.parseLocal((s['finished_at'] ?? s['started_at'])?.toString());
      if (at != null) days.add(DateTime(at.year, at.month, at.day));
    }
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if (!days.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  Future<void> _addWeight() async {
    final id = widget.linkId ?? 0;
    if (id == 0) return;
    final ctrl = TextEditingController(text: '${_home['weight_kg'] ?? ''}');
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF323232)),
        ),
        title: const Text(
          'Вес клиента',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(suffixText: 'кг', hintText: '0'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppColors.fitGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.').trim())),
            child: const Text('Сохранить', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value <= 0) return;
    try {
      await FitApi.addLinkMeasurement(id, {'weight_kg': value});
      FitCache.I.invalidate('chart.$id.');
      await _refresh();
      Toast.success('Вес сохранён');
    } catch (e) {
      Toast.error(FitApi.messageOf(e));
    }
  }

  Future<void> _addNote() async {
    final id = widget.linkId ?? 0;
    final text = _noteCtrl.text.trim();
    if (id == 0 || text.isEmpty) return;
    try {
      await FitApi.addLinkNote(id, text);
      _noteCtrl.clear();
      await _load();
    } catch (e) {
      Toast.error(FitApi.messageOf(e));
    }
  }

  Future<void> _deleteNote(int noteId) async {
    final id = widget.linkId ?? 0;
    if (id == 0 || noteId == 0) return;
    try {
      await FitApi.deleteLinkNote(id, noteId);
      await _load();
    } catch (e) {
      Toast.error(FitApi.messageOf(e));
    }
  }

  String _text(Object? value, String fallback) {
    final text = value?.toString() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _fmtDate(Object? raw) => DateHelper.formatRuAny(raw, withTime: false);

  Future<void> _startWorkout() async {
    final userId = int.tryParse('${_card['user_id'] ?? _card['client_id']}') ?? 0;
    try {
      final result = await FitApi.startOrResumeSession(clientIds: userId == 0 ? const [] : [userId]);
      final sessionId = result.sessionId;
      if (!mounted) return;
      if (sessionId > 0) {
        if (result.resumed) Toast.info('Сначала завершите текущую тренировку');
        context.push(RouteNames.liveSession, extra: sessionId);
      } else {
        Toast.success('Тренировка начата');
      }
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _text(_card['first_name'], widget.name);
    final full = '${_card['first_name'] ?? ''} ${_card['last_name'] ?? ''}'.trim();
    final title = full.isEmpty ? name : full;
    final Widget body = switch (_tab) {
      1 => _sessionsTab(),
      2 => _measurementsTab(),
      3 => _progressTab(),
      4 => _notesTab(),
      _ => Column(
        children: [
          _Overview(
            key: ValueKey('cd-ov-$_refreshGen'),
            home: _home,
            linkId: widget.linkId,
            onEditWeight: _addWeight,
            onOpenNotes: () => setState(() => _tab = 4),
          ),
          const SizedBox(height: 16),
          ..._clientInfo(context),
        ],
      ),
    };

    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onRefresh: _refresh,
      child: ListView(
        physics: fitAlwaysScroll,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          SizedBox(
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SvgPicture.asset('assets/icons/trainer/arrow-left.svg', width: 24, height: 24),
                      ),
                    ),
                  ),
                ),
                const Text(
                  'Тренировка',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _UserHeader(
            name: title.isEmpty ? 'Клиент' : title,
            id: _text(_card['public_id'], ''),
            streak: _home['streak'] as int? ?? 0,
          ),
          const SizedBox(height: 24),
          _ProfileTabs(selected: _tab, onSelect: (i) => setState(() => _tab = i)),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  List<Widget> _clientInfo(BuildContext context) {
    final last = _card['last_measurement'] is Map
        ? Map<String, dynamic>.from(_card['last_measurement'] as Map)
        : const <String, dynamic>{};
    final phone = _text(_card['phone'], '');
    final whatsapp = _text(_card['whatsapp'], '');
    final telegram = _text(_card['telegram'], '');
    final weightNow = _text(last['weight_kg'] ?? _card['weight_kg'], '—');
    final weightGoal = _text(_card['target_weight_kg'] ?? _card['weight_goal_kg'], '—');
    final subEnd = _card['subscription_ends_at'];
    final contraindications = _card['contraindications'] is List
        ? (_card['contraindications'] as List).whereType<Map>().toList()
        : const <Map>[];
    final goals = _card['goals'] is List ? (_card['goals'] as List).map((e) => e.toString()).toList() : const <String>[];

    return [
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: _startWorkout,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.black,
            shape: const StadiumBorder(),
          ),
          child: const Text('Начать тренировку', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 12),
      HubCard(
        child: Column(
          children: [
            _InfoLine(icon: Icons.calendar_today_outlined, label: 'Дата начала', value: _fmtDate(_card['created_at'])),
            _InfoLine(
              icon: Icons.credit_card_outlined,
              label: 'Абонемент до',
              value: subEnd == null ? '—' : _fmtDate(subEnd),
            ),
            _InfoLine(
              icon: Icons.monitor_weight_outlined,
              label: 'Вес (тек / цел)',
              value: '$weightNow кг / $weightGoal кг',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      HubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Связаться',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ContactActionsRow(phone: phone, whatsapp: whatsapp, telegram: telegram),
          ],
        ),
      ),
      const SizedBox(height: 12),
      HubCard(
        child: HubMenuTile(
          icon: Icons.fitness_center_outlined,
          label: 'Назначить курс',
          onTap: () => _assignCourseToClient(context, widget.linkId ?? 0),
        ),
      ),
      if (goals.isNotEmpty) ...[
        const SizedBox(height: 12),
        HubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Цели',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in goals)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF323232)),
                      ),
                      child: Text(g, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (contraindications.isNotEmpty) ...[
        const SizedBox(height: 12),
        HubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Противопоказания',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final c in contraindications)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${c['text'] ?? ''}', style: const TextStyle(color: AppColors.fitGrey)),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _emptyCard(String text) => HubCard(
    child: Text(text, style: const TextStyle(color: AppColors.fitGrey, fontSize: 14)),
  );

  Widget _sessionsTab() {
    if (_sessions.isEmpty) return _emptyCard('Тренировок пока нет');
    return Column(
      children: [
        for (final s in _sessions) ...[
          GestureDetector(
            onTap: () {
              final id = int.tryParse('${s['id']}') ?? 0;
              final clientId = int.tryParse('${_card['user_id'] ?? _card['client_id']}');
              if (id > 0) context.push(RouteNames.sessionDetail, extra: (id: id, clientId: clientId));
            },
            child: HubCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          FitLabels.kinds(s['kinds']),
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DateHelper.formatRuAny(s['finished_at'] ?? s['started_at'])} · '
                          '${formatWorkoutDuration(int.tryParse('${s['duration_sec']}'))}',
                          style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    FitLabels.sessionStatus(s['status']?.toString()),
                    style: TextStyle(
                      color: s['status'] == 'completed' ? AppColors.accent : AppColors.fitGrey,
                      fontSize: 13,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.fitGrey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _measurementsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _addWeight,
          icon: const Icon(Icons.add, color: AppColors.accent),
          label: const Text('Добавить вес', style: TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: Color(0xFF323232)),
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_measurements.isEmpty) _emptyCard('Замеров пока нет'),
        for (final m in _measurements) ...[
          HubCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateHelper.formatRuAny(m['recorded_at'], withTime: false),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in measurementFields)
                      if (num.tryParse('${m[f.key]}') case final v?)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1C),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF323232)),
                          ),
                          child: Text(
                            '${f.label}: ${v % 1 == 0 ? v.toInt() : v} ${f.unit}',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _progressTab() {
    final strength = _stats['strength_progress'] is List
        ? (_stats['strength_progress'] as List).whereType<Map>().toList()
        : const <Map>[];
    final minutes = ((int.tryParse('${_stats['duration_sec_total']}') ?? 0) / 60).round();
    return Column(
      children: [
        OverviewWeightDynamics(key: ValueKey('cd-pr-$_refreshGen'), home: _home, linkId: widget.linkId),
        const SizedBox(height: 16),
        HubCard(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              _MiniStat(label: 'Тренировок', value: '${_stats['sessions_completed'] ?? '—'}'),
              _MiniStat(label: 'Минут', value: '$minutes'),
              _MiniStat(label: 'Ккал', value: '${_stats['calories_total'] ?? '—'}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        HubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Силовые показатели',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (strength.isEmpty)
                const Text('Нет данных', style: TextStyle(color: AppColors.fitGrey))
              else
                for (final item in strength)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['name']?.toString() ?? 'Упражнение',
                            style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                          ),
                        ),
                        Text(
                          '${item['last_weight_kg'] ?? '—'} кг × ${item['last_reps'] ?? '—'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        if (item['best_weight_kg'] != null)
                          Text(
                            '  · макс ${item['best_weight_kg']} кг',
                            style: const TextStyle(color: AppColors.accent, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _notesTab() {
    final notes = _card['notes'] is List ? (_card['notes'] as List).whereType<Map>().toList() : const <Map>[];
    return Column(
      children: [
        HubCard(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Новая заметка',
                    hintStyle: TextStyle(color: AppColors.fitGrey),
                    border: InputBorder.none,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _addNote,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.black, size: 22),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty) _emptyCard('Заметок пока нет'),
        for (final n in notes) ...[
          HubCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n['text']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateHelper.formatRuAny(n['created_at']),
                        style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _deleteNote(int.tryParse('${n['id']}') ?? 0),
                  icon: const Icon(Icons.delete_outline, color: AppColors.fitGrey, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ChipStat extends StatelessWidget {
  const _ChipStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

enum _DayMark { present, missed, rest, upcoming }

DateTime? _parseAttendanceDay(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

Map<DateTime, String> _attendanceMarks(Object? raw) {
  if (raw is! List) return const {};
  const rank = {
    'completed': 4,
    'present': 4,
    'attended': 4,
    'rest': 3,
    'missed': 2,
    'no_show': 2,
    'skipped': 2,
    'absent': 2,
    'cancelled': 2,
    'scheduled': 1,
    'in_progress': 1,
  };
  final marks = <DateTime, String>{};
  for (final item in raw.whereType<Map>()) {
    final date = _parseAttendanceDay(item['date']?.toString());
    if (date == null) continue;
    final status = item['status']?.toString() ?? '';
    final prev = marks[date];
    if (prev == null || (rank[status] ?? 0) >= (rank[prev] ?? 0)) {
      marks[date] = status;
    }
  }
  return marks;
}

const _monthGenitive = <String>[
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];

class _Attendance extends StatelessWidget {
  const _Attendance({this.marks = const {}});

  final Map<DateTime, String> marks;

  _DayMark _mark(DateTime day) {
    final today = DateTime.now();
    final date = DateTime(day.year, day.month, day.day);
    final now = DateTime(today.year, today.month, today.day);
    if (date.isAfter(now)) return _DayMark.upcoming;
    final status = marks[date];
    return switch (status) {
      'completed' || 'present' || 'attended' => _DayMark.present,
      'rest' => _DayMark.rest,
      'missed' || 'no_show' || 'skipped' || 'absent' || 'cancelled' => _DayMark.missed,
      _ => _DayMark.upcoming,
    };
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leading = month.weekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'Посещаемость за ${_monthGenitive[now.month - 1]}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final label in labels)
                    Expanded(
                      child: Center(
                        child: Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (var row = 0; row < rows; row++) ...[
                if (row > 0) const SizedBox(height: 6),
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: Center(
                          child: Builder(
                            builder: (_) {
                              final index = row * 7 + col;
                              final dayNum = index - leading + 1;
                              if (dayNum < 1 || dayNum > daysInMonth) {
                                return const SizedBox(width: 28, height: 28);
                              }
                              final date = DateTime(now.year, now.month, dayNum);
                              return _MonthDayCell(
                                mark: _mark(date),
                                isToday: date == today,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFF2C2C2C)),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _LegendMark(color: Color(0xFFC7F137), label: 'Был'),
                    _LegendMark(color: Color(0xFFFF6B6B), label: 'Пропуск'),
                    _LegendMark(color: Color(0xFFFFB020), label: 'Отдых'),
                    _LegendMark(color: Color(0xFF2A2A2A), label: 'Еще не наступил'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({required this.mark, required this.isToday});

  final _DayMark mark;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final fill = switch (mark) {
      _DayMark.present => const Color(0xFFC7F137),
      _DayMark.missed => const Color(0xFFFF6B6B),
      _DayMark.rest => const Color(0xFFFFB020),
      _DayMark.upcoming => const Color(0xFF2A2A2A),
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: const Color(0xFFC7F137), width: 1.5) : null,
      ),
      child: switch (mark) {
        _DayMark.present => const Icon(Icons.check, size: 16, color: Colors.black),
        _DayMark.missed => const Icon(Icons.close, size: 16, color: Colors.black),
        _DayMark.rest => const Icon(Icons.hotel, size: 14, color: Colors.black),
        _DayMark.upcoming => null,
      },
    );
  }
}

class _LegendMark extends StatelessWidget {
  const _LegendMark({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 13)),
      ],
    );
  }
}

class AttentionClient {
  const AttentionClient({
    required this.name,
    required this.days,
    required this.count,
    required this.place,
    this.linkId = 0,
    this.phone = '',
    this.whatsapp = '',
    this.telegram = '',
    this.weightKg,
    this.targetWeightKg,
    this.clientSince,
    this.subscriptionEndsAt,
  });

  final String name;
  final String days;
  final int count;
  final String place;
  final int linkId;
  final String phone;
  final String whatsapp;
  final String telegram;
  final String? weightKg;
  final String? targetWeightKg;
  final String? clientSince;
  final String? subscriptionEndsAt;

  bool get hot => count >= 14;
}

class AttentionPage extends StatefulWidget {
  const AttentionPage({super.key});

  @override
  State<AttentionPage> createState() => _AttentionPageState();
}

class _AttentionPageState extends State<AttentionPage> {
  String _query = '';
  String _filter = 'Все';
  String _sort = 'Сначала давно';
  List<AttentionClient> _people = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FitApi.trainerAttention();
      if (!mounted) return;
      setState(() {
        _people = items
            .map(
              (item) => AttentionClient(
                name: item.name,
                days: 'Не был ${item.days} дней',
                count: item.days,
                place: item.place,
                linkId: item.linkId,
                phone: item.phone,
                whatsapp: item.whatsapp,
                telegram: item.telegram,
                weightKg: item.weightKg,
                targetWeightKg: item.targetWeightKg,
                clientSince: item.clientSince,
                subscriptionEndsAt: item.subscriptionEndsAt,
              ),
            )
            .toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final people = _people.where((person) {
      final matchesQuery = person.name.toLowerCase().contains(_query.toLowerCase());
      final matchesFilter = switch (_filter) {
        '14 дней' => person.hot,
        'До 7 дней' => !person.hot,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList()
      ..sort((a, b) {
        return switch (_sort) {
          'Сначала недавно' => a.count.compareTo(b.count),
          'По имени' => a.name.compareTo(b.name),
          _ => b.count.compareTo(a.count),
        };
      });
    return FitScaffold(
      child: Column(
        children: [
          const HubBackTitle(title: 'Требуют внимание'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Поиск по имени или телефо...',
                      hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey, size: 20),
                      filled: true,
                      fillColor: AppColors.fitCard,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SquareButton(
                  onTap: () async {
                    final value = await _pickSheet(context, 'Фильтр', const ['Все', '14 дней', 'До 7 дней'], _filter);
                    if (value != null) setState(() => _filter = value);
                  },
                  child: const Icon(Icons.tune, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                _SquareButton(
                  onTap: () async {
                    final value = await _pickSheet(context, 'Сортировка', const ['Сначала давно', 'Сначала недавно', 'По имени'], _sort);
                    if (value != null) setState(() => _sort = value);
                  },
                  child: SvgPicture.asset('assets/icons/usefull/sort.svg', width: 20, height: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final person = people[index];
                return _AttentionCard(
                  person: person,
                  onTap: () => context.push(RouteNames.attentionDetail, extra: person),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AttentionDetailPage extends StatelessWidget {
  const AttentionDetailPage({super.key, required this.client});

  final AttentionClient client;

  String _fmt(String? raw) => DateHelper.formatRuAny(raw, withTime: false);

  @override
  Widget build(BuildContext context) {
    final color = client.hot ? const Color(0xFFFD6565) : const Color(0xFFFEB94B);
    final weight = '${client.weightKg ?? '—'} кг / ${client.targetWeightKg ?? '—'} кг';
    return FitScaffold(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const HubBackTitle(title: 'Требуют внимание'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF232323),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF323232)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ClientPhoto(size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(client.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            _AbsenceLine(hot: client.hot, days: client.days, color: color),
                          ],
                        ),
                      ),
                      _PlaceChip(label: client.place),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('Информация о клиенте', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _InfoLine(icon: Icons.calendar_today_outlined, label: 'Дата начала', value: _fmt(client.clientSince)),
                  _InfoLine(icon: Icons.credit_card_outlined, label: 'Абонемент до', value: _fmt(client.subscriptionEndsAt)),
                  _InfoLine(icon: Icons.inventory_2_outlined, label: 'Вес (тек / цел)', value: weight),
                  const SizedBox(height: 12),
                  const Text('Связаться', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ContactActionsRow(
                    phone: client.phone,
                    whatsapp: client.whatsapp,
                    telegram: client.telegram,
                  ),
                  if (client.linkId > 0) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push(RouteNames.clientDetail, extra: client.linkId),
                        child: const Text('Карточка клиента', style: TextStyle(color: AppColors.accent)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.person, required this.onTap});

  final AttentionClient person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = person.hot ? const Color(0xFFFD6565) : const Color(0xFFFEB94B);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF323232)),
        ),
        child: Row(
          children: [
            const _ClientPhoto(size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  _AbsenceLine(hot: person.hot, days: person.days, color: color),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _AbsenceLine extends StatelessWidget {
  const _AbsenceLine({required this.hot, required this.days, required this.color});

  final bool hot;
  final String days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(
          hot ? 'assets/icons/quick-action/sad.svg' : 'assets/icons/quick-action/none-action.svg',
          width: hot ? 20 : 24,
          height: hot ? 20 : 24,
          colorFilter: hot ? null : ColorFilter.mode(color, BlendMode.srcIn),
        ),
        const SizedBox(width: 6),
        Text(days, style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }
}

class _ClientPhoto extends StatelessWidget {
  const _ClientPhoto({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset('assets/images/client1.png', width: size, height: size, fit: BoxFit.cover),
    );
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/icons/usefull/zal.svg', width: 20, height: 20),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.label, required this.asset, required this.size});

  final String label;
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A4A4A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(asset, width: size, height: size, colorFilter: const ColorFilter.mode(Color(0xFF979797), BlendMode.srcIn)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 14)),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF979797), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 14))),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: child,
      ),
    );
  }
}

Future<String?> _pickSheet(BuildContext context, String title, List<String> options, String selected) {
  return showModalBottomSheet<String>(
    context: context,
    barrierColor: const Color(0x80232323),
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final option in options)
                InkWell(
                  onTap: () => Navigator.pop(context, option),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: TextStyle(color: option == selected ? Colors.white : const Color(0xFFE6E6E6), fontSize: 16, fontWeight: option == selected ? FontWeight.w600 : FontWeight.w400),
                          ),
                        ),
                        Icon(
                          option == selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: option == selected ? const Color(0xFFC7F137) : const Color(0xFF6B6B6B),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class TodayPlanPage extends StatefulWidget {
  const TodayPlanPage({super.key});

  @override
  State<TodayPlanPage> createState() => _TodayPlanPageState();
}

class _TodayPlanPageState extends State<TodayPlanPage> {
  List<_TodayGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 1));
    try {
      final events = await FitApi.trainerCalendar(from: from, to: to);
      if (!mounted) return;
      final grouped = <String, List<FitCalendarEvent>>{};
      for (final event in events) {
        grouped.putIfAbsent('${event.time}|${event.place}|${event.status}|${event.online}', () => []).add(event);
      }
      setState(() {
        _groups = grouped.entries.map((entry) {
          final sample = entry.value.first;
          return _TodayGroup(
            time: sample.time,
            place: sample.place,
            online: sample.online,
            status: sample.status,
            eventId: sample.id,
            clients: entry.value
                .map((event) => _TodayClient(name: event.name, tags: event.tags, eventId: event.id))
                .toList(),
          );
        }).toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const HubBackTitle(title: 'Тренировок сегодня'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (_groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text('На сегодня тренировок нет', style: TextStyle(color: AppColors.fitGrey)),
                  ),
                for (var i = 0; i < _groups.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _TodaySlotCard(group: _groups[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayClient {
  const _TodayClient({required this.name, required this.tags, this.eventId = 0});

  final String name;
  final List<String> tags;
  final int eventId;
}

class _TodayGroup {
  const _TodayGroup({
    required this.time,
    required this.place,
    required this.online,
    required this.status,
    required this.clients,
    this.eventId = 0,
  });

  final String time;
  final String place;
  final bool online;
  final String status;
  final int eventId;
  final List<_TodayClient> clients;
}

class _TodaySlotCard extends StatelessWidget {
  const _TodaySlotCard({required this.group});

  final _TodayGroup group;

  @override
  Widget build(BuildContext context) {
    final status = switch (group.status) {
      'Завершено' => (bg: const Color(0xFFC7F137), fg: Colors.black),
      'В процессе' => (bg: const Color(0xFFFEB94B), fg: Colors.black),
      _ => (bg: const Color(0xFF3A3A3A), fg: Colors.white),
    };
    return GestureDetector(
      onTap: group.eventId > 0 ? () => context.push(RouteNames.calendarEventDetail, extra: group.eventId) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF323232)),
        ),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, size: 18, color: Color(0xFF979797)),
                    const SizedBox(width: 6),
                    Text(group.time, style: const TextStyle(color: Color(0xFFE6E6E6), fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF4A4A4A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            group.online ? 'assets/icons/usefull/online.svg' : 'assets/icons/usefull/zal.svg',
                            width: 18,
                            height: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(group.place, style: const TextStyle(color: Color(0xFF979797), fontSize: 14, height: 1)),
                        ],
                      ),
                    ),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: status.bg, borderRadius: BorderRadius.circular(18)),
                      child: Text(group.status, style: TextStyle(color: status.fg, fontSize: 14, fontWeight: FontWeight.w700, height: 1)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < group.clients.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _TodayClientCard(client: group.clients[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayClientCard extends StatelessWidget {
  const _TodayClientCard({required this.client});

  final _TodayClient client;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: client.eventId > 0
          ? () => context.push(RouteNames.calendarEventDetail, extra: client.eventId)
          : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            HubAvatar(letter: client.name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final tag in client.tags) _TodayTag(label: tag)],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayTag extends StatelessWidget {
  const _TodayTag({required this.label});

  final String label;

  (String, double) get _asset => switch (label) {
        'Бег' => ('assets/icons/exercises/treadmill.svg', 24),
        'Ноги' => ('assets/icons/exercises/stretching-round.svg', 20),
        'Кардио' => ('assets/icons/exercises/cardio.svg', 20),
        'Пресс' => ('assets/icons/exercises/press.svg', 20),
        'Грудь' => ('assets/icons/exercises/chest.svg', 20),
        _ => ('assets/icons/exercises/treadmill.svg', 24),
      };

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A4A4A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            asset.$1,
            width: asset.$2,
            height: asset.$2,
            colorFilter: const ColorFilter.mode(Color(0xFF979797), BlendMode.srcIn),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 14)),
        ],
      ),
    );
  }
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String _period = 'Месяц';
  Map<String, dynamic> _report = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final report = await FitApi.trainerReport(_period == 'Неделя' ? 'week' : 'month');
      if (mounted) setState(() => _report = report);
    } catch (_) {}
  }

  int _kindCount(String bucket) {
    final list = _report['by_kind'];
    if (list is! List) return 0;
    var sum = 0;
    for (final item in list.whereType<Map>()) {
      final kind = item['kind']?.toString() ?? '';
      final total = int.tryParse('${item['total']}') ?? 0;
      final stretch = kind == 'stretch' || kind == 'flexibility' || kind == 'stretching';
      final known = kind == 'strength' || kind == 'cardio' || stretch;
      final match = switch (bucket) {
        'strength' => kind == 'strength',
        'cardio' => kind == 'cardio',
        'stretch' => stretch,
        _ => !known,
      };
      if (match) sum += total;
    }
    return sum;
  }

  String _pct(int part, int total) => total == 0 ? '0%' : '${(part * 100 / total).round()}%';

  @override
  Widget build(BuildContext context) {
    final sessions = int.tryParse('${_report['sessions_count']}') ?? 0;
    final hours = _report['hours_total']?.toString() ?? '0';
    final gender = _report['gender'] is Map ? Map<String, dynamic>.from(_report['gender'] as Map) : const <String, dynamic>{};
    final clientsTotal = int.tryParse('${gender['total']}') ?? 0;
    final fresh = int.tryParse('${_report['new_clients']}') ?? 0;
    final left = int.tryParse('${_report['left_clients']}') ?? 0;
    final rest = (clientsTotal - fresh - left).clamp(0, 1000000);
    final strength = _kindCount('strength');
    final cardio = _kindCount('cardio');
    final stretch = _kindCount('stretch');
    final other = _kindCount('other');
    return FitScaffold(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const HubBackTitle(title: 'Отчет по тренировкам'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ReportStat(
                          asset: 'assets/icons/usefull/dumbbless.svg',
                          tint: const Color(0xFFC7F137),
                          label: 'Всего\nтренировок',
                          value: '$sessions',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ReportStat(
                          asset: 'assets/icons/usefull/time.svg',
                          tint: const Color(0xFFFF9F0A),
                          label: 'Часов\nпроведено',
                          value: hours,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                HubCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Динамика Тренировки', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text('Тренировок за день', style: TextStyle(color: Color(0xFF979797), fontSize: 14)),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            initialValue: _period,
                            color: const Color(0xFF232323),
                            onSelected: (value) {
                              setState(() => _period = value);
                              _load();
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'Неделя', child: Text('Неделя', style: TextStyle(color: Colors.white))),
                              PopupMenuItem(value: 'Месяц', child: Text('Месяц', style: TextStyle(color: Colors.white))),
                              PopupMenuItem(value: 'Год', child: Text('Год', style: TextStyle(color: Colors.white))),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF3A3A3A)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_period, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                  const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DynamicsChart(report: _report),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                HubCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Распределение по типам', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TypeStat(
                                        asset: 'assets/icons/quick-action/dumbell.svg',
                                        assetSize: 18,
                                        color: const Color(0xFFC7F137),
                                        percent: _pct(strength, sessions),
                                        label: 'Силовые',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _TypeStat(
                                        asset: 'assets/icons/quick-action/person-bold.svg',
                                        assetSize: 20,
                                        color: const Color(0xFF45C4FF),
                                        percent: _pct(stretch, sessions),
                                        label: 'Растяжка',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TypeStat(
                                        asset: 'assets/icons/quick-action/cardio.svg',
                                        assetSize: 20,
                                        color: const Color(0xFFFF6B6B),
                                        percent: _pct(cardio, sessions),
                                        label: 'Кардио',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _TypeStat(
                                        asset: 'assets/icons/quick-action/bicycle.svg',
                                        assetSize: 20,
                                        color: const Color(0xFFF5B431),
                                        percent: _pct(other, sessions),
                                        label: 'Другие',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TypeDonut(
                            strength: strength,
                            cardio: cardio,
                            stretch: stretch,
                            other: other,
                            total: sessions,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                HubCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Клиентская база', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(color: Color(0xFF979797), fontSize: 16),
                          children: [
                            const TextSpan(text: 'Всего клиентов: '),
                            TextSpan(text: '$clientsTotal', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(8)),
                        child: SizedBox(
                          height: 8,
                          child: Row(
                            children: [
                              Expanded(flex: left == 0 ? 1 : left, child: const ColoredBox(color: Color(0xFFFF7A72))),
                              Expanded(flex: fresh == 0 ? 1 : fresh, child: const ColoredBox(color: Color(0xFF3DDC97))),
                              Expanded(flex: rest == 0 ? 1 : rest, child: const ColoredBox(color: Color(0xFFF5B431))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ClientLine(color: const Color(0xFF3DDC97), label: 'Новые клиенты: ', value: '+$fresh', up: true),
                      const SizedBox(height: 10),
                      _ClientLine(color: const Color(0xFFFF7A72), label: 'Ушедшие клиенты: ', value: '-$left', up: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({required this.asset, required this.tint, required this.label, required this.value});

  final String asset;
  final Color tint;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return HubCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12)),
                child: SvgPicture.asset(asset, width: 16, height: 16, colorFilter: ColorFilter.mode(tint, BlendMode.srcIn)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 13, height: 1.15)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1)),
        ],
      ),
    );
  }
}

class _TypeStat extends StatelessWidget {
  const _TypeStat({required this.asset, required this.assetSize, required this.color, required this.percent, required this.label});

  final String asset;
  final double assetSize;
  final Color color;
  final String percent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: SvgPicture.asset(
            asset,
            width: assetSize,
            height: assetSize,
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(percent, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypeDonut extends StatelessWidget {
  const _TypeDonut({
    required this.strength,
    required this.cardio,
    required this.stretch,
    required this.other,
    required this.total,
  });

  final int strength;
  final int cardio;
  final int stretch;
  final int other;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = total <= 0 ? 1 : total;
    final segments = <(double, Color)>[
      (strength / t, const Color(0xFFC7F137)),
      (cardio / t, const Color(0xFFFF6B6B)),
      (stretch / t, const Color(0xFF45C4FF)),
      (other / t, const Color(0xFFF5B431)),
    ];
    // Fallback demo segments when all zero — match Figma look.
    final paintSegments = total <= 0
        ? const <(double, Color)>[
            (0.40, Color(0xFFC7F137)),
            (0.30, Color(0xFFFF6B6B)),
            (0.20, Color(0xFF45C4FF)),
            (0.10, Color(0xFFF5B431)),
          ]
        : segments;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size(96, 96), painter: _DonutPainter(paintSegments)),
          const _FireMark(),
        ],
      ),
    );
  }
}

class _FireMark extends StatelessWidget {
  const _FireMark();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/usefull/fire.svg', width: 22, height: 22);
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.segments);

  final List<(double, Color)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    const gap = 0.06;
    var start = -1.5708; // top
    final sum = segments.fold<double>(0, (a, s) => a + s.$1);
    final norm = sum <= 0 ? 1.0 : sum;
    for (final segment in segments) {
      final portion = segment.$1 / norm;
      if (portion <= 0) continue;
      final sweep = (portion * 6.28318 - gap).clamp(0.0, 6.28318);
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = segment.$2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.butt,
      );
      start += portion * 6.28318;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => oldDelegate.segments != segments;
}

class _ClientLine extends StatelessWidget {
  const _ClientLine({required this.color, required this.label, required this.value, required this.up});

  final Color color;
  final String label;
  final String value;
  final bool up;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 15)),
        Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 16),
      ],
    );
  }
}

class _DynamicsChart extends StatefulWidget {
  const _DynamicsChart({this.report = const {}});

  final Map<String, dynamic> report;

  @override
  State<_DynamicsChart> createState() => _DynamicsChartState();
}

class _DynamicsChartState extends State<_DynamicsChart> {
  int? _selected;

  void _pick(Offset local, Size size, List<double> values) {
    final points = _DynamicsPainter(selected: null, values: values).pointsFor(size);
    var index = 0;
    var nearest = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (points[i].dx - local.dx).abs();
      if (distance < nearest) {
        nearest = distance;
        index = i;
      }
    }
    if (_selected != index) setState(() => _selected = index);
  }

  List<double> get _values {
    final raw = widget.report['by_day'] ?? widget.report['daily'] ?? widget.report['points'];
    if (raw is! List) return const [];
    return [
      for (final item in raw.whereType<Map>())
        double.tryParse('${item['count'] ?? item['total'] ?? item['sessions'] ?? item['value']}') ?? 0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    if (values.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text('По дням данных нет', style: TextStyle(color: Color(0xFF979797))),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 196);
        return Listener(
          onPointerDown: (event) => _pick(event.localPosition, size, values),
          onPointerMove: (event) => _pick(event.localPosition, size, values),
          onPointerUp: (_) => setState(() => _selected = null),
          onPointerCancel: (_) => setState(() => _selected = null),
          child: SizedBox(
            height: 196,
            width: double.infinity,
            child: CustomPaint(painter: _DynamicsPainter(selected: _selected, values: values)),
          ),
        );
      },
    );
  }
}

class _DynamicsPainter extends CustomPainter {
  const _DynamicsPainter({required this.selected, this.values = const []});

  final int? selected;
  final List<double> values;

  static const _values = [2.5, 2.7, 6.0, 1.35, 1.35, 4.1, 2.6];
  static const _labels = ['01', '02', '03', '04', '05', '06', '07'];

  List<double> get _series => values.length < 2 ? _values : values;

  double get _maxV {
    final peak = _series.reduce((a, b) => a > b ? a : b);
    return peak <= 0 ? 1 : peak * 1.1;
  }

  static Rect _chart(Size size) => Rect.fromLTWH(6, 36, size.width - 12, size.height - 58);

  List<Offset> pointsFor(Size size) {
    final chart = _chart(size);
    final series = _series;
    return [
      for (var i = 0; i < series.length; i++)
        Offset(
          chart.left + chart.width * i / (series.length - 1),
          chart.bottom - (series[i] / _maxV) * chart.height,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chart = _chart(size);
    final points = pointsFor(size);
    final fill = Path()..moveTo(points.first.dx, chart.bottom);
    for (final spot in points) {
      fill.lineTo(spot.dx, spot.dy);
    }
    fill
      ..lineTo(points.last.dx, chart.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x38C7F137), Color(0x1A232323)],
        ).createShader(chart),
    );

    if (selected != null) {
      final peak = points[selected!];
      final barRect = Rect.fromLTRB(peak.dx - 9, peak.dy, peak.dx + 9, chart.bottom);
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(9)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66C7F137), Color(0x0DC7F137)],
          ).createShader(barRect),
      );
    }

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final spot in points.skip(1)) {
      line.lineTo(spot.dx, spot.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFFC7F137)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < points.length; i++) {
      if (i == selected) continue;
      canvas.drawCircle(points[i], 5, Paint()..color = Colors.white);
      canvas.drawCircle(points[i], 3.2, Paint()..color = const Color(0xFFC7F137));
    }

    if (selected != null) {
      final peak = points[selected!];
      final badge = TextPainter(
        text: TextSpan(
          text: _series[selected!].round().toString(),
          style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bubble = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(peak.dx, peak.dy - 26), width: badge.width + 18, height: 26),
        const Radius.circular(13),
      );
      final bubblePaint = Paint()..color = const Color(0xFF7DDE5A);
      canvas.drawRRect(bubble, bubblePaint);
      final tip = Path()
        ..moveTo(peak.dx - 5, bubble.bottom - 1)
        ..lineTo(peak.dx + 5, bubble.bottom - 1)
        ..lineTo(peak.dx, bubble.bottom + 6)
        ..close();
      canvas.drawPath(tip, bubblePaint);
      badge.paint(canvas, Offset(bubble.left + 9, bubble.top + 4));
    }

    final labelCount = points.length < _labels.length ? points.length : _labels.length;
    for (var i = 0; i < labelCount; i++) {
      final label = TextPainter(
        text: TextSpan(text: _labels[i], style: const TextStyle(color: Color(0xFF979797), fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(points[i].dx - label.width / 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicsPainter oldDelegate) => oldDelegate.selected != selected;
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<FitNotice> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = await FitApi.notifications('today');
      final later = await FitApi.notifications('later');
      if (!mounted) return;
      setState(() => _items = [...today, ...later]);
    } catch (_) {}
  }

  Map<String, List<FitNotice>> get _groups {
    final now = DateTime.now();
    final groups = <String, List<FitNotice>>{};
    for (final item in _items) {
      final date = item.createdAt;
      final title = date == null
          ? 'Позже'
          : (date.year == now.year && date.month == now.month && date.day == now.day)
              ? 'Сегодня'
              : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
      groups.putIfAbsent(title, () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          HubBackTitle(
            title: 'Уведомления',
            trailing: IconButton(
              onPressed: () async {
                try {
                  await FitApi.readAllNotifications();
                  await _load();
                } catch (error) {
                  if (!context.mounted) return;
                  Toast.error(FitApi.messageOf(error));
                }
              },
              icon: const Icon(Icons.done_all, color: AppColors.accent),
            ),
          ),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('Уведомлений нет', style: TextStyle(color: AppColors.fitGrey)),
            ),
          for (final entry in groups.entries)
            _NotifGroup(
              title: entry.key,
              items: entry.value,
              onTap: _openNotice,
            ),
        ],
      ),
    );
  }

  Future<void> _openNotice(FitNotice item) async {
    try {
      if (!item.isRead) await FitApi.readNotification(item.id);
    } catch (_) {}
    if (!mounted) return;
    switch (item.type) {
      case 'new_client_request':
        context.push(RouteNames.trainerRequests);
      case 'request_sent':
      case 'request_accepted':
      case 'request_rejected':
        context.push(RouteNames.myTrainerRequests);
      case 'workout':
      case 'workout_cancelled':
        context.push(RouteNames.clientCalendar);
      case 'program_assigned':
        final programId = int.tryParse('${item.payload['program_id']}') ?? 0;
        if (programId > 0) {
          context.push(RouteNames.programDetail, extra: programId);
        } else {
          context.push(RouteNames.assignedVideos);
        }
      case 'video_assigned':
        context.push(RouteNames.assignedVideos);
      default:
        await _load();
    }
  }
}

class _NotifGroup extends StatelessWidget {
  const _NotifGroup({required this.title, required this.items, required this.onTap});

  final String title;
  final List<FitNotice> items;
  final ValueChanged<FitNotice> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(title, style: const TextStyle(color: AppColors.fitGrey)),
        ),
        for (final item in items)
          GestureDetector(
            onTap: () => onTap(item),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.fitCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: !item.isRead ? AppColors.accent : Colors.transparent),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(item.body, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text(
                    item.createdAt == null
                        ? ''
                        : '${item.createdAt!.hour.toString().padLeft(2, '0')}:${item.createdAt!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, bool> _prefs = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final data = await FitApi.notificationPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = {
          for (final key in const [
            'push_enabled',
            'email_enabled',
            'workout_reminder',
            'new_client_request',
            'client_report',
          ])
            key: data[key] == true,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs = {..._prefs, key: value});
    try {
      await FitApi.patchNotificationPreferences({key: value});
    } catch (error) {
      if (!mounted) return;
      setState(() => _prefs = {..._prefs, key: !value});
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = <String, String>{
      'push_enabled': 'Push-уведомления',
      'email_enabled': 'Email-уведомления',
      'workout_reminder': 'Напоминания о тренировках',
      'new_client_request': 'Новые заявки клиентов',
      'client_report': 'Отчёты по клиентам',
    };
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          const HubBackTitle(title: 'Настройки'),
          const Text('Уведомления', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          HubCard(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  )
                : Column(
                    children: [
                      for (final entry in labels.entries)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value, style: const TextStyle(color: Colors.white, fontSize: 15)),
                          value: _prefs[entry.key] ?? false,
                          activeThumbColor: Colors.black,
                          activeTrackColor: AppColors.accent,
                          onChanged: (value) => _toggle(entry.key, value),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          const Text('Безопасность', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          HubCard(
            child: HubMenuTile(
              icon: Icons.lock_reset,
              label: 'Сменить пароль',
              onTap: () => _changePassword(context),
            ),
          ),
          const SizedBox(height: 18),
          const Text('О приложении', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const HubCard(
            child: HubMenuTile(
              icon: Icons.verified_outlined,
              label: 'Версия приложения',
              trailing: '2.4.1',
              onTap: _noop,
            ),
          ),
        ],
      ),
    );
  }
}

void _noop() {}

Future<void> _changePassword(BuildContext context) async {
  final oldPassword = TextEditingController();
  final newPassword = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1C),
      title: const Text('Сменить пароль', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: oldPassword, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Текущий пароль')),
          TextField(controller: newPassword, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Новый пароль')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
      ],
    ),
  );
  if (saved != true || newPassword.text.trim().length < 8) return;
  try {
    await FitApi.changePassword(oldPassword: oldPassword.text, newPassword: newPassword.text.trim());
    if (context.mounted) Toast.success('Пароль изменён');
  } catch (error) {
    if (context.mounted) Toast.error(FitApi.messageOf(error));
  }
}

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  Map<String, dynamic>? _sub;
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _payments = const [];
  bool _loading = true;
  bool _paying = false;

  String get _audience {
    final trainer = ref.read(fitSessionProvider).user?.role != FitRole.client;
    return trainer ? 'pro_trainer' : 'pro_client';
  }

  bool get _active => _sub?['status']?.toString() == 'active';

  bool get _autoRenew => _sub?['auto_renew'] != false;

  String get _endsLabel {
    final raw = _sub?['ends_at'] ?? _sub?['current_period_end'] ?? _sub?['active_until'];
    return DateHelper.formatRuDayMonthYearAny(raw, fallback: '');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final sub = await FitApi.subscription(_audience);
      final plans = await FitApi.plans(_audience);
      final payments = await FitApi.payments();
      if (!mounted) return;
      setState(() {
        _sub = sub;
        _plans = plans;
        _payments = payments;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  String _planTitle(Map<String, dynamic> plan) {
    final amount = _money(plan['price_amount']);
    final period = switch (plan['period']?.toString()) {
      'year' => 'год',
      'month' => 'месяц',
      _ => plan['period']?.toString() ?? '',
    };
    final currency = plan['currency']?.toString() == 'RUB' ? '₽' : (plan['currency']?.toString() ?? '');
    return '$amount $currency / $period';
  }

  String _money(Object? value) {
    final number = double.tryParse('$value'.replaceAll(',', '.'));
    if (number == null) return '$value';
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(2);
  }

  String _paymentStatus(String? status) {
    return switch (status) {
      'paid' || 'succeeded' => 'Оплачено',
      'pending' => 'Ожидает',
      'failed' => 'Ошибка оплаты',
      'refunded' => 'Возврат',
      _ => status ?? '—',
    };
  }

  Future<void> _resume() async {
    try {
      await FitApi.resumeSubscription();
      if (mounted) Toast.success('Автопродление включено');
      await _load();
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _retryPayment(Map<String, dynamic> payment) async {
    final planId = int.tryParse('${payment['plan_id'] ?? ''}') ?? 0;
    if (planId != 0) {
      await _pay({'id': planId});
      return;
    }
    if (_plans.isNotEmpty) {
      await _pay(_plans.first);
      return;
    }
    Toast.error('Тариф для повторной оплаты не найден');
  }

  Future<void> _pay(Map<String, dynamic> plan) async {
    final id = int.tryParse('${plan['id']}') ?? 0;
    if (id == 0 || _paying) return;
    setState(() => _paying = true);
    try {
      final checkout = await FitApi.checkout(id);
      final provider = checkout['provider']?.toString() ?? '';
      final status = checkout['status']?.toString() ?? '';
      if (provider == 'mock' || status == 'active' || status == 'paid') {
        if (mounted) Toast.success('Подписка PRO активна');
        await _load();
        return;
      }
      final url = checkout['payment_url']?.toString() ?? '';
      final paymentId = int.tryParse('${checkout['payment_id'] ?? checkout['inv_id']}') ?? 0;
      if (url.isEmpty || paymentId == 0) {
        Toast.error('Не удалось получить ссылку на оплату');
        return;
      }
      if (!mounted) return;
      final result = await openRobokassaPay(context, paymentUrl: url, paymentId: paymentId, audience: _audience);
      if (!mounted) return;
      switch (result) {
        case RobokassaPayResult.paid:
          Toast.success('Подписка PRO активна');
        case RobokassaPayResult.pending:
          Toast.info('Оплата обрабатывается, обновите экран через минуту');
        case RobokassaPayResult.failed:
          Toast.error('Оплата не прошла');
        case RobokassaPayResult.cancelled:
          break;
      }
      await _load();
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Отменить подписку?', style: TextStyle(color: Colors.white)),
        content: const Text('PRO останется до конца оплаченного периода.', style: TextStyle(color: AppColors.fitGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Оставить')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отменить', style: TextStyle(color: Color(0xFFFD6565)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FitApi.cancelSubscription();
      if (mounted) Toast.success('Автопродление отменено');
      await _load();
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  String _fromPriceLabel() {
    if (_plans.isEmpty) return '';
    double? minAmount;
    String period = 'мес';
    for (final plan in _plans) {
      final n = double.tryParse('${plan['price_amount']}'.replaceAll(',', '.'));
      if (n == null) continue;
      if (minAmount == null || n < minAmount) {
        minAmount = n;
        period = switch (plan['period']?.toString()) {
          'year' => 'год',
          'month' => 'мес',
          _ => plan['period']?.toString() ?? 'мес',
        };
      }
    }
    if (minAmount == null) return '';
    final amount = minAmount == minAmount.roundToDouble()
        ? minAmount.toInt().toString()
        : minAmount.toStringAsFixed(2);
    return 'от $amount ₽/$period';
  }

  @override
  Widget build(BuildContext context) {
    final trainer = ref.watch(fitSessionProvider).user?.role != FitRole.client;
    const dune = Color(0xFF323232);
    const pink = Color(0xFFFD6565);
    // Figma: trainer vs client perk lists differ.
    final perks = trainer
        ? const [
            'Безлимитное число клиентов',
            'Готовые программы тренировок',
            'Расширенная статистика',
            'Приоритетная поддержка 24/7',
          ]
        : const [
            '50+ программ от профи',
            'Новые тренировки каждую неделю',
            'Видео-инструкции к каждому упражнению',
            'Приоритетная поддержка 24/7',
          ];
    final headline = !trainer && !_active
        ? 'Откройте программы от лучших тренеров'
        : 'PRO подписка';
    final subtitle = _active && _endsLabel.isNotEmpty
        ? 'Активна до $_endsLabel'
        : (!trainer
            ? 'Персональные программы, видео-инструкции и поддержка сертифицированных экспертов.'
            : 'Подписка не оформлена');
    final cardBorder = !trainer && !_active ? AppColors.accent : dune;
    final fromPrice = _fromPriceLabel();
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: fitAlwaysScroll,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const HubBackTitle(title: 'Подписка PRO'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cardBorder, width: 1.12),
                image: const DecorationImage(
                  image: AssetImage('assets/images/price-card-bg.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dune),
                    ),
                    child: SvgPicture.asset('assets/icons/pro/crown.svg', width: 24, height: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(headline, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF979797), fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dune),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < perks.length; i++) ...[
                          if (i > 0) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1, thickness: 1, color: dune),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              SvgPicture.asset('assets/icons/check.svg', width: 20, height: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  perks[i],
                                  style: const TextStyle(color: Color(0xFF979797), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_active) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () => context.push(RouteNames.manageSub),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: const Color(0xFF0C0C0C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('Управлять подпиской', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_autoRenew)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _confirmCancel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: pink,
                            side: const BorderSide(color: dune),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Отменить подписку', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _resume,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: dune),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Возобновить подписку', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                  ] else ...[
                    const SizedBox(height: 12),
                    if (_plans.isEmpty)
                      const Text('Тарифы недоступны', style: TextStyle(color: Color(0xFF979797)))
                    else if (!trainer) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _paying ? null : () => _pay(_plans.first),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: const Color(0xFF0C0C0C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text(
                            _paying
                                ? '…'
                                : (fromPrice.isEmpty
                                    ? 'Оформить PRO'
                                    : 'Оформить PRO — $fromPrice'),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                      if (_plans.length > 1) ...[
                        const SizedBox(height: 12),
                        for (var i = 0; i < _plans.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _paying ? null : () => _pay(_plans[i]),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: dune),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                _planTitle(_plans[i]),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ] else
                      for (final plan in _plans) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _paying ? null : () => _pay(plan),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: const Color(0xFF0C0C0C),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: Text(
                              _paying ? '…' : 'Оформить · ${_planTitle(plan)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF232323),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: dune),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text('История платежей', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF292929),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: dune),
                    ),
                    child: _payments.isEmpty
                        ? const Text('Платежей нет', style: TextStyle(color: Color(0xFF979797), fontSize: 14))
                        : Column(
                            children: [
                              for (var i = 0; i < _payments.length; i++) ...[
                                if (i > 0) ...[
                                  const SizedBox(height: 16),
                                  const Divider(height: 1, thickness: 1, color: dune),
                                  const SizedBox(height: 16),
                                ],
                                _PayRow(
                                  dateAmount:
                                      '${DateHelper.formatRuShortAny(_payments[i]['created_at'] ?? _payments[i]['paid_at'])} · ${_paymentAmount(_payments[i])}',
                                  status: _paymentStatus(_payments[i]['status']?.toString()),
                                  statusKind: switch (_payments[i]['status']?.toString()) {
                                    'paid' || 'succeeded' => _PayStatusKind.paid,
                                    'failed' => _PayStatusKind.failed,
                                    _ => _PayStatusKind.other,
                                  },
                                  onRetry: _payments[i]['status']?.toString() == 'failed'
                                      ? () => _retryPayment(_payments[i])
                                      : null,
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _paymentAmount(Map<String, dynamic> payment) {
    final amount = _money(payment['amount'] ?? payment['price_amount']);
    final currency = payment['currency']?.toString();
    final suffix = currency == 'RUB' || currency == null || currency.isEmpty ? '₽' : currency;
    return '$amount $suffix';
  }
}

enum _PayStatusKind { paid, failed, other }

class _PayRow extends StatelessWidget {
  const _PayRow({
    required this.dateAmount,
    required this.status,
    required this.statusKind,
    this.onRetry,
  });

  final String dateAmount;
  final String status;
  final _PayStatusKind statusKind;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final pillBg = switch (statusKind) {
      _PayStatusKind.paid => const Color(0xFF1E2603),
      _PayStatusKind.failed => const Color(0xFF290700),
      _PayStatusKind.other => const Color(0xFF2A2A2A),
    };
    final pillFg = switch (statusKind) {
      _PayStatusKind.paid => AppColors.accent,
      _PayStatusKind.failed => const Color(0xFFFD6565),
      _PayStatusKind.other => const Color(0xFF979797),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateAmount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onRetry,
                  behavior: HitTestBehavior.opaque,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Повторить оплату', style: TextStyle(color: AppColors.accent, fontSize: 14)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, color: AppColors.accent, size: 16),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(111)),
          alignment: Alignment.center,
          child: Text(status, style: TextStyle(color: pillFg, fontSize: 12)),
        ),
      ],
    );
  }
}

class ManageSubPage extends ConsumerStatefulWidget {
  const ManageSubPage({super.key});

  @override
  ConsumerState<ManageSubPage> createState() => _ManageSubPageState();
}

class _ManageSubPageState extends ConsumerState<ManageSubPage> {
  Map<String, dynamic>? _sub;
  bool _loading = true;

  String get _audience {
    final trainer = ref.read(fitSessionProvider).user?.role != FitRole.client;
    return trainer ? 'pro_trainer' : 'pro_client';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sub = await FitApi.subscription(_audience);
      if (!mounted) return;
      setState(() {
        _sub = sub;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  String _endsLabel() {
    final raw = _sub?['ends_at'] ?? _sub?['current_period_end'];
    return DateHelper.formatRuAny(raw, withTime: false);
  }

  @override
  Widget build(BuildContext context) {
    final active = _sub?['status']?.toString() == 'active';
    final autoRenew = _sub?['auto_renew'] != false;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          const HubBackTitle(title: 'Управление подпиской'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            )
          else
            HubCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Текущий план', style: TextStyle(color: AppColors.fitGrey)),
                  const SizedBox(height: 4),
                  Text(
                    active ? 'PRO · активна' : 'PRO не активна',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    active ? 'До $_endsLabel() · автопродление ${autoRenew ? 'вкл.' : 'выкл.'}' : 'Оформите подписку на экране PRO',
                    style: const TextStyle(color: AppColors.fitGrey),
                  ),
                  const SizedBox(height: 12),
                  HubMenuTile(icon: Icons.receipt_long, label: 'История платежей', onTap: () => context.push(RouteNames.subscription)),
                  if (active && autoRenew)
                    HubMenuTile(
                      icon: Icons.cancel_outlined,
                      label: 'Отменить автопродление',
                      onTap: () async {
                        try {
                          await FitApi.cancelSubscription();
                          if (context.mounted) Toast.success('Автопродление отменено');
                          _load();
                        } catch (error) {
                          if (context.mounted) Toast.error(FitApi.messageOf(error));
                        }
                      },
                    ),
                  if (active && !autoRenew)
                    HubMenuTile(
                      icon: Icons.refresh,
                      label: 'Возобновить автопродление',
                      onTap: () async {
                        try {
                          await FitApi.resumeSubscription();
                          if (context.mounted) Toast.success('Автопродление включено');
                          _load();
                        } catch (error) {
                          if (context.mounted) Toast.error(FitApi.messageOf(error));
                        }
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  List<({String title, String body})> _faqs = const [
    (title: 'Как добавить клиента?', body: 'Откройте список клиентов и нажмите «+». Можно найти человека в базе или создать карточку вручную.'),
    (title: 'Как отменить тренировку?', body: 'В календаре откройте тренировку и выберите «Отменить». Клиент получит уведомление.'),
    (title: 'Как работает подписка PRO?', body: 'PRO снимает лимит клиентов и открывает готовые программы, расширенную статистику и приоритетную поддержку.'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final faqs = await FitApi.faq('all');
      if (faqs.isEmpty || !mounted) return;
      setState(() => _faqs = faqs);
    } catch (_) {}
  }

  Future<void> _supportTicket() async {
    final subject = TextEditingController();
    final message = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Обращение в поддержку', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: subject, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Тема')),
            TextField(controller: message, maxLines: 4, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Сообщение')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отправить')),
        ],
      ),
    );
    if (ok != true || subject.text.trim().isEmpty || message.text.trim().isEmpty) return;
    try {
      await FitApi.createSupportTicket(subject: subject.text.trim(), message: message.text.trim());
      if (mounted) Toast.success('Обращение отправлено');
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final faqs = _faqs;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          const HubBackTitle(title: 'Центр помощи'),
          HubCard(
            child: HubMenuTile(
              icon: Icons.mail_outline,
              label: 'Написать в поддержку',
              onTap: _supportTicket,
            ),
          ),
          const SizedBox(height: 12),
          for (final faq in faqs) _FaqTile(title: faq.title, body: faq.body),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: HubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: _open ? 0.125 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 28),
                  child: Text(widget.body, style: const TextStyle(color: AppColors.fitGrey, height: 1.35)),
                ),
                crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.title, required this.body, this.docType});

  final String title;
  final String body;
  final String? docType;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late String _body = widget.body;

  @override
  void initState() {
    super.initState();
    final type = widget.docType;
    if (type == null) return;
    FitApi.legal(type).then((value) {
      if (value.isNotEmpty && mounted) setState(() => _body = value);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          HubBackTitle(title: widget.title),
          HubCard(child: Text(_body, style: const TextStyle(color: Colors.white70, height: 1.45))),
        ],
      ),
    );
  }
}

class SpecializationPage extends StatefulWidget {
  const SpecializationPage({super.key});

  @override
  State<SpecializationPage> createState() => _SpecializationPageState();
}

class _SpecializationPageState extends State<SpecializationPage> {
  List<({String code, String title})> _specOptions = const [];
  List<({String code, String title})> _formatOptions = const [];

  // editable state
  final Set<String> _selectedSpecs = {};
  final Set<String> _selectedFormats = {};
  final _priceCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  bool _freeConsult = false;
  bool _loading = true;
  bool _saving = false;

  static const _fallbackSpecs = <({String code, String title})>[
    (code: 'strength', title: 'Силовые тренировки'),
    (code: 'cardio', title: 'Кардио'),
    (code: 'yoga', title: 'Йога'),
    (code: 'stretching', title: 'Растяжка'),
    (code: 'crossfit', title: 'Кроссфит'),
    (code: 'boxing', title: 'Бокс'),
    (code: 'pilates', title: 'Пилатес'),
    (code: 'nutrition', title: 'Питание'),
    (code: 'rehabilitation', title: 'Реабилитация'),
    (code: 'functional', title: 'Функциональные'),
  ];

  static const _fallbackFormats = <({String code, String title})>[
    (code: 'gym', title: 'Зал'),
    (code: 'online', title: 'Онлайн'),
    (code: 'home', title: 'Дом'),
    (code: 'visit', title: 'Выезд'),
    (code: 'hybrid', title: 'Гибрид'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        FitApi.trainerProfile(),
        FitApi.dictionaries(),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final dicts = results[1] as List<({String category, String code, String title})>;

      final specOpts = dicts.where((d) => d.category == 'fitness_goal' || d.category == 'specialization').toList();
      final formatOpts = dicts.where((d) => d.category == 'training_format' || d.category == 'work_format').toList();

      final specs = profile['specializations'];
      final formats = profile['work_formats'] ?? profile['training_formats'];
      final priceRaw = profile['session_price_amount']?.toString() ?? '';
      final priceNum = num.tryParse(priceRaw);
      final price = priceNum == null
          ? priceRaw
          : (priceNum == priceNum.roundToDouble() ? priceNum.round().toString() : priceNum.toStringAsFixed(2));
      final duration = profile['session_duration_min']?.toString() ?? '';
      final freeConsult = profile['free_first_consult'] == true ||
          profile['has_free_consultation'] == true ||
          profile['free_consultation'] == true;

      if (!mounted) return;
      setState(() {
        _specOptions = specOpts.isNotEmpty ? specOpts.map((d) => (code: d.code, title: d.title)).toList() : _fallbackSpecs;
        _formatOptions = formatOpts.isNotEmpty ? formatOpts.map((d) => (code: d.code, title: d.title)).toList() : _fallbackFormats;
        _selectedSpecs
          ..clear()
          ..addAll(specs is List ? specs.map((e) => e.toString()).where((s) => s.isNotEmpty) : []);
        _selectedFormats
          ..clear()
          ..addAll(formats is List ? formats.map((e) => e.toString()).where((s) => s.isNotEmpty) : []);
        _priceCtrl.text = price;
        _durationCtrl.text = duration;
        _freeConsult = freeConsult;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _specOptions = _fallbackSpecs;
          _formatOptions = _fallbackFormats;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final priceRaw = _priceCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.');
      final durationRaw = _durationCtrl.text.trim();
      await FitApi.patchTrainerProfile({
        'specializations': _selectedSpecs.toList(),
        'work_formats': _selectedFormats.toList(),
        if (priceRaw.isNotEmpty) 'session_price_amount': num.tryParse(priceRaw) ?? 0,
        if (durationRaw.isNotEmpty) 'session_duration_min': int.tryParse(durationRaw) ?? 60,
        'free_first_consult': _freeConsult,
      });
      if (!mounted) return;
      Toast.success('Сохранено');
    } catch (e) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return FitScaffold(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: const [
            HubBackTitle(title: 'Специализация и цены'),
            Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.accent))),
          ],
        ),
      );
    }
    return FitScaffold(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: HubBackTitle(title: 'Специализация и цены'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                // Specializations (Figma card)
                HubCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Специализация', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _specOptions
                            .map((opt) => _SpecChip(
                                  label: opt.title,
                                  selected: _selectedSpecs.contains(opt.code),
                                  onTap: () => setState(
                                    () => _selectedSpecs.contains(opt.code) ? _selectedSpecs.remove(opt.code) : _selectedSpecs.add(opt.code),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Work formats
                HubCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Онлайн / офлайн', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('Клиенты увидят, как вы проводите занятия', style: TextStyle(color: Color(0xFF979797), fontSize: 13)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _formatOptions
                            .map((opt) => _SpecChip(
                                  label: opt.title,
                                  selected: _selectedFormats.contains(opt.code),
                                  onTap: () => setState(
                                    () => _selectedFormats.contains(opt.code) ? _selectedFormats.remove(opt.code) : _selectedFormats.add(opt.code),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Price / duration
                HubCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Стоимость тренировок', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      const Text('Цена за занятие, ₽', style: TextStyle(color: Color(0xFF979797), fontSize: 14)),
                      const SizedBox(height: 8),
                      _DarkInput(controller: _priceCtrl, hint: 'Например: 2500', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                      const SizedBox(height: 12),
                      const Text('Длительность, мин', style: TextStyle(color: Color(0xFF979797), fontSize: 14)),
                      const SizedBox(height: 8),
                      _DarkInput(controller: _durationCtrl, hint: 'Например: 60', keyboardType: const TextInputType.numberWithOptions(decimal: false)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Free consultation toggle
                HubCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Первая встреча бесплатно', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      Switch(
                        value: _freeConsult,
                        onChanged: (v) => setState(() => _freeConsult = v),
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppColors.accent,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: const Color(0xFF3A3A3A),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: FitAccentButton(title: 'Сохранить', loading: _saving, onPressed: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : const Color(0xFF232323),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accent : const Color(0xFF3A3A3A)),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _DarkInput extends StatelessWidget {
  const _DarkInput({required this.controller, required this.hint, this.keyboardType});

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class BodyParamsPage extends StatefulWidget {
  const BodyParamsPage({super.key});

  @override
  State<BodyParamsPage> createState() => _BodyParamsPageState();
}

class _BodyParamsPageState extends State<BodyParamsPage> {
  List<(String, String, String, bool, List<double>)> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    const metrics = <(String, String)>[
      ('shoulders_cm', 'Плечи'),
      ('chest_cm', 'Грудь'),
      ('waist_cm', 'Талия'),
      ('hips_cm', 'Бедра'),
      ('neck_cm', 'Шея'),
      ('thigh_cm', 'Бёдра'),
      ('arm_left_cm', 'Бицепс'),
      ('forearm_cm', 'Предплечье'),
    ];
    final rows = <(String, String, String, bool, List<double>)>[];
    for (final metric in metrics) {
      try {
        final points = await FitApi.measurementChart(metric.$1);
        if (points.isEmpty) continue;
        final values = [for (final point in points) point.value];
        final delta = values.last - values.first;
        final sign = delta > 0 ? '+' : '';
        rows.add((metric.$2, values.last.toStringAsFixed(1), '$sign${delta.toStringAsFixed(1)} см', delta >= 0, values));
      } catch (_) {}
    }
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const HubBackTitle(title: 'Параметры тела'),
          HubCard(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text('Параметры тела', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Замеров пока нет', style: TextStyle(color: AppColors.fitGrey)),
                  ),
                for (final row in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.accessibility_new, color: AppColors.accent),
                    title: Text(row.$1, style: const TextStyle(color: Colors.white)),
                    subtitle: Sparkline(values: row.$5, color: row.$4 ? _up : _down),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(row.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            Text(row.$3, style: TextStyle(color: row.$4 ? _up : _down, fontSize: 12)),
                          ],
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.fitGrey),
                      ],
                    ),
                    onTap: () => context.push(RouteNames.measurements),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  static const _card = Color(0xFF232323);
  static const _border = Color(0xFF323232);
  static const _listBg = Color(0xFF292929);
  static const _label = Color(0xFF979797);

  List<FitNote> _notes = const [];
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await FitApi.clientNotes(q: _query);
      if (mounted) setState(() => _notes = notes);
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    final empty = _notes.isEmpty;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    const Icon(Icons.search, color: _label, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: _onSearchChanged,
                        cursorColor: AppColors.accent,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Найти заметки',
                          hintStyle: TextStyle(color: _label, fontSize: 14),
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _add,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Icon(Icons.add, color: AppColors.accent, size: 22),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (empty && _query.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 48, 8, 24),
            child: Column(
              children: [
                const Text(
                  'У вас пока нет заметок',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Создайте свою первую заметку, нажав на кнопку «+»',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _label, fontSize: 14, height: 1.35),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border, width: 1.12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Заметки', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _listBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _border),
                  ),
                  child: empty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text('Ничего не найдено', style: TextStyle(color: _label))),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < _notes.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _NoteCard(
                                note: _notes[i],
                                onTap: () => _openNoteDetail(_notes[i]),
                                onEdit: () => _edit(_notes[i]),
                                onDelete: () => _delete(_notes[i]),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _add() async {
    final result = await _openNoteSheet(title: 'Новая заметка');
    if (result == null || result.title.isEmpty) return;
    try {
      await FitApi.createNote(title: result.title, body: result.body);
      await _load();
    } catch (error) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _edit(FitNote note) async {
    final result = await _openNoteSheet(
      title: 'Изменить заметку',
      initialTitle: note.title,
      initialBody: note.body,
    );
    if (result == null || result.title.isEmpty) return;
    try {
      await FitApi.updateNote(id: note.id, title: result.title, body: result.body);
      await _load();
    } catch (error) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _openNoteDetail(FitNote note) async {
    final at = DateHelper.parseLocal(note.createdAt);
    final date = at == null
        ? '—'
        : '${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')}.${at.year}';
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final action = await showBlurredModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 5,
                    decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(date, style: const TextStyle(color: _label, fontSize: 13)),
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(time, style: const TextStyle(color: _label, fontSize: 13)),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: _label, size: 20),
                    ),
                  ],
                ),
                if (note.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(note.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ],
                if (note.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.45),
                    child: SingleChildScrollView(
                      child: Text(
                        note.body,
                        style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 14, height: 1.45),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFD6565),
                            side: const BorderSide(color: _border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Удалить', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, 'edit'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Изменить', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'edit') await _edit(note);
    if (action == 'delete') await _delete(note);
  }

  Future<({String title, String body})?> _openNoteSheet({
    required String title,
    String initialTitle = '',
    String initialBody = '',
  }) {
    final titleController = TextEditingController(text: initialTitle);
    final bodyController = TextEditingController(text: initialBody);
    return showBlurredModalBottomSheet<({String title, String body})>(
      context: context,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 5,
                    decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100)),
                  ),
                  const SizedBox(height: 16),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Заголовок заметки', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  _NoteField(controller: titleController, hint: 'Введите заголовок', autofocus: true),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Основной текст', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  _NoteField(
                    controller: bodyController,
                    hint: 'Введите ваши мысли, идеи, рецепты, результаты...',
                    maxLines: 5,
                    minHeight: 134,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: _border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Отменить', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: () {
                              final t = titleController.text.trim();
                              if (t.isEmpty) {
                                Toast.info('Введите заголовок');
                                return;
                              }
                              Navigator.pop(ctx, (title: t, body: bodyController.text.trim()));
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _delete(FitNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: _border)),
        title: const Text('Удалить заметку?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('Это действие нельзя отменить.', style: TextStyle(color: _label, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена', style: TextStyle(color: AppColors.accent))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить', style: TextStyle(color: Color(0xFFFD6565)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FitApi.deleteNote(note.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(error));
    }
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.minHeight,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final double? minHeight;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF323232)),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        maxLines: maxLines,
        cursorColor: AppColors.accent,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF979797), fontSize: 14),
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class ClientHomePage extends ConsumerStatefulWidget {
  const ClientHomePage({super.key});

  @override
  ConsumerState<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends ConsumerState<ClientHomePage> {
  int _tab = 0;
  int _refreshGen = 0;
  Map<String, dynamic> _home = const {};
  StreamSubscription<String>? _cacheSub;

  @override
  void initState() {
    super.initState();
    final cached = FitCache.I.peek<Map<String, dynamic>>('home');
    if (cached != null) _home = cached;
    _cacheSub = FitCache.I.updates.listen((key) {
      if (key != 'home' || !mounted) return;
      final next = FitCache.I.peek<Map<String, dynamic>>('home');
      if (next != null) setState(() => _home = next);
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => PushRegistration.askOnHome());
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final home = await FitApi.clientHome(force: force);
      if (mounted) setState(() => _home = home);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _load(force: true);
    if (!mounted) return;
    // Remount tab bodies so their GET loaders run again.
    setState(() => _refreshGen++);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(fitSessionProvider).user;
    final name = user == null || user.name.isEmpty ? 'Клиент' : user.name;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onRefresh: _refresh,
      child: ListView(
        physics: fitAlwaysScroll,
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _UserHeader(
            name: name,
            id: user?.uuid ?? '',
            badge: int.tryParse('${_home['unread_count']}') != 0,
            streak: int.tryParse('${_home['streak']}') ?? 0,
          ),
          const SizedBox(height: 24),
          _ProfileTabs(selected: _tab, onSelect: (i) => setState(() => _tab = i)),
          const SizedBox(height: 16),
          // Only the active tab takes height (IndexedStack used the tallest → empty scroll).
          // maintainState keeps tab state; keys bump on pull-to-refresh.
          Column(
            children: [
              Visibility(
                visible: _tab == 0,
                maintainState: true,
                maintainSize: false,
                child: _Overview(key: ValueKey('ov-$_refreshGen'), home: _home, onOpenNotes: () => setState(() => _tab = 4)),
              ),
              Visibility(
                visible: _tab == 1,
                maintainState: true,
                maintainSize: false,
                child: ClientWorkoutsTab(key: ValueKey('wo-$_refreshGen')),
              ),
              Visibility(
                visible: _tab == 2,
                maintainState: true,
                maintainSize: false,
                child: MeasuresTab(key: ValueKey('ms-$_refreshGen'), home: _home),
              ),
              Visibility(
                visible: _tab == 3,
                maintainState: true,
                maintainSize: false,
                child: ProgressTab(key: ValueKey('pr-$_refreshGen'), home: _home),
              ),
              Visibility(
                visible: _tab == 4,
                maintainState: true,
                maintainSize: false,
                child: NotesPage(key: ValueKey('nt-$_refreshGen')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _tabs = ['Обзор', 'Тренировки', 'Замеры', 'Прогресс', 'Заметки'];

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == i ? AppColors.accent : const Color(0xFF232323),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected == i ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF323232),
                  ),
                ),
                child: Text(
                  _tabs[i],
                  style: TextStyle(color: selected == i ? const Color(0xFF0C0C0C) : Colors.white, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({super.key, required this.home, this.onOpenNotes, this.linkId, this.onEditWeight});

  final Map<String, dynamic> home;
  final VoidCallback? onOpenNotes;

  /// Set when a trainer views a client: charts load that client's data.
  final int? linkId;
  final VoidCallback? onEditWeight;

  @override
  Widget build(BuildContext context) {
    String kg(Object? raw) {
      final v = double.tryParse('$raw'.replaceAll(',', '.'));
      if (v == null) return '—';
      return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
    }

    final weight = kg(home['weight_kg']);
    final deltaNum = double.tryParse('${home['weight_delta_30d']}'.replaceAll(',', '.'));
    final deltaText = deltaNum == null
        ? '—'
        : '${deltaNum > 0 ? '+' : ''}${deltaNum.toStringAsFixed(1).replaceAll('.', ',')} кг';
    final deltaColor = deltaNum == null || deltaNum == 0
        ? AppColors.fitGrey
        : (deltaNum > 0 ? const Color(0xFF37F184) : _down);
    final progress = double.tryParse('${home['progress_pct']}') ?? 0;
    final goal = kg(home['weight_goal_kg']);
    final last = home['last_session'] is Map ? Map<String, dynamic>.from(home['last_session'] as Map) : const <String, dynamic>{};
    final kindsLabel = FitLabels.kinds(last['kinds'] ?? last['kind'] ?? last['title']);
    final hasLast = last.isNotEmpty;
    final lastId = int.tryParse('${last['id']}') ?? 0;
    final topSets = last['top_sets'] is List
        ? (last['top_sets'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF323232)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _OverviewIconBox(asset: 'assets/icons/overview/weight.svg'),
                          const SizedBox(width: 8),
                          const Text('Вес', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$weight кг',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: onEditWeight ?? () => context.push(RouteNames.measurements),
                            child: SvgPicture.asset('assets/icons/overview/pen.svg', width: 20, height: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(deltaText, style: TextStyle(color: deltaColor, fontSize: 14)),
                      const SizedBox(height: 8),
                      const Text('За 30 дней', style: TextStyle(color: Color(0xFF979797), fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF323232)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _OverviewIconBox(asset: 'assets/icons/overview/progress.svg'),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Прогресс', style: TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${progress.round()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: (progress / 100).clamp(0, 1),
                          minHeight: 6,
                          color: AppColors.accent,
                          backgroundColor: const Color(0xFF3A3A3A),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('До $goal кг', style: const TextStyle(color: Color(0xFF979797), fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OverviewWeightDynamics(home: home, linkId: linkId),
        const SizedBox(height: 12),
        HubCard(
          padding: EdgeInsets.zero,
          child: _Attendance(marks: _attendanceMarks(home['attendance_30d'])),
        ),
        const SizedBox(height: 12),
        HubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Прошлая тренировка', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (lastId > 0) {
                        context.push(RouteNames.sessionDetail, extra: lastId);
                      } else if (linkId == null) {
                        context.push(RouteNames.lastWorkout);
                      }
                    },
                    child: const Row(
                      children: [
                        Text('Подробнее', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                        Icon(Icons.chevron_right, color: AppColors.accent, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                DateHelper.formatRuAny(last['finished_at'] ?? last['started_at']),
                style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (!hasLast)
                const Text('Нет тренировок', style: TextStyle(color: AppColors.fitGrey))
              else ...[
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/ready/bodyweight.svg',
                      width: 28,
                      height: 28,
                      placeholderBuilder: (_) => const Icon(Icons.accessibility_new, color: AppColors.fitGrey),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(kindsLabel, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _OverviewStatPod(
                      icon: Icons.timer_outlined,
                      iconColor: AppColors.accent,
                      value: formatWorkoutDuration(int.tryParse('${last['duration_sec']}')),
                      label: 'Минуты',
                    ),
                    const SizedBox(width: 8),
                    _OverviewStatPod(
                      icon: Icons.fitness_center,
                      iconColor: const Color(0xFF6EC8FF),
                      value: '${last['exercises_count'] ?? '—'}',
                      label: 'Упражн.',
                    ),
                    const SizedBox(width: 8),
                    _OverviewStatPod(
                      iconAsset: 'assets/icons/usefull/fire.svg',
                      iconColor: const Color(0xFFFF8A4C),
                      value: '${last['calories'] ?? '—'}',
                      label: 'Ккал',
                    ),
                  ],
                ),
                if (topSets.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Топ подходы', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final set in topSets.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              set['name']?.toString() ?? 'Упражнение',
                              style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                            ),
                          ),
                          Text(
                            '${set['weight_kg'] ?? '—'} кг × ${set['reps'] ?? '—'}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _TrainerNotesBlock(
          notes: [
            for (final item in (home['trainer_notes'] is List ? home['trainer_notes'] as List : const []))
              if (item is Map) (item['text']?.toString() ?? item['body']?.toString() ?? ''),
          ].where((text) => text.trim().isNotEmpty).toList(),
          onAdd: onOpenNotes,
        ),
      ],
    );
  }
}

class _OverviewIconBox extends StatelessWidget {
  const _OverviewIconBox({required this.asset, this.tint});

  final String asset;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF323232),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SvgPicture.asset(
        asset,
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        colorFilter: tint == null ? null : ColorFilter.mode(tint!, BlendMode.srcIn),
        placeholderBuilder: (_) => Icon(Icons.fitness_center, size: 18, color: tint ?? const Color(0xFFC7F137)),
      ),
    );
  }
}

class _OverviewStatPod extends StatelessWidget {
  const _OverviewStatPod({
    required this.value,
    required this.label,
    this.icon,
    this.iconAsset,
    this.iconColor = AppColors.accent,
  });

  final String value;
  final String label;
  final IconData? icon;
  final String? iconAsset;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            if (iconAsset != null)
              SvgPicture.asset(iconAsset!, width: 16, height: 16)
            else if (icon != null)
              Icon(icon, color: iconColor, size: 16),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _TrainerNotesBlock extends StatelessWidget {
  const _TrainerNotesBlock({required this.notes, this.onAdd});

  final List<String> notes;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return HubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Заметки тренера', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFC7F137), shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.black, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            const Text('Заметок тренера пока нет', style: TextStyle(color: AppColors.fitGrey, fontSize: 14))
          else
            for (var i = 0; i < notes.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF232323),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: Color(0xFF323232)),
                      ),
                      title: const Text('Заметка тренера', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      content: Text(notes[i], style: const TextStyle(color: Color(0xFF979797), height: 1.4)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть', style: TextStyle(color: AppColors.accent))),
                      ],
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF292929),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF323232)),
                  ),
                  child: Text(notes[i], style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 14, height: 1.4)),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, this.onTap, this.onEdit, this.onDelete});

  final FitNote note;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final at = DateHelper.parseLocal(note.createdAt);
    final date = at == null
        ? '—'
        : '${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')}.${at.year}';
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final body = note.body.trim().isEmpty ? note.title : note.body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF232323),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF323232)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(date, style: const TextStyle(color: Color(0xFF979797), fontSize: 13)),
                  const Spacer(),
                  if (time.isNotEmpty) Text(time, style: const TextStyle(color: Color(0xFF979797), fontSize: 13)),
                  if (onEdit != null || onDelete != null) ...[
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      color: const Color(0xFF292929),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF323232)),
                      ),
                      icon: const Icon(Icons.more_horiz, color: Color(0xFF979797), size: 20),
                      onSelected: (value) {
                        if (value == 'edit') onEdit?.call();
                        if (value == 'delete') onDelete?.call();
                      },
                      itemBuilder: (context) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, color: AppColors.accent, size: 16),
                                SizedBox(width: 8),
                                Text('Изменить', style: TextStyle(color: Colors.white, fontSize: 14)),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Color(0xFFFD6565), size: 16),
                                SizedBox(width: 8),
                                Text('Удалить', style: TextStyle(color: Color(0xFFFD6565), fontSize: 14)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              if (note.title.isNotEmpty && note.body.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LastWorkoutPage extends StatefulWidget {
  const LastWorkoutPage({super.key});

  @override
  State<LastWorkoutPage> createState() => _LastWorkoutPageState();
}

class _LastWorkoutPageState extends State<LastWorkoutPage> {
  Map<String, dynamic> _session = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final home = await FitApi.clientHome();
      final last = home['last_session'];
      if (last is Map && mounted) setState(() => _session = Map<String, dynamic>.from(last));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sets = _session['top_sets'];
    final moves = sets is List
        ? [
            for (final item in sets.whereType<Map>())
              (item['name']?.toString() ?? 'Упражнение', '${item['weight_kg'] ?? '—'} кг × ${item['reps'] ?? '—'}'),
          ]
        : <(String, String)>[];
    final minutes = ((int.tryParse('${_session['duration_sec']}') ?? 0) / 60).round();
    final kinds = FitLabels.kinds(_session['kinds'] ?? _session['kind'] ?? _session['title']);
    final when = DateHelper.formatRuAny(_session['finished_at'] ?? _session['started_at']);
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          const HubBackTitle(title: 'Прошлая тренировка'),
          Text('$when · $kinds', style: const TextStyle(color: AppColors.fitGrey)),
          const SizedBox(height: 12),
          Row(
            children: [
              _ChipStat(label: 'Минуты', value: '$minutes'),
              const SizedBox(width: 8),
              _ChipStat(label: 'Упражн.', value: '${_session['exercises_count'] ?? '—'}'),
              const SizedBox(width: 8),
              _ChipStat(label: 'Ккал', value: '${_session['calories'] ?? '—'}'),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Топ подходы', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (moves.isEmpty) const Text('Тренировок пока нет', style: TextStyle(color: AppColors.fitGrey)),
          for (final move in moves)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HubCard(
                child: Row(
                  children: [
                    Expanded(child: Text(move.$1, style: const TextStyle(color: Colors.white))),
                    Text(move.$2, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
