import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/routes/route_names.dart';

const _kWeekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _kMonthsGen = [
  'Января',
  'Февраля',
  'Марта',
  'Апреля',
  'Мая',
  'Июня',
  'Июля',
  'Августа',
  'Сентября',
  'Октября',
  'Ноября',
  'Декабря',
];
const _kAccents = [Color(0xFFC7F137), Color(0xFFFF8A3D), Color(0xFF5EC8FF)];

/// Figma «Календарь» — day timeline (tab). Separate from «Запланированные тренировки».
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  static const _dayChip = 48.0;
  static const _dayGap = 16.0;

  late DateTime _selected;
  late List<DateTime> _days;
  List<FitCalendarEvent> _events = const [];
  final _dayScroll = ScrollController();
  bool _loading = false;

  bool get _isTrainer => ref.read(fitSessionProvider).user?.role != FitRole.client;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _days = List.generate(42, (i) => _selected.subtract(const Duration(days: 21)).add(Duration(days: i)));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerSelectedDay(jump: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelectedDay(jump: true));
    });
  }

  @override
  void dispose() {
    _dayScroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    final start = DateTime(_selected.year, _selected.month, _selected.day);
    final end = start.add(const Duration(days: 1));
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final events = _isTrainer
          ? await FitApi.trainerCalendar(from: start, to: end, force: force)
          : await FitApi.clientCalendar(from: start, to: end, force: force);
      if (!mounted) return;
      setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _events = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _centerSelectedDay({bool jump = false}) {
    if (!_dayScroll.hasClients) return;
    final index = _days.indexWhere((d) => _sameDay(d, _selected));
    if (index < 0) return;
    final viewport = _dayScroll.position.viewportDimension;
    final target = (index * (_dayChip + _dayGap)) - (viewport / 2) + (_dayChip / 2);
    final offset = target.clamp(0.0, _dayScroll.position.maxScrollExtent);
    if (jump) {
      _dayScroll.jumpTo(offset);
    } else {
      _dayScroll.animateTo(offset, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Color _accentFor(FitCalendarEvent e) => _kAccents[e.id % _kAccents.length];

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
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
    setState(() {
      _selected = DateTime(picked.year, picked.month, picked.day);
      _days = List.generate(42, (i) => _selected.subtract(const Duration(days: 21)).add(Duration(days: i)));
    });
    await _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelectedDay(jump: true));
  }

  Future<void> _openAdd({TimeOfDay? time}) async {
    if (!_isTrainer) return;
    final result = await context.push<Object?>(
      RouteNames.addCalendarEvent,
      extra: {
        'date': _selected,
        if (time != null) 'time': time,
      },
    );
    if (!mounted) return;
    if (result is DateTime && !_sameDay(result, _selected)) {
      setState(() {
        _selected = DateTime(result.year, result.month, result.day);
        _days = List.generate(42, (i) => _selected.subtract(const Duration(days: 21)).add(Duration(days: i)));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelectedDay(jump: true));
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
              const SizedBox(height: 6),
              Text('${event.tags.join(' · ')} · ${event.place}', style: const TextStyle(color: AppColors.fitGrey)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = [..._events]..sort((a, b) => (a.startsAt ?? DateTime(0)).compareTo(b.startsAt ?? DateTime(0)));

    return Scaffold(
      backgroundColor: AppColors.fitBg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              FitPageTitle(
                title: 'Календарь',
                leading: SizedBox(
                  width: 88,
                  child: Text(
                    '${_selected.day} ${_kMonthsGen[_selected.month - 1]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                trailing: IconButton(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined, color: Colors.white),
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  controller: _dayScroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: _days.length,
                  separatorBuilder: (_, _) => const SizedBox(width: _dayGap),
                  itemBuilder: (context, index) {
                    final day = _days[index];
                    final active = _sameDay(day, _selected);
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selected = day);
                        _load();
                        _centerSelectedDay();
                      },
                      child: Container(
                        width: _dayChip,
                        height: _dayChip,
                        decoration: BoxDecoration(
                          color: active ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _kWeekdays[day.weekday - 1],
                              style: TextStyle(
                                color: active ? Colors.black54 : AppColors.fitGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                color: active ? Colors.black : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
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
                      : _DayTimeline(
                          selected: _selected,
                          events: dayEvents,
                          isTrainer: _isTrainer,
                          accentFor: _accentFor,
                          onAdd: _openAdd,
                          onEvent: _openEvent,
                          onChanged: _load,
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

class _DayTimeline extends StatelessWidget {
  const _DayTimeline({
    required this.selected,
    required this.events,
    required this.isTrainer,
    required this.accentFor,
    required this.onAdd,
    required this.onEvent,
    required this.onChanged,
  });

  final DateTime selected;
  final List<FitCalendarEvent> events;
  final bool isTrainer;
  final Color Function(FitCalendarEvent) accentFor;
  final void Function({TimeOfDay? time}) onAdd;
  final void Function(FitCalendarEvent) onEvent;
  final Future<void> Function() onChanged;

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool _hourCovered(int hour) {
    final slot = DateTime(selected.year, selected.month, selected.day, hour);
    for (final e in events) {
      final s = e.startsAt;
      if (s == null) continue;
      final end = e.endsAt ?? s.add(Duration(minutes: e.durationMin <= 0 ? 60 : e.durationMin));
      // Covered if hour starts strictly inside the event (not at the start).
      if (slot.isAfter(s) && slot.isBefore(end)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Client empty → polished empty state. Trainer empty → Figma timeline with +.
    if (events.isEmpty && !isTrainer) {
      return const _DayEmpty();
    }

    final hours = <int>{for (var h = 9; h <= 21; h++) h};
    for (final e in events) {
      final s = e.startsAt;
      if (s != null) {
        hours.add(s.hour);
        final end = e.endsAt ?? s.add(Duration(minutes: e.durationMin <= 0 ? 60 : e.durationMin));
        hours.add(end.hour);
      }
    }
    final sortedHours = hours.toList()..sort();

    final rows = <Widget>[];
    for (final hour in sortedHours) {
      final starting = events.where((e) => e.startsAt?.hour == hour).toList();
      if (starting.isNotEmpty) {
        for (final event in starting) {
          final accent = accentFor(event);
          final start = event.startsAt!;
          final end = event.endsAt ?? start.add(Duration(minutes: event.durationMin <= 0 ? 60 : event.durationMin));
          final mins = end.difference(start).inMinutes.clamp(30, 300);
          // Visual span: 60 min ≈ 108px, 90 min ≈ 162px (20:00→21:30).
          // Min 128 so name + tags + duration never overflow.
          final cardH = (mins * 1.8).clamp(128.0, 280.0);
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: cardH),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 52,
                        child: _TimeRangeGutter(start: _hhmm(start), end: _hhmm(end)),
                      ),
                      Expanded(
                        child: _TrainerEventCard(
                          event: event,
                          accent: accent,
                          showMenu: isTrainer,
                          onTap: () => onEvent(event),
                          onChanged: onChanged,
                        onEdit: () {
                          context
                              .push('${RouteNames.addCalendarEvent}?eventId=${event.id}', extra: {'eventId': event.id})
                              .then((_) => onChanged());
                        },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        continue;
      }
      if (_hourCovered(hour)) continue;
      if (!isTrainer) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(child: Container(height: 1, color: const Color(0xFF2A2A2A))),
              ],
            ),
          ),
        );
        continue;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(child: _EmptySlot(onAdd: () => onAdd(time: TimeOfDay(hour: hour, minute: 0)))),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 120),
        children: rows,
      ),
    );
  }
}

class _TimeRangeGutter extends StatelessWidget {
  const _TimeRangeGutter({required this.start, required this.end});

  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(start, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CustomPaint(
              painter: _DashedLinePainter(color: const Color(0xFF5A5A5A)),
              child: const SizedBox(width: 2, height: double.infinity),
            ),
          ),
        ),
        Text(end, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 4.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      final y2 = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(x, y), Offset(x, y2), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

class _DayEmpty extends StatelessWidget {
  const _DayEmpty();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined, color: AppColors.accent, size: 36),
            SizedBox(height: 14),
            Text(
              'На этот день тренировок нет',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Выберите другой день или дождитесь\nназначения от тренера',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.fitGrey, fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(height: 1, color: const Color(0xFF2F2F2F)),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 1.5),
              ),
              child: const Icon(Icons.add, size: 18, color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerEventCard extends StatelessWidget {
  const _TrainerEventCard({
    required this.event,
    required this.accent,
    required this.onTap,
    required this.onChanged,
    required this.onEdit,
    this.showMenu = true,
  });

  final FitCalendarEvent event;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final Future<void> Function() onChanged;
  final bool showMenu;

  String _tagAsset(String tag) {
    final t = tag.toLowerCase();
    if (t.contains('бег') || t.contains('run') || t.contains('кардио') || t.contains('cardio')) {
      return 'assets/icons/quick-action/cardio.svg';
    }
    if (t.contains('ног') || t.contains('leg') || t.contains('растяж') || t.contains('пресс')) {
      return 'assets/icons/quick-action/person-bold.svg';
    }
    if (t.contains('сил') || t.contains('strength') || t.contains('груд') || t.contains('спин') || t.contains('рук')) {
      return 'assets/icons/quick-action/dumbell.svg';
    }
    return 'assets/icons/quick-action/dumbell.svg';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Удалить тренировку?', style: TextStyle(color: Colors.white)),
        content: const Text('Это действие нельзя отменить.', style: TextStyle(color: AppColors.fitGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FitApi.deleteCalendarEvent(event.id);
      Toast.success('Удалено');
      await onChanged();
    } catch (e) {
      Toast.error(FitApi.messageOf(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = event.tags.take(2).toList();
    final extra = event.tags.length - tags.length;
    final duration = event.durationMin > 0
        ? event.durationMin
        : (event.startsAt != null && event.endsAt != null ? event.endsAt!.difference(event.startsAt!).inMinutes : 0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: accent, width: 3.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          if (showMenu)
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.more_horiz, color: Colors.white54, size: 20),
                              color: const Color(0xFF242424),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: Color(0xFF3A3A3A)),
                              ),
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  onEdit();
                                  return;
                                }
                                if (value == 'delete') {
                                  await _confirmDelete(context);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                                      SizedBox(width: 10),
                                      Text('Изменить', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(height: 1),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: Color(0xFFFF6B6B), size: 18),
                                      SizedBox(width: 10),
                                      Text('Удалить', style: TextStyle(color: Color(0xFFFF6B6B))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A3A3A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    _tagAsset(tag),
                                    width: 12,
                                    height: 12,
                                    colorFilter: const ColorFilter.mode(Colors.white70, BlendMode.srcIn),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(tag, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          if (extra > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A3A3A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('+$extra', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ),
                        ],
                      ),
                      if (duration > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 14, color: accent),
                            const SizedBox(width: 4),
                            Text(
                              '$duration мин',
                              style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
