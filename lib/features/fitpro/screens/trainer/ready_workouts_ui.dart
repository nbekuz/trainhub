import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/screens/trainer/edit_program_day_page.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/routes/route_names.dart';

// ─────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────
String _levelLabel(String raw) => switch (raw.trim().toLowerCase()) {
      'beginner' => 'Новичок',
      'intermediate' => 'Средний',
      'advanced' => 'Продвинутый',
      _ => raw,
    };

String _goalLabel(String raw) {
  final code = raw.trim().toLowerCase();
  return switch (code) {
    'lose_weight' || 'weight_loss' || 'fat_loss' => 'Похудение',
    'gain_muscle' || 'muscle_gain' || 'mass' || 'hypertrophy' => 'Нарастить мышцы',
    'shape' || 'maintain' || 'maintenance' => 'Поддержание формы',
    'strength' => 'Развитие силы',
    'relief' || 'definition' || 'toning' => 'Рельеф',
    'flexibility' || 'mobility' => 'Гибкость',
    'rehab' || 'rehabilitation' || 'recovery' => 'Реабилитация',
    'endurance' || 'stamina' || 'cardio' => 'Выносливость',
    _ => raw.replaceAll(RegExp(r'[_\-]+'), ' '),
  };
}

String _equipmentPlaceLabel(List<String> codes) {
  final lower = codes.map((e) => e.toLowerCase()).toList();
  if (lower.any((e) => e.contains('gym') || e.contains('зал') || e == 'machine')) {
    return 'Тренажерный зал';
  }
  if (lower.any((e) => e.contains('home') || e.contains('дом'))) return 'Дома';
  if (lower.any((e) => e.contains('body') || e.contains('без'))) return 'Без инвентаря';
  if (codes.isEmpty) return 'С оборудованием';
  return 'С оборудованием';
}

String _setsRepsLabel(Map<String, dynamic> item) {
  final sets = item['sets'];
  final rMin = item['reps_min'];
  final rMax = item['reps_max'];
  final parts = <String>[];
  if (sets != null) {
    final n = int.tryParse('$sets') ?? 0;
    if (n == 1) {
      parts.add('1 подход');
    } else if (n > 1) {
      parts.add('$n подхода');
    }
  }
  if (rMin != null && rMax != null) {
    parts.add('$rMin-$rMax повторений');
  } else if (rMin != null) {
    parts.add('$rMin повторений');
  } else if (rMax != null) {
    parts.add('$rMax повторений');
  }
  return parts.join(' · ');
}

