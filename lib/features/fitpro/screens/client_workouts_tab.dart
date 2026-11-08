import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/routes/route_names.dart';

const _lime = Color(0xFFC7F137);
const _card = Color(0xFF232323);
const _border = Color(0xFF323232);
const _label = Color(0xFF979797);
const _listBg = Color(0xFF292929);
const _prGreen = Color(0xFF37F184);

String formatWorkoutDuration(int? durationSec) {
  final totalMin = ((durationSec ?? 0) / 60).round();
  if (totalMin <= 0) return '—';
  if (totalMin < 60) return '$totalMin мин';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (m == 0) return '$h ч';
  return '$h ч $m мин';
}

String _muscleIconAsset(List<String> codes) {
  final keys = codes.map((e) => e.toLowerCase().trim()).where((e) => e.isNotEmpty).toList();
  bool has(Iterable<String> any) => keys.any(any.contains);
  if (has(const ['neck', 'traps'])) return 'assets/icons/workouts/muscle-neck.svg';
  if (has(const ['shoulders', 'delts'])) return 'assets/icons/workouts/muscle-shoulders.svg';
  if (has(const ['chest'])) return 'assets/icons/workouts/muscle-chest.svg';
  if (has(const ['back'])) return 'assets/icons/workouts/muscle-back.svg';
  if (has(const ['glutes'])) return 'assets/icons/workouts/muscle-glutes.svg';
  if (has(const ['biceps', 'arms'])) return 'assets/icons/workouts/muscle-biceps.svg';
  if (has(const ['triceps'])) return 'assets/icons/workouts/muscle-triceps.svg';
  if (has(const ['forearms'])) return 'assets/icons/workouts/muscle-forearms.svg';
  return 'assets/icons/workouts/muscle-card.svg';
}

/// Figma «Тренировки» tab — search + history cards.
class ClientWorkoutsTab extends StatefulWidget {
  const ClientWorkoutsTab({super.key});

  @override
  State<ClientWorkoutsTab> createState() => _ClientWorkoutsTabState();
}

