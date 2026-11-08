import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/routes/route_names.dart';

// Figma «Добавить тренировки» / тип тренировки sheet
// startNow (hub «Новая тренировка») = start live session now, no scheduling fields.
// Otherwise (calendar) = schedule a calendar event; with eventId = edit it.

const _kKinds = <({String code, String label})>[
  (code: 'strength', label: 'Силовая тренировка'),
  (code: 'functional', label: 'Функциональный тренинг'),
  (code: 'cardio', label: 'Кардио'),
  (code: 'stretching', label: 'Растяжка'),
  (code: 'circuit', label: 'Круговая тренировка'),
  (code: 'interval', label: 'Интервальная тренировка'),
  (code: 'rehab', label: 'Реабилитация'),
  (code: 'endurance', label: 'Выносливость'),
];

const _kReminders = <({String code, String label})>[
  (code: 'none', label: 'Не напоминать'),
  (code: '1h', label: 'За 1 час'),
  (code: '3h', label: 'За 3 часа'),
];

const _kMuscles = <({String code, String label})>[
  (code: 'chest', label: 'Грудь'),
  (code: 'back', label: 'Спина'),
  (code: 'legs', label: 'Ноги'),
  (code: 'shoulders', label: 'Плечи'),
  (code: 'arms', label: 'Руки'),
  (code: 'abs', label: 'Пресс'),
  (code: 'glutes', label: 'Ягодицы'),
  (code: 'traps', label: 'Трапеция'),
  (code: 'neck', label: 'Шея'),
  (code: 'full_body', label: 'Всё тело'),
];

class AddCalendarEventPage extends StatefulWidget {
  const AddCalendarEventPage({super.key, this.initialDate, this.initialTime, this.eventId, this.startNow = false});

  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final int? eventId;
  final bool startNow;

  @override
  State<AddCalendarEventPage> createState() => _AddCalendarEventPageState();
}

class _AddCalendarEventPageState extends State<AddCalendarEventPage> {
  final _noteCtrl = TextEditingController();

  List<FitClient> _clients = const [];
  int? _selectedClientUserId;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final Set<String> _kinds = {};
  final Set<String> _muscles = {};
  String _format = 'gym'; // gym | online
  bool _repeatWeekly = false;
  String _reminder = '1h';
  bool _loading = false;
  bool _saving = false;