/// Cover comes from trainer upload / API media — no bundled PNGs.
Widget _programCover(String? url, {BoxFit fit = BoxFit.cover}) {
  if (url == null || url.isEmpty) return const _CoverPlaceholder();
  return Image.network(
    url,
    fit: fit,
    errorBuilder: (_, _, _) => const _CoverPlaceholder(),
  );
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF292929),
      child: Center(
        child: Icon(Icons.fitness_center_rounded, color: Color(0xFF555555), size: 36),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  ReadyWorkoutsPage
// ─────────────────────────────────────────────
class ReadyWorkoutsPage extends ConsumerStatefulWidget {
  const ReadyWorkoutsPage({super.key, this.pro = false, this.source, this.saved = false});

  final bool pro;
  final String? source;
  /// Figma «Сохраненные тренировки»
  final bool saved;

  @override
  ConsumerState<ReadyWorkoutsPage> createState() => _ReadyWorkoutsPageState();
}

class _ReadyWorkoutsPageState extends ConsumerState<ReadyWorkoutsPage> {
  static const _previewLimit = 3;

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _showAll = false;
  String? _error;
  String? _filterLevel;
  String? _filterGoal;
  String? _filterEquipment;

  // dict options loaded lazily
  List<({String code, String title})> _levelOptions = const [];
  List<({String code, String title})> _goalOptions = const [];
  List<({String code, String title})> _equipmentOptions = const [];

  bool get _isTrainer => ref.watch(fitSessionProvider).user?.role == FitRole.trainer;

  @override
  void initState() {
    super.initState();
    _loadDicts();
    _load();
  }

  Future<void> _loadDicts() async {
    // Figma «Готовая тренировка» filter options (fixed catalog).
    if (!mounted) return;
    setState(() {
      _levelOptions = const [
        (code: 'beginner', title: 'Новичок'),
        (code: 'intermediate', title: 'Средний'),
        (code: 'advanced', title: 'Продвинутый'),
      ];
      _goalOptions = const [
        (code: 'gain_muscle', title: 'Нарастить мышцы'),
        (code: 'strength', title: 'Сила'),
        (code: 'lose_weight', title: 'Сбросить вес'),
      ];
      _equipmentOptions = const [
        (code: 'gym', title: 'Тренажерный зал'),
        (code: 'dumbbell', title: 'Гантели'),
        (code: 'bodyweight', title: 'Нет'),
      ];
    });
  }

  /// Keep unique program ids; drop entries without a valid id.
  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> raw) {
    final seen = <int>{};
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      final id = int.tryParse('${item['id']}') ?? 0;
      if (id <= 0 || seen.contains(id)) continue;
      seen.add(id);
      out.add(item);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _showAll = false;
    });
    try {
      if (widget.saved) {
        final items = await FitApi.savedPrograms();
        if (!mounted) return;
        setState(() {
          _items = _dedupe(items);
          _loading = false;
        });
        return;
      }
      // Готовая = опубликованные без Pro; от профи = is_pro=true (публикация уже на сервере).
      final items = await FitApi.programs(
        source: widget.source,
        isPro: widget.pro ? true : false,
        level: _filterLevel,
        goal: _filterGoal,
        equipment: _filterEquipment,
      );
      if (mounted) {
        setState(() {
          _items = _dedupe(items);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = FitApi.messageOf(e);
          _loading = false;
        });
        Toast.error(FitApi.messageOf(e));
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _filterLevel = null;
      _filterGoal = null;
      _filterEquipment = null;
    });
    _load();
  }

  bool get _hasFilter => _filterLevel != null || _filterGoal != null || _filterEquipment != null;

  Future<void> _pickLevel() async {
    final result = await _showPickerSheet(
      context: context,
      title: 'Уровень',
      options: _levelOptions,
      selected: _filterLevel,
    );
    if (result != null && mounted) {
      setState(() => _filterLevel = result == _filterLevel ? null : result);
      _load();
    }
  }

  Future<void> _pickGoal() async {
    final result = await _showPickerSheet(
      context: context,
      title: 'Цель',
      options: _goalOptions,
      selected: _filterGoal,
    );
    if (result != null && mounted) {
      setState(() => _filterGoal = result == _filterGoal ? null : result);
      _load();
    }
  }

  Future<void> _pickEquipment() async {
    final result = await _showPickerSheet(
      context: context,
      title: 'Оборудование',
      options: _equipmentOptions,
      selected: _filterEquipment,
    );
    if (result != null && mounted) {
      setState(() => _filterEquipment = result == _filterEquipment ? null : result);
      _load();
    }
  }

  Future<void> _openAllFilters() async {
    final result = await _showProgramFiltersSheet(
      context: context,
      levelOptions: _levelOptions,
      goalOptions: _goalOptions,
      equipmentOptions: _equipmentOptions,
      level: _filterLevel,
      goal: _filterGoal,
      equipment: _filterEquipment,
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterLevel = result.level;
      _filterGoal = result.goal;
      _filterEquipment = result.equipment;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isTrainer = _isTrainer;
    return FitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: HubBackTitle(
              title: widget.saved
                  ? 'Сохраненные тренировки'
                  : (widget.pro ? 'Тренировки от профи' : 'Готовая тренировка'),
              trailing: !widget.saved && _hasFilter
                  ? GestureDetector(
                      onTap: _clearFilters,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Text('Сброс', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    )
                  : null,
            ),
          ),
          if (!widget.saved) ...[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'Фильтр',
                    active: _hasFilter,
                    iconAsset: 'assets/icons/ready/filter.svg',
                    onTap: _openAllFilters,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _filterLevel != null ? _levelLabel(_filterLevel!) : 'Уровень',
                    active: _filterLevel != null,
                    trailingChevron: true,
                    onTap: _pickLevel,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _filterGoal != null ? _goalLabel(_filterGoal!) : 'Цель',
                    active: _filterGoal != null,
                    trailingChevron: true,
                    onTap: _pickGoal,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _filterEquipment != null
                        ? (_equipmentOptions.where((e) => e.code == _filterEquipment).firstOrNull?.title ?? _filterEquipment!)
                        : 'Оборудование',
                    active: _filterEquipment != null,
                    trailingChevron: true,
                    onTap: _pickEquipment,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _load,
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 140),
                        Center(child: CircularProgressIndicator(color: AppColors.accent)),
                      ],
                    )
                  : _error != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                          children: [
                            _CatalogEmpty(
                              title: 'Не удалось загрузить',
                              subtitle: _error!,
                              actionLabel: 'Повторить',
                              onAction: _load,
                            ),
                          ],
                        )
                      : _items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                              children: [
                                _CatalogEmpty(
                                  title: _hasFilter ? 'Ничего не найдено' : 'Пока нет готовых тренировок',
                                  subtitle: _hasFilter
                                      ? 'Измените или сбросьте фильтры — каталог обновится.'
                                      : (isTrainer
                                          ? 'Создайте первую программу — она появится здесь после публикации.'
                                          : 'Загляните позже — здесь появятся новые программы.'),
                                  actionLabel: _hasFilter
                                      ? 'Сбросить фильтры'
                                      : (isTrainer ? 'Создать программу' : null),
                                  onAction: _hasFilter
                                      ? _clearFilters
                                      : (isTrainer ? () => context.push(RouteNames.createProgram) : null),
                                ),
                              ],
                            )
                          : Builder(
                              builder: (context) {
                                final visible = _showAll ? _items : _items.take(_previewLimit).toList();
                                final hasMore = !_showAll && _items.length > _previewLimit;
                                return ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(16, 0, 16, isTrainer ? 8 : 24),
                                  itemCount: visible.length + (hasMore ? 1 : 0),
                                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    if (hasMore && index == visible.length) {
                                      return OutlinedButton(
                                        onPressed: () => setState(() => _showAll = true),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.accent,
                                          side: const BorderSide(color: Color(0xFF323232)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        child: Text(
                                          'Показать все ${_items.length}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                      );
                                    }
                                    final item = visible[index];
                                    final id = int.tryParse('${item['id']}') ?? 0;
                                    return _ProgramCard(
                                      item: item,
                                      onTap: () {
                                        if (id <= 0) return;
                                        context.push(RouteNames.programDetail, extra: id);
                                      },
                                    );
                                  },
                                );
                              },
                            ),
            ),
          ),
          if (isTrainer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push(RouteNames.createProgram),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Создать программу', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
          ),
          child: const Icon(Icons.fitness_center_rounded, color: AppColors.accent, size: 36),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.fitGrey, fontSize: 14, height: 1.4),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  _FilterChip
