import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/widgets/contact_actions.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/routes/route_names.dart';

/// Figma «Запланированные тренировки — Тренировка» / Details training.
class CalendarEventDetailPage extends StatefulWidget {
  const CalendarEventDetailPage({super.key, required this.eventId});

  final int eventId;

  @override
  State<CalendarEventDetailPage> createState() => _CalendarEventDetailPageState();
}

class _CalendarEventDetailPageState extends State<CalendarEventDetailPage> {
  Map<String, dynamic> _event = const {};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final event = await FitApi.calendarEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(e));
    }
  }

  String _name() {
    final full = '${_event['first_name'] ?? ''} ${_event['last_name'] ?? ''}'.trim();
    return full.isEmpty ? 'Без клиента' : full;
  }

  String _initials() {
    final a = (_event['first_name']?.toString() ?? '').isNotEmpty ? _event['first_name'].toString()[0] : '';
    final b = (_event['last_name']?.toString() ?? '').isNotEmpty ? _event['last_name'].toString()[0] : '';
    final v = '$a$b'.toUpperCase();
    return v.isEmpty ? '?' : v;
  }

  DateTime? get _starts => DateTime.tryParse('${_event['starts_at']}')?.toLocal();
  DateTime? get _ends => DateTime.tryParse('${_event['ends_at']}')?.toLocal();

  String _dateLine() {
    final d = _starts;
    if (d == null) return '—';
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    const weekdays = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
    return '${d.day} ${months[d.month - 1]}, ${weekdays[d.weekday - 1]}';
  }

  String _timeLine() {
    final s = _starts;
    final e = _ends;
    if (s == null) return '—';
    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final mins = e == null ? (int.tryParse('${_event['duration_min']}') ?? 60) : e.difference(s).inMinutes;
    return e == null ? '${hhmm(s)} ($mins мин)' : '${hhmm(s)} – ${hhmm(e)} ($mins мин)';
  }

  String _formatLine() {
    return switch (_event['format']?.toString()) {
      'online' => 'Онлайн',
      'home' => 'Дом',
      'visit' => 'Выезд',
      'hybrid' => 'Гибрид',
      _ => 'В зале',
    };
  }

  (String label, Color bg, Color fg) _statusChip() {
    return switch (_event['status']?.toString()) {
      'completed' => ('Завершена', const Color(0xFFC7F137), Colors.black),
      'in_progress' => ('В процессе', const Color(0xFFFEB94B), Colors.black),
      'cancelled' => ('Отменена', const Color(0xFFFD6565), Colors.black),
      'no_show' => ('Неявка', const Color(0xFFFD6565), Colors.black),
      _ => ('Предстоящая', const Color(0xFF37D2F1), Colors.black),
    };
  }

  List<String> get _muscles {
    final raw = _event['focus_muscles'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  List<String> get _kinds {
    final raw = _event['kinds'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty && e != 'ordinary' && e != 'trial').toList();
  }

  String _clientSince() {
    final d = DateTime.tryParse('${_event['client_since']}')?.toLocal();
    if (d == null) return '';
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return 'Клиент с ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  bool get _canStart {
    final st = _event['status']?.toString();
    return st != 'cancelled' && st != 'completed' && st != 'no_show';
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Отменить тренировку?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить', style: TextStyle(color: Color(0xFFFD6565))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await FitApi.cancelCalendarEvent(widget.eventId);
      if (!mounted) return;
      Toast.success('Тренировка отменена');
      await _load();
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final session = await FitApi.startSessionFromCalendar(widget.eventId);
      final sessionId = int.tryParse('${session['id']}') ?? 0;
      if (!mounted) return;
      if (sessionId > 0) {
        setState(() => _busy = false);
        await context.push(RouteNames.liveSession, extra: sessionId);
        if (mounted) await _load();
      } else {
        Toast.success('Сессия создана');
      }
    } catch (e) {
      if (!mounted) return;
      final existing = FitApi.activeSessionIdFromError(e);
      if (existing != null && existing > 0) {
        Toast.info('Есть активная тренировка — продолжаем');
        context.push(RouteNames.liveSession, extra: existing);
      } else {
        Toast.error(FitApi.messageOf(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    await context.push(
      '${RouteNames.addCalendarEvent}?eventId=${widget.eventId}',
      extra: {'eventId': widget.eventId},
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusChip();
    final note = _event['note']?.toString() ?? '';
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                HubBackTitle(
                  title: 'Тренировка',
                  trailing: IconButton(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.more_horiz, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(bottom: 24 + bottomInset),
                    children: [
                      HubCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(0xFF3A3A3A),
                              backgroundImage: (_event['avatar_url']?.toString().isNotEmpty ?? false)
                                  ? NetworkImage(_event['avatar_url'].toString())
                                  : null,
                              child: (_event['avatar_url']?.toString().isNotEmpty ?? false)
                                  ? null
                                  : Text(_initials(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_name(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  if (_clientSince().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(_clientSince(), style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                                  ],
                                ],
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
                            const Text('Связаться', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            ContactActionsRow(
                              phone: _event['phone']?.toString() ?? '',
                              whatsapp: _event['whatsapp']?.toString(),
                              telegram: _event['telegram']?.toString(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      HubCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Детали тренировки', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 12),
                            _DetailRow(icon: Icons.calendar_today_outlined, text: _dateLine()),
                            _DetailRow(icon: Icons.access_time, text: _timeLine()),
                            _DetailRow(icon: Icons.place_outlined, text: _formatLine()),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.hourglass_empty, color: AppColors.fitGrey, size: 18),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: status.$2, borderRadius: BorderRadius.circular(10)),
                                    child: Text(status.$1, style: TextStyle(color: status.$3, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_kinds.isNotEmpty || _muscles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        HubCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('План тренировки', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 10),
                              if (_kinds.isNotEmpty)
                                Text(
                                  _kinds.map(_kindRu).join(', '),
                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              if (_muscles.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final m in _muscles)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1C1C1C),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFF323232)),
                                        ),
                                        child: Text(_muscleRu(m), style: const TextStyle(color: Colors.white, fontSize: 13)),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        HubCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Заметки', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 8),
                              Text(note, style: const TextStyle(color: AppColors.fitGrey, height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_canStart)
                  Padding(
                    padding: EdgeInsets.fromLTRB(0, 8, 0, 16 + bottomInset),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _busy ? null : _cancel,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFD6565),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _busy ? null : _start,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _busy
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Text('Начать тренировку', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.fitGrey, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14))),
        ],
      ),
    );
  }
}

String _kindRu(String code) {
  return switch (code) {
    'strength' => 'Силовая тренировка',
    'cardio' => 'Кардио',
    'functional' => 'Функциональный тренинг',
    'stretching' || 'stretch' => 'Растяжка',
    'circuit' => 'Круговая',
    'interval' || 'hiit' => 'Интервальная',
    'rehab' => 'Реабилитация',
    'endurance' => 'Выносливость',
    _ => code,
  };
}

String _muscleRu(String code) {
  return switch (code) {
    'chest' => 'Грудь',
    'back' => 'Спина',
    'legs' => 'Ноги',
    'shoulders' => 'Плечи',
    'arms' || 'biceps' => 'Руки',
    'abs' || 'press' => 'Пресс',
    'glutes' => 'Ягодицы',
    'traps' => 'Трапеция',
    'neck' => 'Шея',
    'full_body' => 'Всё тело',
    _ => code,
  };
}
