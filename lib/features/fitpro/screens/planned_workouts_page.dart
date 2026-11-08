import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/routes/route_names.dart';

const _kWeekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _kMonthsShort = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
const _kAccents = [Color(0xFFC7F137), Color(0xFFFF8A3D), Color(0xFF5EC8FF), Color(0xFF9E9E9E)];

/// Figma «Запланированные тренировки» — week grid (separate from Calendar tab).
class PlannedWorkoutsPage extends ConsumerStatefulWidget {
  const PlannedWorkoutsPage({super.key});

  @override
  ConsumerState<PlannedWorkoutsPage> createState() => _PlannedWorkoutsPageState();
}

class _PlannedWorkoutsPageState extends ConsumerState<PlannedWorkoutsPage> {
  static const _hourH = 72.0;
  static const _dayW = 118.0;
  static const _startHour = 8;
  static const _endHour = 22;

  late DateTime _weekStart;
  List<FitCalendarEvent> _events = const [];
  bool _loading = false;
  final _weekScroll = ScrollController();

  bool get _isTrainer => ref.read(fitSessionProvider).user?.role != FitRole.client;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_weekScroll.hasClients) return;
      const chipW = 118.0;
      const gap = 8.0;
      final target = 3 * (chipW + gap) - 40;
      _weekScroll.jumpTo(target.clamp(0.0, _weekScroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _weekScroll.dispose();
    super.dispose();
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 7));

  List<DateTime> get _days => List.generate(7, (i) => _weekStart.add(Duration(days: i)));

  List<DateTime> get _weekOptions => List.generate(7, (i) => _weekStart.subtract(Duration(days: (3 - i) * 7)));

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final events = _isTrainer
          ? await FitApi.trainerCalendar(from: _weekStart, to: _weekEnd, force: force)
          : await FitApi.clientCalendar(from: _weekStart, to: _weekEnd, force: force);
      if (!mounted) return;
      setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _events = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Color _accentFor(FitCalendarEvent e) => _kAccents[e.id % _kAccents.length];

  String _weekLabel(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    final a = monday.day.toString().padLeft(2, '0');
    final b = sunday.day.toString().padLeft(2, '0');
    if (monday.month == sunday.month) {
      return '${_kMonthsShort[monday.month - 1]} $a-$b';
    }
    return '${_kMonthsShort[monday.month - 1]}-${_kMonthsShort[sunday.month - 1]} $a-$b';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, onPrimary: Colors.black, surface: Color(0xFF232323)),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1C1C1C)),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() => _weekStart = day.subtract(Duration(days: day.weekday - 1)));
    await _load();
  }

  Future<void> _openAdd({DateTime? day, TimeOfDay? time}) async {
    if (!_isTrainer) return;
    final d = day ?? DateTime.now();
    final result = await context.push<Object?>(
      RouteNames.addCalendarEvent,
      extra: {
        'date': DateTime(d.year, d.month, d.day),
        if (time != null) 'time': time,
      },
    );
    if (!mounted) return;
    if (result is DateTime && (result.isBefore(_weekStart) || !result.isBefore(_weekEnd))) {
      final picked = DateTime(result.year, result.month, result.day);
      setState(() => _weekStart = picked.subtract(Duration(days: picked.weekday - 1)));
    }
    await _load(force: true);
  }

  void _openEvent(FitCalendarEvent event) {
    if (_isTrainer) {
      context.push(RouteNames.calendarEventDetail, extra: event.id).then((_) => _load());
      return;
    }
    showBlurredModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              Text(event.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(event.time, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  String _shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) return '${parts[0]} ${parts[1][0]}.';
    return name;
  }

  double _topFor(DateTime start) {
    final minutes = (start.hour - _startHour) * 60 + start.minute;
    return (minutes / 60.0) * _hourH;
  }

  double _heightFor(FitCalendarEvent e) {
    final mins = e.durationMin > 0
        ? e.durationMin
        : (e.endsAt != null && e.startsAt != null ? e.endsAt!.difference(e.startsAt!).inMinutes : 60);
    return ((mins / 60.0) * _hourH).clamp(36.0, (_endHour - _startHour) * _hourH);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final hourCount = _endHour - _startHour;
    final days = _days;

    return Scaffold(
      backgroundColor: AppColors.fitBg,
      floatingActionButton: _isTrainer
          ? FloatingActionButton(
              onPressed: () => _openAdd(),
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(RouteNames.trainerWorkouts);
                      }
                    },
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                  const Expanded(
                    child: Text(
                      'Запланированные тренировки',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  controller: _weekScroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: _weekOptions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final monday = _weekOptions[i];
                    final active = _sameDay(monday, _weekStart);
                    return GestureDetector(
                      onTap: () {
                        setState(() => _weekStart = monday);
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _weekLabel(monday),
                          style: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: const Color(0xFF232323),
                onRefresh: () => _load(silent: true, force: true),
                child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator(color: AppColors.accent)),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 120),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Time gutter + spacer for header row
                              Column(
                                children: [
                                  const SizedBox(height: 44),
                                  SizedBox(
                                    width: 48,
                                    height: hourCount * _hourH,
                                    child: Column(
                                      children: [
                                        for (var h = _startHour; h < _endHour; h++)
                                          SizedBox(
                                            height: _hourH,
                                            child: Align(
                                              alignment: Alignment.topLeft,
                                              child: Padding(
                                                padding: const EdgeInsets.only(left: 6, top: 4),
                                                child: Text(
                                                  '${h.toString().padLeft(2, '0')}:00',
                                                  style: const TextStyle(color: AppColors.fitGrey, fontSize: 11),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Days header + grid — one horizontal scroll
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 44,
                                        child: Row(
                                          children: [
                                            for (final day in days)
                                              SizedBox(
                                                width: _dayW,
                                                child: Center(
                                                  child: Text(
                                                    '${_kWeekdays[day.weekday - 1]} ${day.day.toString().padLeft(2, '0')}',
                                                    style: TextStyle(
                                                      color: _sameDay(day, todayDate) ? AppColors.accent : Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(height: 1, width: days.length * _dayW, color: const Color(0xFF2A2A2A)),
                                      SizedBox(
                                        width: days.length * _dayW,
                                        height: hourCount * _hourH,
                                        child: Stack(
                                          children: [
                                            for (var h = 0; h <= hourCount; h++)
                                              Positioned(
                                                top: h * _hourH,
                                                left: 0,
                                                right: 0,
                                                child: Container(height: 1, color: const Color(0xFF2A2A2A)),
                                              ),
                                            for (var d = 0; d <= days.length; d++)
                                              Positioned(
                                                left: d * _dayW,
                                                top: 0,
                                                bottom: 0,
                                                child: Container(width: 1, color: const Color(0xFF2A2A2A)),
                                              ),
                                            for (var di = 0; di < days.length; di++)
                                              for (final event in _events.where(
                                                (e) => e.startsAt != null && _sameDay(e.startsAt!, days[di]),
                                              ))
                                                if (event.startsAt!.hour >= _startHour && event.startsAt!.hour < _endHour)
                                                  Positioned(
                                                    left: di * _dayW + 4,
                                                    top: _topFor(event.startsAt!),
                                                    width: _dayW - 8,
                                                    height: _heightFor(event),
                                                    child: GestureDetector(
                                                      onTap: () => _openEvent(event),
                                                      child: Container(
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF2A2A2A),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border(
                                                            left: BorderSide(color: _accentFor(event), width: 3),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '${_shortName(event.name)}\n${event.durationMin > 0 ? '${event.durationMin} мин' : ''}'
                                                              .trim(),
                                                          maxLines: 4,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
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
