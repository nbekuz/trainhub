import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/image_upload.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/screens/trainer/edit_program_day_page.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/routes/route_names.dart';

/// Create / edit program structure. Day content is edited via [EditProgramDayPage].
class CreateProgramPage extends ConsumerStatefulWidget {
  const CreateProgramPage({super.key, this.programId, this.asOwnWorkout = false});

  final int? programId;

  /// Client «Своя тренировка»: same flow, no moderation.
  final bool asOwnWorkout;

  @override
  ConsumerState<CreateProgramPage> createState() => _CreateProgramPageState();
}

class _CreateProgramPageState extends ConsumerState<CreateProgramPage> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _saving = false;
  bool _loadingExisting = false;
  bool _busy = false;
  bool _addingDay = false;

  int? _createdProgramId;
  String _createdTitle = '';
  String _status = 'draft';
  String? _coverUrl;
  String? _coverPath;
  String? _coverName;
  int? _activeWeekId;
  List<Map<String, dynamic>> _days = [];

  bool get _isTrainer => ref.read(fitSessionProvider).user?.role == FitRole.trainer;
  bool get _ownMode => widget.asOwnWorkout || !_isTrainer;
  bool get _hasCover => (_coverPath != null && _coverPath!.isNotEmpty) || (_coverUrl != null && _coverUrl!.trim().isNotEmpty);
  bool get _formValid => _titleCtrl.text.trim().isNotEmpty && _hasCover && !_saving;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.programId;
      if (id != null && id > 0) _loadExisting(id);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting(int id) async {
    setState(() => _loadingExisting = true);
    try {
      final program = await FitApi.program(id);
      if (!mounted) return;
      _createdProgramId = id;
      _createdTitle = program['title']?.toString() ?? (_ownMode ? 'Своя тренировка' : 'Программа');
      _syncFromProgram(program);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  void _syncFromProgram(Map<String, dynamic> program) {
    final weeks = (program['weeks'] is List)
        ? (program['weeks'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final days = (program['days'] is List)
        ? (program['days'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _days = days;
      _status = program['status']?.toString() ?? _status;
      _createdTitle = program['title']?.toString() ?? _createdTitle;
      final cover = FitMedia.url(program['cover_url']?.toString());
      if (cover != null && cover.isNotEmpty) {
        _coverUrl = cover;
        _coverPath = null;
        _coverName = null;
      }
      if (_activeWeekId == null && weeks.isNotEmpty) {
        _activeWeekId = int.tryParse('${weeks.first['id']}');
      } else if (_activeWeekId != null &&
          weeks.every((w) => int.tryParse('${w['id']}') != _activeWeekId) &&
          weeks.isNotEmpty) {
        _activeWeekId = int.tryParse('${weeks.first['id']}');
      }
    });
  }

  Future<void> _pickCover() async {
    late final PreparedUploadImage prepared;
    try {
      final picked = await pickPreparedImage();
      if (picked == null) return;
      prepared = picked;
    } catch (e) {
      Toast.error(e is FormatException ? e.message : FitApi.messageOf(e));
      return;
    }
    setState(() {
      _coverPath = prepared.path;
      _coverName = prepared.filename;
    });
    final programId = _createdProgramId;
    if (programId != null) {
      setState(() => _busy = true);
      try {
        final program = await FitApi.uploadProgramCover(programId, prepared.path);
        if (mounted) _syncFromProgram(program);
      } catch (e) {
        if (mounted) Toast.error(FitApi.messageOf(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _clearCoverLocal() {
    setState(() {
      _coverPath = null;
      _coverName = null;
    });
  }

  Future<void> _createProgram() async {
    if (_titleCtrl.text.trim().isEmpty) {
      Toast.info('Укажите название');
      return;
    }
    if (!_hasCover) {
      Toast.info('Добавьте обложку');
      return;
    }
    if (!_formValid) return;
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        'duration_weeks': 4,
        'workouts_per_week': 3,
        'status': 'draft',
        'source': _ownMode ? 'user_copy' : 'trainer',
      };
      final result = await FitApi.createProgram(body);
      if (!mounted) return;
      final id = int.tryParse('${result['id']}') ?? 0;
      if (id <= 0) throw Exception('Не удалось создать');

      Map<String, dynamic> program = Map<String, dynamic>.from(result);
      final coverPath = _coverPath;
      if (coverPath != null && coverPath.isNotEmpty) {
        program = await FitApi.uploadProgramCover(id, coverPath);
      }
      int? weekId;
      try {
        program = await FitApi.addProgramWeek(id, title: 'Неделя 1', weekIndex: 1, isPreview: true);
        final weeks = program['weeks'];
        if (weeks is List && weeks.isNotEmpty) {
          weekId = int.tryParse('${(weeks.first as Map)['id']}');
        }
      } catch (_) {}

      // Bootstrap first complex and open edit-day (same UX as editing).
      Map<String, dynamic>? firstDay;
      try {
        program = await FitApi.addProgramDay(id, {
          'title': 'Комплекс 1',
          'week_id': ?weekId,
        });
        final days = program['days'];
        if (days is List && days.isNotEmpty) {
          firstDay = Map<String, dynamic>.from(days.last as Map);
        }
      } catch (_) {}

      if (!mounted) return;
      _createdProgramId = id;
      _activeWeekId = weekId;
      _syncFromProgram(program);

      if (firstDay != null) {
        await _openDayEditor(firstDay);
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openDayEditor(Map<String, dynamic> day) async {
    final programId = _createdProgramId;
    if (programId == null) return;
    final dayId = int.tryParse('${day['id']}') ?? 0;
    final fresh = _days.cast<Map<String, dynamic>?>().firstWhere(
          (d) => int.tryParse('${d?['id']}') == dayId,
          orElse: () => day,
        ) ??
        day;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProgramDayPage(programId: programId, day: fresh),
      ),
    );
    if (changed == true && mounted) {
      try {
        final program = await FitApi.program(programId);
        if (mounted) _syncFromProgram(program);
      } catch (e) {
        if (mounted) Toast.error(FitApi.messageOf(e));
      }
    }
  }

  Future<void> _addDay() async {
    final programId = _createdProgramId;
    if (programId == null) return;
    setState(() => _addingDay = true);
    try {
      final program = await FitApi.addProgramDay(programId, {
        'title': 'Комплекс ${_days.length + 1}',
        'week_id': ?_activeWeekId,
      });
      if (!mounted) return;
      _syncFromProgram(program);
      final days = program['days'];
      Map<String, dynamic>? created;
      if (days is List && days.isNotEmpty) {
        created = Map<String, dynamic>.from(days.last as Map);
      }
      if (created != null) await _openDayEditor(created);
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _addingDay = false);
    }
  }

  Future<void> _deleteDay(Map<String, dynamic> day) async {
    final programId = _createdProgramId;
    final dayId = int.tryParse('${day['id']}') ?? 0;
    if (programId == null || dayId <= 0) return;
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
      final program = await FitApi.deleteProgramDay(programId, dayId);
      if (mounted) {
        _syncFromProgram(program);
        Toast.success('Комплекс удалён');
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _exerciseCount {
    var n = 0;
    for (final day in _days) {
      final ex = day['exercises'];
      if (ex is List) n += ex.length;
    }
    return n;
  }

  bool get _hasMinExercises => _exerciseCount >= 1;

  Future<void> _saveAndClose() async {
    if (!_hasCover) {
      Toast.info('Добавьте обложку');
      return;
    }
    if (!_hasMinExercises) {
      Toast.info('Добавьте хотя бы одно упражнение');
      return;
    }
    final programId = _createdProgramId;
    // Own workout = private save only (no publish). Trainer courses still publish.
    if (!_ownMode && _isTrainer && programId != null && _status != 'published') {
      setState(() => _busy = true);
      try {
        final program = await FitApi.submitProgram(programId);
        if (mounted) _syncFromProgram(program);
        if (mounted) Toast.success('Программа опубликована');
      } catch (e) {
        if (mounted) Toast.error(FitApi.messageOf(e));
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      Toast.success(_ownMode ? 'Тренировка сохранена' : 'Сохранено');
    }
    if (mounted) context.pop(true);
  }

  int? _firstStartableDayId() {
    for (final day in _days) {
      final id = int.tryParse('${day['id']}') ?? 0;
      if (id <= 0) continue;
      final exercises = day['exercises'];
      if (exercises is List && exercises.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _startOwnWorkout() async {
    final dayId = _firstStartableDayId();
    if (dayId == null) {
      Toast.info('Добавьте хотя бы одно упражнение');
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
        Toast.error('Не удалось начать тренировку');
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dayMeta(Map<String, dynamic> day) {
    final exercises = day['exercises'];
    final n = exercises is List ? exercises.length : 0;
    if (n == 0) return 'Нет упражнений';
    if (n == 1) return '1 упражнение';
    if (n >= 2 && n <= 4) return '$n упражнения';
    return '$n упражнений';
  }

  @override
  Widget build(BuildContext context) {
    final topTitle = _createdProgramId != null
        ? (_ownMode ? 'Своя тренировка' : 'Программа')
        : (_ownMode ? 'Своя тренировка' : 'Создать программу');

    return FitScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: HubBackTitle(title: topTitle),
          ),
          Expanded(
            child: _loadingExisting
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _createdProgramId == null
                    ? _buildForm()
                    : _buildDaysList(),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              HubCard(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: SvgPicture.asset(
                            'assets/icons/trainer/stretching.svg',
                            width: 22,
                            height: 22,
                            colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _ownMode ? 'Новая тренировка' : 'Новая программа',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ownMode
                          ? 'Укажите название — дальше добавите упражнения в комплекс'
                          : 'Укажите название — дальше соберёте комплексы с упражнениями',
                      style: const TextStyle(color: AppColors.fitGrey, fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Обложка *', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
              const SizedBox(height: 8),
              _CoverPicker(
                localPath: _coverPath,
                networkUrl: _coverPath == null ? _coverUrl : null,
                fileName: _coverName,
                onPick: _pickCover,
                onClear: _coverPath != null ? _clearCoverLocal : null,
              ),
              const SizedBox(height: 16),
              const Text('Название *', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
              const SizedBox(height: 8),
              _TitleField(
                controller: _titleCtrl,
                hint: _ownMode ? 'Например, Полное тело' : 'Например, Жим / ноги',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              const Text('Описание', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
              const SizedBox(height: 8),
              CustomPaint(
                painter: _DashedBorderPainter(color: const Color(0xFF4A4A4A), radius: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: const Color(0xFF1A1A1A),
                    child: TextField(
                      controller: _descCtrl,
                      maxLines: 5,
                      minLines: 3,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                      cursorColor: AppColors.accent,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        contentPadding: const EdgeInsets.all(14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: _ownMode ? 'Что включает тренировка…' : 'Что включает программа…',
                        hintStyle: const TextStyle(color: AppColors.fitGrey),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: FitAccentButton(
            title: 'Далее',
            loading: _saving,
            onPressed: _formValid ? _createProgram : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDaysList() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Own workouts are private — no draft/publish badges.
    final statusLabel = _ownMode
        ? ''
        : switch (_status) {
            'pending_review' => 'На модерации',
            'published' => 'Опубликован',
            'rejected' => 'Отклонён',
            _ => 'Черновик',
          };
    final title = _createdTitle.isNotEmpty ? _createdTitle : (_ownMode ? 'Своя тренировка' : 'Программа');

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              _ProgramHero(
                title: title,
                statusLabel: statusLabel,
                localCoverPath: _coverPath,
                coverUrl: _coverUrl,
                busy: _busy,
                onChangeCover: _pickCover,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Комплексы',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: (_addingDay || _busy) ? null : _addDay,
                    icon: Icon(
                      Icons.add_rounded,
                      color: (_addingDay || _busy) ? AppColors.fitGrey : AppColors.accent,
                      size: 20,
                    ),
                    label: Text(
                      _addingDay ? '…' : 'Добавить',
                      style: TextStyle(
                        color: (_addingDay || _busy) ? AppColors.fitGrey : AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Откройте комплекс и добавьте упражнения',
                style: TextStyle(color: AppColors.fitGrey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (_days.isEmpty)
                _EmptyDaysCard(
                  onAdd: (_addingDay || _busy) ? null : _addDay,
                  loading: _addingDay,
                )
              else
                for (var i = 0; i < _days.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _DayRow(
                    index: i + 1,
                    title: _days[i]['title']?.toString() ?? 'Комплекс',
                    meta: _dayMeta(_days[i]),
                    onTap: _busy ? null : () => _openDayEditor(_days[i]),
                    onDelete: _busy ? null : () => _deleteDay(_days[i]),
                  ),
                ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: Column(
            children: [
              if (_ownMode) ...[
                ValueListenableBuilder<int?>(
                  valueListenable: WorkoutOfflineQueue.I.activeSession,
                  builder: (context, activeId, _) {
                    final resume = activeId != null && activeId > 0;
                    return FitAccentButton(
                      title: resume ? 'Продолжить тренировку' : 'Начать тренировку',
                      loading: _busy,
                      onPressed: _busy ? null : _startOwnWorkout,
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],
              if (_isTrainer && _status != 'published')
                FitAccentButton(
                  title: 'Опубликовать',
                  loading: _busy,
                  onPressed: _busy ? null : _saveAndClose,
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _saveAndClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF222222),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Сохранить и закрыть', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgramHero extends StatelessWidget {
  const _ProgramHero({
    required this.title,
    required this.statusLabel,
    required this.onChangeCover,
    this.localCoverPath,
    this.coverUrl,
    this.busy = false,
  });

  final String title;
  final String statusLabel;
  final String? localCoverPath;
  final String? coverUrl;
  final bool busy;
  final VoidCallback onChangeCover;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 168,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (localCoverPath != null)
              Image.file(File(localCoverPath!), fit: BoxFit.cover, errorBuilder: (_, _, _) => _bg())
            else if (coverUrl != null && coverUrl!.isNotEmpty)
              Image.network(coverUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _bg())
            else
              _bg(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xE6000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (statusLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: busy ? null : onChangeCover,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0x66000000),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/trainer/camera.svg',
                              width: 14,
                              height: 14,
                              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              (localCoverPath != null || (coverUrl != null && coverUrl!.isNotEmpty))
                                  ? 'Сменить'
                                  : 'Обложка',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bg() {
    return const ColoredBox(
      color: Color(0xFF232323),
      child: Center(
        child: Icon(Icons.image_outlined, color: AppColors.fitGrey, size: 36),
      ),
    );
  }
}

class _EmptyDaysCard extends StatelessWidget {
  const _EmptyDaysCard({this.onAdd, this.loading = false});

  final VoidCallback? onAdd;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF323232)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/icons/trainer/stretching.svg',
              width: 28,
              height: 28,
              colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Пока нет комплексов',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Создайте комплекс и добавьте упражнения',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.fitGrey, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppColors.fitMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Добавить комплекс', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.onPick,
    this.localPath,
    this.networkUrl,
    this.fileName,
    this.onClear,
  });

  final String? localPath;
  final String? networkUrl;
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasImage = localPath != null || (networkUrl != null && networkUrl!.isNotEmpty);
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 72,
                  child: localPath != null
                      ? Image.file(File(localPath!), fit: BoxFit.cover, errorBuilder: (_, _, _) => _empty())
                      : networkUrl != null
                          ? Image.network(networkUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _empty())
                          : _empty(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasImage ? 'Обложка выбрана' : 'Добавить обложку',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasImage
                          ? (fileName?.trim().isNotEmpty == true ? fileName! : 'JPG, PNG, WEBP')
                          : 'JPG, PNG, WEBP или GIF',
                      style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          hasImage ? 'Сменить' : 'Выбрать',
                          style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        if (onClear != null) ...[
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: onClear,
                            child: const Text(
                              'Убрать',
                              style: TextStyle(color: Color(0xFFFD6565), fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return ColoredBox(
      color: const Color(0xFF232323),
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/trainer/camera.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(AppColors.fitGrey, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _TitleField extends StatelessWidget {
  const _TitleField({
    required this.controller,
    this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;

  static const _radius = BorderRadius.all(Radius.circular(14));
  static const _fill = Color(0xFF1A1A1A);
  static const _line = Color(0xFF3A3A3A);

  @override
  Widget build(BuildContext context) {
    // Use OutlineInputBorder + ClipRRect so iOS autofill/focus layer stays inside radius.
    return ClipRRect(
      borderRadius: _radius,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        cursorColor: AppColors.accent,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          filled: true,
          fillColor: _fill,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14, fontWeight: FontWeight.w400),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: _radius,
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: _radius,
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: _radius,
            borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

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
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.index,
    required this.title,
    required this.meta,
    this.onTap,
    this.onDelete,
  });

  final int index;
  final String title;
  final String meta;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF232323),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF323232)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3A3A3A)),
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(meta, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  icon: SvgPicture.asset(
                    'assets/icons/program/delete.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(Color(0xFFFD6565), BlendMode.srcIn),
                  ),
                ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.fitGrey, size: 22),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