class _ClientWorkoutsTabState extends State<ClientWorkoutsTab> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String _sort = 'newest';
  String? _kind;
  bool? _withTrainer;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Timer? _debounce;
  int? _activeSessionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await WorkoutOfflineQueue.I.flush();
      final activeId = await WorkoutOfflineQueue.I.activeSessionId();
      final items = await FitApi.clientSessions(
        force: true,
        sort: _sort,
        kind: _kind,
        withTrainer: _withTrainer,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      if (!mounted) return;
      Map<String, dynamic>? fromApi;
      for (final e in items) {
        if (e['status']?.toString() == 'in_progress') {
          fromApi = e;
          break;
        }
      }
      final resolvedActive = int.tryParse('${fromApi?['id']}') ?? activeId;
      if (resolvedActive != null && resolvedActive > 0) {
        await WorkoutOfflineQueue.I.setActiveSessionId(resolvedActive);
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _activeSessionId = resolvedActive;
        _loading = false;
      });
    } catch (e) {
      final activeId = await WorkoutOfflineQueue.I.activeSessionId();
      if (!mounted) return;
      setState(() {
        _activeSessionId = activeId;
        _loading = false;
      });
      Toast.error(FitApi.messageOf(e));
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  List<Map<String, dynamic>> get _filtered {
    return [
      for (final item in _items)
        if (_inMonth(item)) item,
    ];
  }

  bool _inMonth(Map<String, dynamic> item) {
    final raw = item['finished_at'] ?? item['started_at'] ?? item['created_at'];
    final at = DateHelper.parseLocal(raw?.toString() ?? '') ?? DateTime.tryParse('$raw')?.toLocal();
    if (at == null) return true;
    return at.year == _month.year && at.month == _month.month;
  }

  Future<void> _pickMonth() async {
    final months = <DateTime>{};
    for (final item in _items) {
      final raw = item['finished_at'] ?? item['started_at'] ?? item['created_at'];
      final at = DateHelper.parseLocal(raw?.toString() ?? '') ?? DateTime.tryParse('$raw')?.toLocal();
      if (at != null) months.add(DateTime(at.year, at.month));
    }
    months.add(DateTime(DateTime.now().year, DateTime.now().month));
    final list = months.toList()..sort((a, b) => b.compareTo(a));
    final next = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in list)
              ListTile(
                title: Text(
                  _monthTitle(m),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: m == _month ? const Icon(Icons.check, color: _lime) : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (next != null) setState(() => _month = next);
  }

  Future<void> _openFilters() async {
    String sort = _sort;
    String? kind = _kind;
    bool? withTrainer = _withTrainer;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF232323),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setB) {
            Widget chip(String label, bool on, VoidCallback tap) {
              return GestureDetector(
                onTap: tap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? _lime : const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: on ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text('Фильтр и сортировка', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Сортировка', style: TextStyle(color: _label)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        chip('Сначала новые', sort == 'newest', () => setB(() => sort = 'newest')),
                        chip('Сначала старые', sort == 'oldest', () => setB(() => sort = 'oldest')),
                        chip('Короткие', sort == 'duration_asc', () => setB(() => sort = 'duration_asc')),
                        chip('Длинные', sort == 'duration_desc', () => setB(() => sort = 'duration_desc')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Тип', style: TextStyle(color: _label)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        chip('Все', kind == null, () => setB(() => kind = null)),
                        chip('Силовые', kind == 'strength', () => setB(() => kind = 'strength')),
                        chip('Кардио', kind == 'cardio', () => setB(() => kind = 'cardio')),
                        chip('Растяжка', kind == 'stretching', () => setB(() => kind = 'stretching')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('С тренером', style: TextStyle(color: _label)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        chip('Все', withTrainer == null, () => setB(() => withTrainer = null)),
                        chip('С тренером', withTrainer == true, () => setB(() => withTrainer = true)),
                        chip('Самостоятельно', withTrainer == false, () => setB(() => withTrainer = false)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _sort = sort;
                          _kind = kind;
                          _withTrainer = withTrainer;
                          Navigator.pop(ctx2, true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _lime,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Применить', style: TextStyle(fontWeight: FontWeight.w700)),
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
    if (applied == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      children: [
        if (_activeSessionId != null && _activeSessionId! > 0) ...[
          GestureDetector(
            onTap: () async {
              await context.push(RouteNames.liveSession, extra: _activeSessionId);
              if (mounted) _load();
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1F3A24),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _lime),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill, color: _lime),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Тренировка не завершена — продолжить',
                      style: GoogleFonts.openSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _lime),
                ],
              ),
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF292929)),
                ),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/workouts/search.svg',
                      width: 18,
                      height: 18,
                      colorFilter: const ColorFilter.mode(_label, BlendMode.srcIn),
                      placeholderBuilder: (_) => const Icon(Icons.search, color: _label, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: _onSearchChanged,
                        cursorColor: _lime,
                        style: GoogleFonts.openSans(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Найти тренировку',
                          hintStyle: GoogleFonts.openSans(color: _label, fontSize: 14),
                          isDense: true,
                          filled: false,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SquareIconButton(
              asset: 'assets/icons/workouts/filter.svg',
              fallback: Icons.tune,
              onTap: _openFilters,
            ),
            const SizedBox(width: 8),
            _SquareIconButton(
              asset: 'assets/icons/workouts/sort.svg',
              fallback: Icons.sort,
              onTap: () async {
                setState(() => _sort = _sort == 'newest' ? 'oldest' : 'newest');
                await _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'История тренировок',
                        style: GoogleFonts.openSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickMonth,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(56),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _monthTitle(_month),
                              style: GoogleFonts.openSans(color: Colors.white, fontSize: 13),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator(color: _lime)),
                      )
                    : rows.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text('Пока нет тренировок', style: GoogleFonts.openSans(color: _label)),
                            ),
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < rows.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                _WorkoutHistoryCard(
                                  item: rows[i],
                                  indexLabel: 'Тренировка #${rows.length - i}',
                                  onTap: () {
                                    final id = int.tryParse('${rows[i]['id']}') ?? 0;
                                    if (id > 0) context.push(RouteNames.sessionDetail, extra: id);
                                  },
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

  String _monthTitle(DateTime m) {
    const names = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    return names[m.month - 1];
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.asset, required this.fallback, required this.onTap});

  final String asset;
  final IconData fallback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF292929)),
          ),
          child: SvgPicture.asset(
            asset,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            placeholderBuilder: (_) => Icon(fallback, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _WorkoutHistoryCard extends StatelessWidget {
  const _WorkoutHistoryCard({
    required this.item,
    required this.indexLabel,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final String indexLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muscleCodes = <String>[
      for (final m in (item['focus_muscles'] is List ? item['focus_muscles'] as List : const []))
        '${m ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).toList();
    final muscles = <String>[
      for (final m in muscleCodes) FitLabels.muscle(m),
    ].where((e) => e.isNotEmpty).take(3).toList();
    if (muscles.isEmpty) {
      final kinds = item['kinds'];
      if (kinds is List) {
        for (final k in kinds.take(2)) {
          final label = FitLabels.kind(k?.toString());
          if (label.isNotEmpty) muscles.add(label);
        }
      }
    }
    final when = DateHelper.parseLocal(
          '${item['finished_at'] ?? item['started_at'] ?? item['created_at'] ?? ''}',
        ) ??
        DateTime.tryParse('${item['finished_at'] ?? item['started_at'] ?? ''}');
    final date = when == null ? '—' : DateHelper.formatRuDate(when).replaceAll(' г.', '');
    final duration = formatWorkoutDuration(int.tryParse('${item['duration_sec']}'));
    final sets = item['sets_count'] ?? '—';
    final record = item['personal_record']?.toString();
    final iconAsset = _muscleIconAsset(muscleCodes);

    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SvgPicture.asset(
                      iconAsset,
                      width: 27,
                      height: 27,
                      fit: BoxFit.contain,
                      placeholderBuilder: (_) => const SizedBox(
                        width: 27,
                        height: 27,
                        child: Icon(Icons.accessibility_new, color: _label, size: 22),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            indexLabel,
                            style: GoogleFonts.openSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          if (muscles.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final m in muscles)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _listBg,
                                      borderRadius: BorderRadius.circular(111),
                                      border: Border.all(color: _border, width: 1.1),
                                    ),
                                    child: Text(
                                      m,
                                      style: GoogleFonts.openSans(color: _label, fontSize: 14),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          _MetaRow(parts: ['$date', duration, '$sets подходов']),
                          if (record != null && record.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/workouts/medal-star.svg',
                                  width: 16,
                                  height: 16,
                                  placeholderBuilder: (_) => const Icon(Icons.stars_rounded, color: _prGreen, size: 16),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    record,
                                    style: GoogleFonts.openSans(color: _prGreen, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SvgPicture.asset(
                'assets/icons/workouts/chevron-right.svg',
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                placeholderBuilder: (_) => const Icon(Icons.chevron_right, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        children.add(const SizedBox(width: 4));
        children.add(
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(color: _label, shape: BoxShape.circle),
          ),
        );
        children.add(const SizedBox(width: 4));
      }
      children.add(
        Text(
          parts[i],
          style: GoogleFonts.openSans(color: _label, fontSize: 12),
        ),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