  bool get _isEdit => (widget.eventId ?? 0) > 0;
  bool get _startNow => widget.startNow && !_isEdit;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = widget.initialDate ?? now;
    _date = DateTime(seed.year, seed.month, seed.day);
    _startTime = widget.initialTime ?? TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    _endTime = TimeOfDay(hour: (_startTime.hour + 1) % 24, minute: _startTime.minute);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final clients = await FitApi.trainerClients();
      if (!mounted) return;
      setState(() => _clients = clients);
      if (_isEdit) await _hydrateEvent(widget.eventId!);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _asStringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    if (value is String && value.isNotEmpty) {
      final trimmed = value.replaceAll('{', '').replaceAll('}', '');
      return trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  Future<void> _hydrateEvent(int id) async {
    final event = await FitApi.calendarEvent(id);
    if (!mounted) return;
    final start = DateTime.tryParse('${event['starts_at']}')?.toLocal();
    final end = DateTime.tryParse('${event['ends_at']}')?.toLocal();
    final clientId = int.tryParse('${event['client_id']}') ?? 0;
    final kinds = _asStringList(event['kinds']);
    final muscles = _asStringList(event['focus_muscles']);
    final format = event['format']?.toString() ?? '';
    final reminder = event['reminder']?.toString() ?? '1h';
    final note = event['note']?.toString() ?? '';

    // Match client by users.id (client_id) — FitClient.userId.
    int? selected;
    if (clientId > 0) {
      for (final c in _clients) {
        final uid = c.userId > 0 ? c.userId : c.id;
        if (uid == clientId || c.id == clientId) {
          selected = uid;
          break;
        }
      }
      selected ??= clientId;
    }

    setState(() {
      if (start != null) {
        _date = DateTime(start.year, start.month, start.day);
        _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
      }
      if (end != null) {
        _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
      } else if (start != null) {
        _endTime = TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute);
      }
      _selectedClientUserId = selected;
      _format = format.isNotEmpty ? format : 'gym';
      _reminder = reminder.isNotEmpty ? reminder : '1h';
      _repeatWeekly = event['repeat_weekly'] == true;
      _noteCtrl.text = note == 'null' ? '' : note;
      _kinds
        ..clear()
        ..addAll(kinds.where((k) => _kKinds.any((x) => x.code == k)));
      // Keep unknown kind codes too (e.g. ordinary/trial).
      for (final k in kinds) {
        if (!_kinds.contains(k)) _kinds.add(k);
      }
      _muscles
        ..clear()
        ..addAll(muscles);
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  FitClient? get _selectedClient {
    final selected = _selectedClientUserId;
    if (selected == null) return null;
    for (final c in _clients) {
      final uid = c.userId > 0 ? c.userId : c.id;
      if (uid == selected || c.id == selected) return c;
    }
    return null;
  }

  String get _kindsLabel {
    if (_kinds.isEmpty) return 'Выберите тип';
    final labels = _kKinds.where((k) => _kinds.contains(k.code)).map((k) => k.label).toList();
    if (labels.length <= 2) return labels.join(', ');
    return '${labels.take(2).join(', ')}, +${labels.length - 2}';
  }

  String get _musclesLabel {
    if (_muscles.isEmpty) return 'Выберите мышцы';
    final labels = _kMuscles.where((k) => _muscles.contains(k.code)).map((k) => k.label).toList();
    if (labels.length <= 2) return labels.join(', ');
    return '${labels.take(2).join(', ')}, +${labels.length - 2}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
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
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, onPrimary: Colors.black, surface: Color(0xFF232323)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _endTime = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, onPrimary: Colors.black, surface: Color(0xFF232323)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<void> _pickClient() async {
    if (_clients.isEmpty) {
      Toast.info('Клиентов пока нет');
      return;
    }
    final searchCtrl = TextEditingController();
    final picked = await showBlurredModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setB) {
            final q = searchCtrl.text.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _clients
                : _clients.where((c) {
                    final name = '${c.name} ${c.surname}'.trim().toLowerCase();
                    return name.contains(q);
                  }).toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, sc) => Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 72, height: 5, decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100))),
                  const SizedBox(height: 16),
                  const Text('Выбор клиента', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setB(() {}),
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        hintText: 'Поиск клиента',
                        hintStyle: const TextStyle(color: AppColors.fitGrey),
                        prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey),
                        filled: true,
                        fillColor: const Color(0xFF232323),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Никого не найдено', style: TextStyle(color: AppColors.fitGrey)))
                        : ListView.separated(
                            controller: sc,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(color: Color(0xFF323232), height: 1),
                            itemBuilder: (_, i) {
                              final c = filtered[i];
                              final uid = c.userId > 0 ? c.userId : c.id;
                              final selected = uid == _selectedClientUserId;
                              final name = '${c.name} ${c.surname}'.trim();
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF3A3A3A),
                                  child: Text(c.initials, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                                title: Text(name, style: TextStyle(color: selected ? AppColors.accent : Colors.white)),
                                trailing: selected
                                    ? const Icon(Icons.radio_button_checked, color: AppColors.accent)
                                    : const Icon(Icons.radio_button_off, color: Color(0xFF6A6A6A)),
                                onTap: () => Navigator.pop(ctx, uid),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
    if (picked != null) setState(() => _selectedClientUserId = picked);
  }

  Future<void> _pickKinds() async {
    final draft = Set<String>.from(_kinds);
    final applied = await showBlurredModalBottomSheet<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setB) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 72, height: 5, decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100))),
                    const SizedBox(height: 16),
                    const Text('Тип тренировки', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _kKinds.length,
                        separatorBuilder: (_, _) => const Divider(color: Color(0xFF323232), height: 1),
                        itemBuilder: (_, i) {
                          final k = _kKinds[i];
                          final on = draft.contains(k.code);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: on ? AppColors.accent : const Color(0xFF6A6A6A),
                            ),
                            title: Text(k.label, style: const TextStyle(color: Colors.white, fontSize: 15)),
                            onTap: () => setB(() => on ? draft.remove(k.code) : draft.add(k.code)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setB(draft.clear),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: Color(0xFF323232)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Сбросить всё', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx2, Set<String>.from(draft)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text('Применить (${draft.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
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
      },
    );
    if (applied != null) {
      setState(() {
        _kinds
          ..clear()
          ..addAll(applied);
      });
    }
  }

  Future<void> _pickMuscles() async {
    final draft = Set<String>.from(_muscles);
    final applied = await showBlurredModalBottomSheet<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setB) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 72, height: 5, decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100))),
                    const SizedBox(height: 16),
                    const Text('Фокус мышц', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _kMuscles.length,
                        separatorBuilder: (_, _) => const Divider(color: Color(0xFF323232), height: 1),
                        itemBuilder: (_, i) {
                          final k = _kMuscles[i];
                          final on = draft.contains(k.code);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: on ? AppColors.accent : const Color(0xFF6A6A6A),
                            ),
                            title: Text(k.label, style: const TextStyle(color: Colors.white, fontSize: 15)),
                            onTap: () => setB(() => on ? draft.remove(k.code) : draft.add(k.code)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx2, Set<String>.from(draft)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Применить (${draft.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (applied != null) {
      setState(() {
        _muscles
          ..clear()
          ..addAll(applied);
      });
    }
  }

  String _dateLabel() {
    final day = _date.day.toString().padLeft(2, '0');
    final month = _date.month.toString().padLeft(2, '0');
    return '$day.$month.${_date.year}';
  }

  String _timeLabel(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  DateTime _combine(DateTime date, TimeOfDay time) => DateTime(date.year, date.month, date.day, time.hour, time.minute);

  String _toIsoLocal(DateTime dt) {
    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final mins = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final local = DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    return '${local.toIso8601String()}$sign$hours:$mins';
  }

  bool get _valid => _selectedClientUserId != null && !_saving;

  /// Create (schedule) or update a calendar event.
  Future<void> _saveEvent() async {
    if (_selectedClientUserId == null) {
      Toast.info('Выберите клиента');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final startsAt = _combine(_date, _startTime);
      var endsAt = _combine(_date, _endTime);
      if (!endsAt.isAfter(startsAt)) {
        endsAt = startsAt.add(const Duration(hours: 1));
      }

      final body = <String, dynamic>{
        'client_id': _selectedClientUserId,
        'starts_at': _toIsoLocal(startsAt),
        'ends_at': _toIsoLocal(endsAt),
        'format': _format,
        'kinds': _kinds.toList(),
        'focus_muscles': _muscles.toList(),
        'reminder': _reminder,
        'repeat_weekly': _repeatWeekly,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      };

      if (_isEdit) {
        await FitApi.updateCalendarEvent(widget.eventId!, body);
      } else {
        await FitApi.createCalendarEvent(body);
      }
      if (!mounted) return;
      Toast.success(_isEdit ? 'Тренировка обновлена' : 'Тренировка запланирована на ${_dateLabel()} ${_timeLabel(_startTime)}');
      context.pop(_date);
    } catch (e) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Create calendar visit for "now" (metadata) + open active live session.
  Future<void> _startWorkout() async {
    if (_selectedClientUserId == null) {
      Toast.info('Выберите клиента');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final kinds = _kinds.isEmpty ? <String>['strength'] : _kinds.toList();
      final now = DateTime.now();
      final ends = now.add(const Duration(hours: 1));
      final note = _noteCtrl.text.trim();

      final event = await FitApi.createCalendarEvent({
        'client_id': _selectedClientUserId,
        'starts_at': _toIsoLocal(now),
        'ends_at': _toIsoLocal(ends),
        'format': _format,
        'kinds': kinds,
        'focus_muscles': _muscles.toList(),
        'reminder': 'none',
        'repeat_weekly': false,
        if (note.isNotEmpty) 'note': note,
      });
      final eventId = int.tryParse('${event['id']}') ?? 0;

      int sessionId = 0;
      if (eventId > 0) {
        try {
          final session = await FitApi.startSessionFromCalendar(eventId);
          sessionId = int.tryParse('${session['id']}') ?? 0;
        } catch (_) {
          sessionId = 0;
        }
      }
      if (sessionId <= 0) {
        final started = await FitApi.startOrResumeSession(
          clientIds: [_selectedClientUserId!],
          kinds: kinds,
          source: 'new',
        );
        sessionId = started.sessionId;
        if (started.resumed) {
          Toast.info('Открыта незавершённая тренировка');
        }
      }
      if (sessionId <= 0) {
        throw Exception('Не удалось создать тренировку');
      }
      if (!mounted) return;
      context.pushReplacement(RouteNames.liveSession, extra: sessionId);
    } catch (e) {
      if (!mounted) return;
      final existing = FitApi.activeSessionIdFromError(e);
      if (existing != null && existing > 0) {
        Toast.info('Есть активная тренировка — продолжаем');
        context.pushReplacement(RouteNames.liveSession, extra: existing);
        return;
      }
      Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = _selectedClient;
    final clientName = client == null ? 'Выберите клиента' : '${client.name} ${client.surname}'.trim();

    return FitScaffold(
      child: Column(
        children: [
          HubBackTitle(
            title: _isEdit
                ? 'Изменить тренировку'
                : _startNow
                    ? 'Новая тренировка'
                    : 'Запланировать тренировку',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _FieldLabel(text: 'Клиент', required: true),
                const SizedBox(height: 4),
                _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                      )
                    : _SelectRow(
                        onTap: _pickClient,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF3A3A3A),
                              child: Text(
                                client?.initials ?? '?',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                clientName,
                                style: TextStyle(
                                  color: client == null ? AppColors.fitGrey : Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            SvgPicture.asset(
                              'assets/icons/trainer/arrow-down.svg',
                              width: 18,
                              height: 18,
                              colorFilter: const ColorFilter.mode(AppColors.fitGrey, BlendMode.srcIn),
                            ),
                          ],
                        ),
                      ),
                if (!_startNow) ...[
                  const SizedBox(height: 16),
                  _FieldLabel(text: 'Дата', required: true),
                  const SizedBox(height: 4),
                  _SelectRow(
                    onTap: _pickDate,
                    child: Row(
                      children: [
                        Expanded(child: Text(_dateLabel(), style: const TextStyle(color: Colors.white, fontSize: 14))),
                        const Icon(Icons.calendar_today_outlined, color: AppColors.fitGrey, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel(text: 'Время', required: true),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Начало', style: TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                            const SizedBox(height: 4),
                            _SelectRow(
                              onTap: _pickStartTime,
                              child: Row(
                                children: [
                                  Expanded(child: Text(_timeLabel(_startTime), style: const TextStyle(color: Colors.white, fontSize: 14))),
                                  const Icon(Icons.access_time, color: AppColors.fitGrey, size: 18),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Окончание', style: TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                            const SizedBox(height: 4),
                            _SelectRow(
                              onTap: _pickEndTime,
                              child: Row(
                                children: [
                                  Expanded(child: Text(_timeLabel(_endTime), style: const TextStyle(color: Colors.white, fontSize: 14))),
                                  const Icon(Icons.access_time, color: AppColors.fitGrey, size: 18),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const _FieldLabel(text: 'Тип тренировки'),
                const SizedBox(height: 4),
                _SelectRow(
                  onTap: _pickKinds,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _kindsLabel,
                          style: TextStyle(color: _kinds.isEmpty ? AppColors.fitGrey : Colors.white, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/icons/trainer/arrow-down.svg',
                        width: 18,
                        height: 18,
                        colorFilter: const ColorFilter.mode(AppColors.fitGrey, BlendMode.srcIn),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _FieldLabel(text: 'Фокус мышц'),
                const SizedBox(height: 4),
                _SelectRow(
                  onTap: _pickMuscles,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _musclesLabel,
                          style: TextStyle(color: _muscles.isEmpty ? AppColors.fitGrey : Colors.white, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/icons/trainer/arrow-down.svg',
                        width: 18,
                        height: 18,
                        colorFilter: const ColorFilter.mode(AppColors.fitGrey, BlendMode.srcIn),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _FieldLabel(text: 'Формат тренировки'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF292929)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Segment(
                          label: 'В зале',
                          selected: _format == 'gym',
                          onTap: () => setState(() => _format = 'gym'),
                        ),
                      ),
                      Expanded(
                        child: _Segment(
                          label: 'Онлайн',
                          selected: _format == 'online',
                          onTap: () => setState(() => _format = 'online'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_startNow) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232323),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF323232)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Повторять еженедельно', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                              SizedBox(height: 4),
                              Text(
                                'Тренировка будет добавляться каждую неделю',
                                style: TextStyle(color: AppColors.fitGrey, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _repeatWeekly,
                          activeThumbColor: Colors.white,
                          activeTrackColor: AppColors.accent,
                          onChanged: (v) => setState(() => _repeatWeekly = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel(text: 'Напоминание'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in _kReminders)
                        GestureDetector(
                          onTap: () => setState(() => _reminder = r.code),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _reminder == r.code ? AppColors.accent : const Color(0xFF232323),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _reminder == r.code ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF323232),
                              ),
                            ),
                            child: Text(
                              r.label,
                              style: TextStyle(
                                color: _reminder == r.code ? Colors.black : (_reminder == 'none' && r.code == 'none' ? AppColors.fitGrey : Colors.white),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Заметки', style: TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF323232)),
                  ),
                  child: TextField(
                    controller: _noteCtrl,
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: AppColors.accent,
                    decoration: const InputDecoration(
                      hintText: 'Сделать акцент на плечи и трапеции…',
                      hintStyle: TextStyle(color: AppColors.fitGrey, fontSize: 14),
                      contentPadding: EdgeInsets.all(16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: FitAccentButton(
              title: _isEdit
                  ? 'Сохранить изменения'
                  : _startNow
                      ? 'Начать тренировку'
                      : 'Запланировать тренировку',
              loading: _saving,
              onPressed: _valid ? (_startNow ? _startWorkout : _saveEvent) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$text ',
        style: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
        children: [
          if (required) const TextSpan(text: '*', style: TextStyle(color: Color(0xFFFD6565))),
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF323232)),
        ),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF232323) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF292929) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : Colors.white,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
