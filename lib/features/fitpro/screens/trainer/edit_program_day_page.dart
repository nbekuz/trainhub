import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';

/// Edit a program day: title, description, focus muscles, exercise sets/reps; swap/delete exercises.
class EditProgramDayPage extends StatefulWidget {
  const EditProgramDayPage({
    super.key,
    required this.programId,
    required this.day,
  });

  final int programId;
  final Map<String, dynamic> day;

  @override
  State<EditProgramDayPage> createState() => _EditProgramDayPageState();
}

class _EditProgramDayPageState extends State<EditProgramDayPage> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late List<Map<String, dynamic>> _exercises;
  late Set<String> _focusMuscles;
  List<({String code, String title})> _muscleOpts = const [];
  bool _saving = false;
  bool _orderDirty = false;

  int get _dayId => int.tryParse('${widget.day['id']}') ?? 0;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.day['title']?.toString() ?? '');
    _desc = TextEditingController(text: widget.day['description']?.toString() ?? '');
    final raw = widget.day['exercises'];
    _exercises = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final muscles = widget.day['focus_muscles'];
    _focusMuscles = muscles is List
        ? muscles.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet()
        : <String>{};
    _loadMuscles();
  }

  Future<void> _loadMuscles() async {
    try {
      final dicts = await FitApi.dictionaries();
      if (!mounted) return;
      setState(() {
        _muscleOpts = dicts
            .where((d) => d.category == 'muscle_group')
            .map((d) => (code: d.code, title: d.title))
            .toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _applyProgram(Map<String, dynamic> program) {
    final days = program['days'];
    final weeks = program['weeks'];
    Map<String, dynamic>? found;
    if (days is List) {
      for (final d in days.whereType<Map>()) {
        if (int.tryParse('${d['id']}') == _dayId) {
          found = Map<String, dynamic>.from(d);
          break;
        }
      }
    }
    if (found == null && weeks is List) {
      for (final week in weeks.whereType<Map>()) {
        final wd = week['days'];
        if (wd is! List) continue;
        for (final d in wd.whereType<Map>()) {
          if (int.tryParse('${d['id']}') == _dayId) {
            found = Map<String, dynamic>.from(d);
            break;
          }
        }
        if (found != null) break;
      }
    }
    if (found == null) return;
    final ex = found['exercises'];
    setState(() {
      _title.text = found!['title']?.toString() ?? _title.text;
      _desc.text = found['description']?.toString() ?? _desc.text;
      final fm = found['focus_muscles'];
      if (fm is List) {
        _focusMuscles = fm.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
      }
      if (ex is List) {
        _exercises = ex.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    });
  }

  Future<void> _saveDayMeta() async {
    if (_dayId <= 0) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      Toast.error('Укажите название комплекса');
      return;
    }
    if (_exercises.isEmpty) {
      Toast.info('Добавьте хотя бы одно упражнение');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_orderDirty) {
        final ids = _exercises.map((e) => int.tryParse('${e['id']}') ?? 0).where((id) => id > 0).toList();
        if (ids.length == _exercises.length && ids.isNotEmpty) {
          await FitApi.reorderProgramDayExercises(widget.programId, _dayId, ids);
        }
        _orderDirty = false;
      }
      await FitApi.patchProgramDay(widget.programId, _dayId, {
        'title': title,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'focus_muscles': _focusMuscles.toList(),
        if (widget.day['duration_min'] != null) 'duration_min': widget.day['duration_min'],
        if (widget.day['sort_order'] != null) 'sort_order': widget.day['sort_order'],
        if (widget.day['week_id'] != null) 'week_id': widget.day['week_id'],
      });
      if (!mounted) return;
      Toast.success('Сохранено');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>?> _pickExercise() async {
    List<Map<String, dynamic>> catalog = [];
    try {
      catalog = await FitApi.exercises();
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
      return null;
    }
    if (!mounted) return null;
    if (catalog.isEmpty) {
      Toast.info('Каталог упражнений пуст');
      return null;
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.fitCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Выберите упражнение', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: catalog.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final ex = catalog[i];
                  final name = ex['title']?.toString() ?? ex['name']?.toString() ?? 'Упражнение';
                  final muscle = FitLabels.muscle(
                    ex['primary_muscle']?.toString() ?? ex['muscle']?.toString(),
                  );
                  return Material(
                    color: const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(ctx, ex),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            FitExerciseThumb.fromExercise(ex, size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  if (muscle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(muscle, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
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
      ),
    );
  }

  Future<void> _editExercise(int index) async {
    final item = _exercises[index];
    final itemId = int.tryParse('${item['id']}') ?? 0;
    var exerciseId = int.tryParse('${item['exercise_id']}') ?? 0;
    if (itemId <= 0 || exerciseId <= 0) {
      Toast.error('Нельзя изменить это упражнение');
      return;
    }
    final setsCtrl = TextEditingController(text: item['sets']?.toString() ?? '');
    final repsMinCtrl = TextEditingController(text: item['reps_min']?.toString() ?? '');
    final repsMaxCtrl = TextEditingController(text: item['reps_max']?.toString() ?? '');
    var name = item['title']?.toString() ?? item['name']?.toString() ?? 'Упражнение';
    var muscle = FitLabels.muscle(item['primary_muscle']?.toString());

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  if (muscle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(muscle, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickExercise();
                      if (picked == null) return;
                      final id = int.tryParse('${picked['id']}') ?? 0;
                      if (id <= 0) return;
                      setModal(() {
                        exerciseId = id;
                        name = picked['title']?.toString() ?? picked['name']?.toString() ?? name;
                        muscle = FitLabels.muscle(
                          picked['primary_muscle']?.toString() ?? picked['muscle']?.toString(),
                        );
                      });
                    },
                    icon: const Icon(Icons.swap_horiz, color: AppColors.accent, size: 18),
                    label: const Text('Сменить упражнение', style: TextStyle(color: AppColors.accent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Подходы', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                  const SizedBox(height: 6),
                  _NumField(controller: setsCtrl),
                  const SizedBox(height: 12),
                  const Text('Повторения от', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                  const SizedBox(height: 6),
                  _NumField(controller: repsMinCtrl),
                  const SizedBox(height: 12),
                  const Text('Повторения до', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                  const SizedBox(height: 6),
                  _NumField(controller: repsMaxCtrl),
                  const SizedBox(height: 16),
                  FitAccentButton(
                    title: 'Сохранить',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) {
      setsCtrl.dispose();
      repsMinCtrl.dispose();
      repsMaxCtrl.dispose();
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await FitApi.patchProgramDayExercise(widget.programId, _dayId, itemId, {
        'exercise_id': exerciseId,
        'sets': int.tryParse(setsCtrl.text.trim()),
        'reps_min': int.tryParse(repsMinCtrl.text.trim()),
        'reps_max': int.tryParse(repsMaxCtrl.text.trim()),
        if (item['note'] != null) 'note': item['note'],
        if (item['rest_sec'] != null) 'rest_sec': item['rest_sec'],
        if (item['weight_kg'] != null) 'weight_kg': item['weight_kg'],
        if (item['sort_order'] != null) 'sort_order': item['sort_order'],
        if (item['video_lesson_id'] != null) 'video_lesson_id': item['video_lesson_id'],
      });
      _applyProgram(updated);
      if (mounted) Toast.success('Упражнение обновлено');
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      setsCtrl.dispose();
      repsMinCtrl.dispose();
      repsMaxCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteExercise(int index) async {
    final item = _exercises[index];
    final itemId = int.tryParse('${item['id']}') ?? 0;
    if (itemId <= 0) return;
    final name = item['title']?.toString() ?? item['name']?.toString() ?? 'Упражнение';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Удалить упражнение?', style: TextStyle(color: Colors.white)),
        content: Text(name, style: const TextStyle(color: AppColors.fitGrey)),
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
    setState(() => _saving = true);
    try {
      final updated = await FitApi.deleteProgramDayExercise(widget.programId, _dayId, itemId);
      _applyProgram(updated);
      if (mounted) Toast.success('Удалено');
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addExercise() async {
    final picked = await _pickExercise();
    if (picked == null || !mounted) return;
    final exerciseId = int.tryParse('${picked['id']}') ?? 0;
    if (exerciseId <= 0) return;

    final setsCtrl = TextEditingController(text: '3');
    final repsMinCtrl = TextEditingController(text: '10');
    final repsMaxCtrl = TextEditingController(text: '12');
    final name = picked['title']?.toString() ?? picked['name']?.toString() ?? 'Упражнение';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              const Text('Подходы', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
              const SizedBox(height: 6),
              _NumField(controller: setsCtrl),
              const SizedBox(height: 12),
              const Text('Повторения от', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
              const SizedBox(height: 6),
              _NumField(controller: repsMinCtrl),
              const SizedBox(height: 12),
              const Text('Повторения до', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
              const SizedBox(height: 6),
              _NumField(controller: repsMaxCtrl),
              const SizedBox(height: 16),
              FitAccentButton(title: 'Добавить', onPressed: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (ok != true || !mounted) {
      setsCtrl.dispose();
      repsMinCtrl.dispose();
      repsMaxCtrl.dispose();
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await FitApi.addProgramDayExercise(widget.programId, _dayId, {
        'exercise_id': exerciseId,
        'sets': int.tryParse(setsCtrl.text.trim()) ?? 3,
        'reps_min': int.tryParse(repsMinCtrl.text.trim()),
        'reps_max': int.tryParse(repsMaxCtrl.text.trim()),
      });
      _applyProgram(updated);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      setsCtrl.dispose();
      repsMinCtrl.dispose();
      repsMaxCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  String _meta(Map<String, dynamic> item) {
    final sets = item['sets'];
    final rMin = item['reps_min'];
    final rMax = item['reps_max'];
    final parts = <String>[];
    if (sets != null) {
      final n = int.tryParse('$sets') ?? 0;
      if (n == 1) {
        parts.add('1 подход');
      } else if (n > 1 && n < 5) {
        parts.add('$n подхода');
      } else if (n >= 5) {
        parts.add('$n подходов');
      }
    }
    if (rMin != null && rMax != null) {
      parts.add('$rMin–$rMax повторений');
    } else if (rMin != null) {
      parts.add('$rMin повторений');
    } else if (rMax != null) {
      parts.add('$rMax повторений');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: HubBackTitle(
              title: _title.text.trim().isEmpty ? 'Комплекс' : _title.text.trim(),
              trailing: TextButton(
                onPressed: _saving ? null : _saveDayMeta,
                child: Text(
                  'Готово',
                  style: TextStyle(
                    color: _saving ? AppColors.fitGrey : AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const Text('Название', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                const SizedBox(height: 8),
                _DarkField(controller: _title, onChanged: (_) => setState(() {})),
                const SizedBox(height: 16),
                const Text('Описание', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                const SizedBox(height: 8),
                CustomPaint(
                  painter: _DashedRRectPainter(color: const Color(0xFF4A4A4A), radius: 16),
                  child: TextField(
                    controller: _desc,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                    cursorColor: AppColors.accent,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(14),
                      border: InputBorder.none,
                      hintText: 'Описание комплекса',
                      hintStyle: TextStyle(color: AppColors.fitGrey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Группы мышц', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                const SizedBox(height: 8),
                if (_muscleOpts.isEmpty)
                  const Text('Загрузка…', style: TextStyle(color: AppColors.fitGrey, fontSize: 12))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _muscleOpts)
                        FilterChip(
                          label: Text(m.title),
                          selected: _focusMuscles.contains(m.code),
                          onSelected: _saving
                              ? null
                              : (v) => setState(() {
                                    if (v) {
                                      _focusMuscles.add(m.code);
                                    } else {
                                      _focusMuscles.remove(m.code);
                                    }
                                  }),
                          selectedColor: AppColors.accent.withValues(alpha: 0.2),
                          checkmarkColor: AppColors.accent,
                          labelStyle: TextStyle(
                            color: _focusMuscles.contains(m.code) ? AppColors.accent : Colors.white70,
                            fontSize: 13,
                          ),
                          backgroundColor: const Color(0xFF1A1A1A),
                          side: BorderSide(
                            color: _focusMuscles.contains(m.code) ? AppColors.accent : const Color(0xFF3A3A3A),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Упражнения',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _addExercise,
                      icon: const Icon(Icons.add, color: AppColors.accent, size: 18),
                      label: const Text('Добавить', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (_exercises.length > 1)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Удерживайте ≡ и перетащите. Порядок сохранится по кнопке «Сохранить».',
                      style: TextStyle(color: AppColors.fitGrey, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 4),
                if (_exercises.isEmpty)
                  const Text('Нет упражнений', style: TextStyle(color: AppColors.fitGrey))
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _exercises.length,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          return Material(
                            color: Colors.transparent,
                            elevation: 6 * animation.value,
                            borderRadius: BorderRadius.circular(16),
                            child: child,
                          );
                        },
                      );
                    },
                    onReorder: _saving
                        ? (oldIndex, newIndex) {}
                        : (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            setState(() {
                              final item = _exercises.removeAt(oldIndex);
                              _exercises.insert(newIndex, item);
                              _orderDirty = true;
                            });
                          },
                    itemBuilder: (context, i) {
                      final item = _exercises[i];
                      final id = int.tryParse('${item['id']}') ?? i;
                      return Padding(
                        key: ValueKey('ex-$id'),
                        padding: EdgeInsets.only(bottom: i == _exercises.length - 1 ? 0 : 10),
                        child: _ExerciseEditTile(
                          name: item['title']?.toString() ?? item['name']?.toString() ?? 'Упражнение',
                          meta: _meta(item),
                          photoUrl: FitMedia.url(item['photo_url']?.toString()) ??
                              FitMedia.url(
                                (item['photo_urls'] is List && (item['photo_urls'] as List).isNotEmpty)
                                    ? (item['photo_urls'] as List).first.toString()
                                    : null,
                              ),
                          dragIndex: i,
                          onEdit: _saving ? null : () => _editExercise(i),
                          onDelete: _saving ? null : () => _deleteExercise(i),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),
                FitAccentButton(
                  title: 'Сохранить комплекс',
                  loading: _saving,
                  onPressed: _saving ? null : _saveDayMeta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
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
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _DarkField extends StatelessWidget {
  const _DarkField({required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

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
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        cursorColor: AppColors.accent,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.controller});

  final TextEditingController controller;

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
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: AppColors.accent,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _ExerciseEditTile extends StatelessWidget {
  const _ExerciseEditTile({
    required this.name,
    required this.meta,
    required this.onEdit,
    required this.onDelete,
    required this.dragIndex,
    this.photoUrl,
  });

  final String name;
  final String meta;
  final String? photoUrl;
  final int dragIndex;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF323232)),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: dragIndex,
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.drag_handle_rounded, color: AppColors.fitGrey, size: 22),
            ),
          ),
          FitExerciseThumb(url: photoUrl, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: SvgPicture.asset(
              'assets/icons/program/edit.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(Colors.white70, BlendMode.srcIn),
            ),
            tooltip: 'Редактировать',
          ),
          IconButton(
            onPressed: onDelete,
            icon: SvgPicture.asset(
              'assets/icons/program/delete.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(Color(0xFFFD6565), BlendMode.srcIn),
            ),
            tooltip: 'Удалить',
          ),
        ],
      ),
    );
  }
}