// ─────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.iconAsset,
    this.trailingChevron = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? iconAsset;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.accent : const Color(0xFF292929)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconAsset != null) ...[
              SvgPicture.asset(
                iconAsset!,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(active ? AppColors.accent : Colors.white, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(color: active ? AppColors.accent : Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (trailingChevron) ...[
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/icons/ready/arrow-down.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(active ? AppColors.accent : Colors.white, BlendMode.srcIn),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  _ProgramCard
// ─────────────────────────────────────────────
class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  String _equipmentSubtitle(List<String> codes) {
    final lower = codes.map((e) => e.toLowerCase()).toList();
    if (lower.any((e) => e.contains('gym') || e.contains('machine') || e.contains('зал'))) {
      return '(С тренажёрами)';
    }
    if (lower.any((e) => e.contains('dumbbell') || e.contains('гантел'))) return '(С гантелями)';
    if (lower.any((e) => e.contains('body') || e.contains('нет') || e.contains('none'))) return '(Без оборудования)';
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
    return int.tryParse('${item['workouts_per_week']}') ?? 3;
  }

  @override
  Widget build(BuildContext context) {
    final name = item['title']?.toString().trim();
    final title = (name == null || name.isEmpty) ? 'Программа' : name;

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
                        _programCover(cover),
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

// ─────────────────────────────────────────────
//  ProgramDetailPage
// ─────────────────────────────────────────────
class ProgramDetailPage extends ConsumerStatefulWidget {
  const ProgramDetailPage({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ProgramDetailPage> createState() => _ProgramDetailPageState();
}

class _ProgramDetailPageState extends ConsumerState<ProgramDetailPage> {
  Map<String, dynamic>? _program;
  bool _loading = true;
  bool _busy = false;

  bool get _isTrainer => ref.watch(fitSessionProvider).user?.role == FitRole.trainer;
  bool get _canEditProgram {
    final user = ref.watch(fitSessionProvider).user;
    if (user == null || user.role != FitRole.trainer) return false;
    final authorId = int.tryParse('${_program?['author_id']}') ?? 0;
    return authorId > 0 && authorId == user.id;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await FitApi.program(widget.id);
      if (mounted) setState(() => _program = data);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDay(Map<String, dynamic> day) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProgramDayPage(programId: widget.id, day: day),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _duplicateDay(Map<String, dynamic> day) async {
    if (!_canEditProgram) {
      // Non-author trainers: duplicate whole program into drafts.
      await _duplicate();
      return;
    }
    setState(() => _busy = true);
    try {
      final title = day['title']?.toString() ?? 'Комплекс';
      final created = await FitApi.addProgramDay(widget.id, {
        'title': '$title (копия)',
        if (day['description'] != null) 'description': day['description'],
        if (day['duration_min'] != null) 'duration_min': day['duration_min'],
        if (day['focus_muscles'] is List) 'focus_muscles': day['focus_muscles'],
        if (day['week_id'] != null) 'week_id': day['week_id'],
      });
      final flat = _flatDays(created);
      Map<String, dynamic>? newDay;
      for (final d in flat.reversed) {
        if (d['title']?.toString() == '$title (копия)') {
          newDay = d;
          break;
        }
      }
      newDay ??= flat.isNotEmpty ? flat.last : null;
      final newDayId = int.tryParse('${newDay?['id']}') ?? 0;
      final exercises = day['exercises'];
      if (newDayId > 0 && exercises is List) {
        for (final ex in exercises.whereType<Map>()) {
          final exerciseId = int.tryParse('${ex['exercise_id']}') ?? 0;
          if (exerciseId <= 0) continue;
          await FitApi.addProgramDayExercise(widget.id, newDayId, {
            'exercise_id': exerciseId,
            if (ex['sets'] != null) 'sets': ex['sets'],
            if (ex['reps_min'] != null) 'reps_min': ex['reps_min'],
            if (ex['reps_max'] != null) 'reps_max': ex['reps_max'],
            if (ex['note'] != null) 'note': ex['note'],
            if (ex['rest_sec'] != null) 'rest_sec': ex['rest_sec'],
            if (ex['weight_kg'] != null) 'weight_kg': ex['weight_kg'],
            if (ex['video_lesson_id'] != null) 'video_lesson_id': ex['video_lesson_id'],
          });
        }
      }
      if (mounted) {
        Toast.success('Комплекс скопирован');
        await _load();
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDay(Map<String, dynamic> day) async {
    final dayId = int.tryParse('${day['id']}') ?? 0;
    if (dayId <= 0 || !_canEditProgram) return;
    final title = day['title']?.toString() ?? 'Комплекс';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Удалить комплекс?', style: TextStyle(color: Colors.white)),
        content: Text(title, style: const TextStyle(color: AppColors.fitGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Color(0xFFFD6565))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await FitApi.deleteProgramDay(widget.id, dayId);
      if (mounted) {
        Toast.success('Комплекс удалён');
        await _load();
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicate() async {
    if (!_isTrainer) return;
    setState(() => _busy = true);
    try {
      await FitApi.duplicateProgram(widget.id);
      if (mounted) Toast.success('Копия создана в ваших черновиках');
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProgram() async {
    if (!_canEditProgram) return;
    final title = _program?['title']?.toString() ?? 'Программа';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Удалить программу?', style: TextStyle(color: Colors.white)),
        content: Text(
          '«$title» будет архивирована. Это действие нельзя отменить.',
          style: const TextStyle(color: AppColors.fitGrey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Color(0xFFFD6565))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await FitApi.deleteProgram(widget.id);
      if (!mounted) return;
      Toast.success('Программа удалена');
      context.pop(true);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _firstStartableDayId() {
    final program = _program;
    if (program == null) return null;
    final weeks = program['weeks'];
    if (weeks is List) {
      for (final week in weeks.whereType<Map>()) {
        final days = week['days'];
        if (days is! List) continue;
        for (final day in days.whereType<Map>()) {
          if (day['locked'] == true) continue;
          final id = int.tryParse('${day['id']}') ?? 0;
          if (id > 0) return id;
        }
      }
    }
    final days = program['days'];
    if (days is List) {
      for (final day in days.whereType<Map>()) {
        if (day['locked'] == true) continue;
        final id = int.tryParse('${day['id']}') ?? 0;
        if (id > 0) return id;
      }
    }
    return null;
  }

  Future<void> _startWorkout() async {
    final dayId = _firstStartableDayId();
    if (dayId == null) {
      final needsPro = _program?['is_pro'] == true && _program?['has_pro_access'] == false;
      if (needsPro) {
        Toast.info('Для полного доступа нужна подписка Pro');
        if (mounted) context.push(RouteNames.subscription);
        return;
      }
      Toast.info('Нет доступного дня для старта');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await FitApi.startOrResumeSession(programDayId: dayId);
      final sessionId = result.sessionId;
      if (!mounted) return;
      if (sessionId > 0) {
        await WorkoutOfflineQueue.I.setActiveSessionId(sessionId);
        if (result.resumed) Toast.info('Продолжаем текущую тренировку');
        if (!mounted) return;
        context.push(RouteNames.liveSession, extra: sessionId);
      } else {
        Toast.success('Тренировка начата');
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _flatDays(Map<String, dynamic>? program) {
    if (program == null) return const [];
    final out = <Map<String, dynamic>>[];
    final weeks = program['weeks'];
    if (weeks is List && weeks.isNotEmpty) {
      for (final week in weeks.whereType<Map>()) {
        final days = week['days'];
        if (days is! List) continue;
        for (final day in days.whereType<Map>()) {
          out.add(Map<String, dynamic>.from(day));
        }
      }
      return out;
    }
    final days = program['days'];
    if (days is List) {
      for (final day in days.whereType<Map>()) {
        out.add(Map<String, dynamic>.from(day));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    final isTrainer = _isTrainer;
    final canEdit = _canEditProgram;
    final canStart = _firstStartableDayId() != null;
    final needsPro = program?['is_pro'] == true && program?['has_pro_access'] == false;
    final title = program?['title']?.toString() ?? 'Программа';
    final levelRaw = program?['level']?.toString() ?? '';
    final level = levelRaw.isEmpty ? '' : _levelLabel(levelRaw);
    final goals = program?['goals'];
    final goalRaw = goals is List && goals.isNotEmpty ? goals.first.toString() : '';
    final goal = goalRaw.isEmpty ? '' : _goalLabel(goalRaw);
    final equipmentList = program?['equipment'];
    final equipmentCodes = equipmentList is List
        ? equipmentList.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final place = _equipmentPlaceLabel(equipmentCodes);
    final perWeek = program?['workouts_per_week'];
    final freq = perWeek == null ? 'С оборудованием' : '$perWeek комплекса в нед.';
    final cover = FitMedia.url(program?['cover_url']?.toString());
    final desc = program?['description']?.toString() ?? '';
    final days = _flatDays(program);

    return FitScaffold(
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                          ),
                          const Expanded(
                            child: Text(
                              'Программа',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (canEdit)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz, color: Colors.white70),
                              color: const Color(0xFF292929),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF323232)),
                              ),
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await context.push(RouteNames.createProgram, extra: widget.id);
                                  if (mounted) _load();
                                } else if (v == 'delete') {
                                  await _deleteProgram();
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  height: 36,
                                  child: Row(
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/program/edit.svg',
                                        width: 16,
                                        height: 16,
                                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text('Редактировать', style: TextStyle(color: Colors.white, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  height: 36,
                                  child: Row(
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/program/delete.svg',
                                        width: 16,
                                        height: 16,
                                        colorFilter: const ColorFilter.mode(Color(0xFFFD6565), BlendMode.srcIn),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text('Удалить', style: TextStyle(color: Color(0xFFFD6565), fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF232323),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      Text(
                                        _equipmentPlaceLabel(equipmentCodes) == 'Тренажерный зал'
                                            ? '(С тренажёрами)'
                                            : (level.isNotEmpty ? '($level)' : ''),
                                        style: const TextStyle(color: Color(0xFF979797), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: SizedBox(
                                      height: 160,
                                      width: double.infinity,
                                      child: _programCover(cover),
                                    ),
                                  ),
                                ),
                                // Trainer own: edit. Trainer catalog: copy to drafts. Client: no save CTA.
                                if (canEdit || isTrainer)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () async {
                                                if (canEdit) {
                                                  await context.push(RouteNames.createProgram, extra: widget.id);
                                                  if (mounted) _load();
                                                } else {
                                                  await _duplicate();
                                                }
                                              },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                        ),
                                        child: Text(
                                          canEdit ? 'Редактировать программу' : 'Использовать программу',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (canEdit)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: _busy ? null : _deleteProgram,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFFD6565),
                                          side: const BorderSide(color: Color(0xFFFD6565)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        child: const Text('Удалить программу', style: TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  ),
                                if (desc.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                    child: Text(
                                      desc,
                                      style: const TextStyle(color: AppColors.fitGrey, fontSize: 14, height: 1.45),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                  child: Row(
                                    children: [
                                      Expanded(child: _MetaTile(icon: Icons.signal_cellular_alt_rounded, label: level.isEmpty ? 'Уровень' : level)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _MetaTile(icon: Icons.fitness_center_rounded, label: goal.isEmpty ? 'Цель' : goal)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _MetaTile(icon: Icons.location_on_outlined, label: place)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _MetaTile(icon: Icons.assignment_outlined, label: freq)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Комплексы упражнений',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          if (days.isEmpty)
                            const Text('Дни не указаны', style: TextStyle(color: AppColors.fitGrey))
                          else
                            for (var i = 0; i < days.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              _DayCard(
                                index: i,
                                day: days[i],
                                isTrainer: isTrainer,
                                canEdit: canEdit,
                                initiallyExpanded: true,
                                onEdit: _busy || !canEdit ? null : () => _editDay(days[i]),
                                onDuplicateDay: canEdit && !_busy
                                    ? () => _duplicateDay(days[i])
                                    : null,
                                onDelete: _busy || !canEdit ? null : () => _deleteDay(days[i]),
                                onOpenPro: needsPro ? () => context.push(RouteNames.subscription) : null,
                              ),
                            ],
                          // Start workout is a client action — hide for trainers.
                          if (!isTrainer && canStart) ...[
                            const SizedBox(height: 16),
                            ValueListenableBuilder<int?>(
                              valueListenable: WorkoutOfflineQueue.I.activeSession,
                              builder: (context, activeId, _) {
                                final resume = activeId != null && activeId > 0;
                                return SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _busy ? null : _startWorkout,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.accent,
                                      side: const BorderSide(color: AppColors.accent),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: Text(
                                      resume ? 'Продолжить тренировку' : 'Начать тренировку',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (needsPro)
                  Positioned.fill(
                    child: _ProAccessGate(
                      onSubscribe: () async {
                        await context.push(RouteNames.subscription);
                        if (mounted) _load();
                      },
                      onCancel: () => context.pop(),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.15),
          ),
        ],
      ),
    );
  }
}

class _ProAccessGate extends StatelessWidget {
  const _ProAccessGate({required this.onSubscribe, required this.onCancel});

  final VoidCallback onSubscribe;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium_rounded, color: AppColors.accent, size: 40),
                  const SizedBox(height: 14),
                  const Text(
                    'Pro-программа',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.accent, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Превью доступно бесплатно. Полные недели открываются с активной подпиской Pro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.fitGrey, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: onSubscribe,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Оформить', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatefulWidget {
  const _DayCard({
    required this.index,
    required this.day,
    this.onOpenPro,
    this.onEdit,
    this.onDuplicateDay,
    this.onDelete,
    this.isTrainer = false,
    this.canEdit = false,
    this.initiallyExpanded = true,
  });

  final int index;
  final Map<String, dynamic> day;
  final VoidCallback? onOpenPro;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicateDay;
  final VoidCallback? onDelete;
  final bool isTrainer;
  final bool canEdit;
  final bool initiallyExpanded;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final locked = widget.day['locked'] == true;
    final title = widget.day['title']?.toString() ?? 'День ${widget.index + 1}';
    final description = widget.day['description']?.toString() ?? '';
    final exercises = widget.day['exercises'];
    final exerciseList = exercises is List ? exercises : [];
    final showMenu = widget.isTrainer && (widget.canEdit || widget.onDuplicateDay != null);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: locked ? AppColors.accent.withValues(alpha: 0.25) : const Color(0xFF323232)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (showMenu)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Colors.white70),
                    color: const Color(0xFF292929),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFF323232)),
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'edit') widget.onEdit?.call();
                      if (v == 'duplicate') widget.onDuplicateDay?.call();
                      if (v == 'delete') widget.onDelete?.call();
                    },
                    itemBuilder: (_) => [
                      if (widget.canEdit && widget.onEdit != null)
                        PopupMenuItem(
                          value: 'edit',
                          height: 36,
                          child: Row(
                            children: [
                              SvgPicture.asset(
                                'assets/icons/program/edit.svg',
                                width: 16,
                                height: 16,
                                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                              ),
                              const SizedBox(width: 4),
                              const Text('Редактировать', style: TextStyle(color: Colors.white, fontSize: 14)),
                            ],
                          ),
                        ),
                      if (widget.onDuplicateDay != null)
                        PopupMenuItem(
                          value: 'duplicate',
                          height: 36,
                          child: Row(
                            children: [
                              SvgPicture.asset(
                                'assets/icons/program/copy.svg',
                                width: 16,
                                height: 16,
                                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                              ),
                              const SizedBox(width: 4),
                              const Text('Дублировать', style: TextStyle(color: Colors.white, fontSize: 14)),
                            ],
                          ),
                        ),
                      if (widget.canEdit && widget.onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          height: 36,
                          child: Row(
                            children: [
                              SvgPicture.asset(
                                'assets/icons/program/delete.svg',
                                width: 16,
                                height: 16,
                                colorFilter: const ColorFilter.mode(Color(0xFFFD6565), BlendMode.srcIn),
                              ),
                              const SizedBox(width: 4),
                              const Text('Удалить', style: TextStyle(color: Color(0xFFFD6565), fontSize: 14)),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  IconButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.fitGrey),
                  ),
              ],
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: CustomPaint(
                painter: _DayDashedBorderPainter(color: const Color(0xFF4A4A4A), radius: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(description, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13, height: 1.4)),
                ),
              ),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: locked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Содержание этой недели скрыто. Оформите подписку Pro, чтобы открыть упражнения.',
                          style: TextStyle(color: AppColors.fitGrey, fontSize: 13, height: 1.35),
                        ),
                        if (widget.onOpenPro != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: widget.onOpenPro,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Оформить Pro', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      children: [
                        if (exerciseList.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Упражнения не указаны', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                          )
                        else
                          for (var i = 0; i < exerciseList.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _ExerciseRow(
                              item: exerciseList[i] is Map
                                  ? Map<String, dynamic>.from(exerciseList[i] as Map)
                                  : {},
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

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['title']?.toString() ?? item['name']?.toString() ?? 'Упражнение';
    final meta = _setsRepsLabel(item);

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FitExerciseThumb.fromExercise(item, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Combined program filters sheet (Figma icon cards)
// ─────────────────────────────────────────────
typedef _ProgramFilters = ({String? level, String? goal, String? equipment});

String? _filterIconFor(String code) {
  return switch (code) {
    'beginner' => 'assets/icons/ready/level1.svg',
    'intermediate' => 'assets/icons/ready/level2.svg',
    'advanced' => 'assets/icons/ready/level3.svg',
    'gain_muscle' || 'mass' || 'muscle_gain' => 'assets/icons/ready/biceps.svg',
    'strength' => 'assets/icons/ready/dumbbell.svg',
    'lose_weight' || 'weight_loss' => 'assets/icons/ready/weight.svg',
    'gym' || 'machine' => 'assets/icons/ready/gym.svg',
    'dumbbell' => 'assets/icons/ready/dumbbells.svg',
    'bodyweight' || 'none' => 'assets/icons/ready/bodyweight.svg',
    _ => null,
  };
}

Widget _filterOptionCards({
  required List<({String code, String title})> options,
  required String? selected,
  required ValueChanged<String?> onSelect,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            onTap: () => onSelect(selected == options[i].code ? null : options[i].code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              decoration: BoxDecoration(
                color: selected == options[i].code ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == options[i].code ? AppColors.accent : const Color(0xFF323232),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_filterIconFor(options[i].code) != null)
                    SvgPicture.asset(
                      _filterIconFor(options[i].code)!,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    )
                  else
                    const Icon(Icons.circle_outlined, color: Colors.white, size: 24),
                  const SizedBox(height: 12),
                  Text(
                    options[i].title,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

Future<_ProgramFilters?> _showProgramFiltersSheet({
  required BuildContext context,
  required List<({String code, String title})> levelOptions,
  required List<({String code, String title})> goalOptions,
  required List<({String code, String title})> equipmentOptions,
  String? level,
  String? goal,
  String? equipment,
}) {
  return showModalBottomSheet<_ProgramFilters>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0x80232323),
    backgroundColor: const Color(0xFF232323),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      var localLevel = level;
      var localGoal = goal;
      var localEquipment = equipment;
      return StatefulBuilder(
        builder: (context, setSheet) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 72, height: 5, decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100))),
                  const SizedBox(height: 16),
                  const Text('Фильтр', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Уровень', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          _filterOptionCards(options: levelOptions, selected: localLevel, onSelect: (v) => setSheet(() => localLevel = v)),
                          const SizedBox(height: 16),
                          const Text('Цель', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          _filterOptionCards(options: goalOptions, selected: localGoal, onSelect: (v) => setSheet(() => localGoal = v)),
                          const SizedBox(height: 16),
                          const Text('Оборудование', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          _filterOptionCards(options: equipmentOptions, selected: localEquipment, onSelect: (v) => setSheet(() => localEquipment = v)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => setSheet(() {
                        localLevel = null;
                        localGoal = null;
                        localEquipment = null;
                      }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: Color(0xFF323232)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Очистить фильтры', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, (
                        level: localLevel,
                        goal: localGoal,
                        equipment: localEquipment,
                      )),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Показать результаты', style: TextStyle(fontWeight: FontWeight.w700)),
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
}

Future<String?> _showPickerSheet({
  required BuildContext context,
  required String title,
  required List<({String code, String title})> options,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0x80232323),
    backgroundColor: const Color(0xFF232323),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      String? localSelected = selected;
      return StatefulBuilder(
        builder: (context, setSheet) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 72, height: 5, decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100))),
                const SizedBox(height: 16),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                if (options.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Нет вариантов', style: TextStyle(color: AppColors.fitGrey)))
                else
                  _filterOptionCards(
                    options: options,
                    selected: localSelected,
                    onSelect: (v) {
                      setSheet(() => localSelected = v);
                      Navigator.pop(ctx, v);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      );
    },
  );
}

class _DayDashedBorderPainter extends CustomPainter {
  _DayDashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayDashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
