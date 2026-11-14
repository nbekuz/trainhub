import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/screens/client_workouts_tab.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';

const _lime = Color(0xFFC7F137);
const _card = Color(0xFF232323);
const _border = Color(0xFF323232);
const _label = Color(0xFF979797);
const _listBg = Color(0xFF292929);
const _cell = Color(0xFF242424);
const _prGreen = Color(0xFF37F184);
const _prRed = Color(0xFFFD6565);

/// Client workout history list + detail (§26) with filter/sort.
class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key});

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  int _refreshGen = 0;

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onRefresh: () async {
        setState(() => _refreshGen++);
        // Allow the remounted tab a moment to start its GET.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      child: ListView(
        physics: fitAlwaysScroll,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const HubBackTitle(title: 'История тренировок'),
          const SizedBox(height: 8),
          ClientWorkoutsTab(key: ValueKey('history-$_refreshGen')),
        ],
      ),
    );
  }
}

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.sessionId, this.clientId});

  final int sessionId;

  /// Trainer opened a client's history: show only that client's part of a group workout.
  final int? clientId;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  Map<String, dynamic> _session = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final showSpinner = _session.isEmpty;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      Map<String, dynamic> data;
      if (widget.clientId != null) {
        data = await FitApi.session(widget.sessionId, clientId: widget.clientId);
      } else {
        try {
          data = await FitApi.clientSession(widget.sessionId);
        } catch (_) {
          data = await FitApi.session(widget.sessionId);
        }
      }
      if (!mounted) return;
      setState(() {
        _session = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(e));
    }
  }

  /// Group workout: exercises under each participant's name; null when only one person trained.
  List<({String name, List<Map<String, dynamic>> exercises})>? _byClient(List<Map<String, dynamic>> exercises) {
    final owners = exercises.map((ex) => ex['client_id']?.toString()).whereType<String>().toSet();
    if (owners.length < 2) return null;
    final clients = _session['clients'] is List ? (_session['clients'] as List).whereType<Map>().toList() : const [];
    final shared = exercises.where((ex) => ex['client_id'] == null).toList();
    return [
      if (shared.isNotEmpty) (name: 'Все', exercises: shared),
      for (final c in clients)
        if (owners.contains('${c['id']}'))
          (
            name: '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim(),
            exercises: exercises.where((ex) => '${ex['client_id']}' == '${c['id']}').toList(),
          ),
    ];
  }

  String _detailTitle() {
    final n = int.tryParse('${_session['session_number'] ?? _session['index'] ?? _session['number'] ?? ''}');
    // Figma always uses «Тренировка #N», never kind label like «Силовая».
    if (n != null && n > 0) return 'Тренировка #$n';
    return 'Тренировка #${widget.sessionId}';
  }

  @override
  Widget build(BuildContext context) {
    final clientId = widget.clientId;
    final exercises = (_session['exercises'] is List
            ? (_session['exercises'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[])
        .where((ex) => clientId == null || ex['client_id'] == null || '${ex['client_id']}' == '$clientId')
        .toList();
    final sections = clientId == null ? _byClient(exercises) : null;
    final muscles = <String>{
      for (final ex in exercises)
        if (ex['primary_muscle'] != null) FitLabels.muscle(ex['primary_muscle']?.toString()),
      for (final m in (_session['focus_muscles'] is List ? _session['focus_muscles'] as List : const []))
        FitLabels.muscle(m?.toString()),
    }.where((e) => e.isNotEmpty).take(4).toList();
    if (muscles.isEmpty) {
      final kinds = _session['kinds'];
      if (kinds is List) {
        for (final k in kinds.take(2)) {
          final label = FitLabels.kind(k?.toString());
          if (label.isNotEmpty) muscles.add(label);
        }
      }
    }
    final minutes = ((int.tryParse('${_session['duration_sec']}') ?? 0) / 60).round();
    final when = DateHelper.parseLocal('${_session['finished_at'] ?? _session['started_at'] ?? _session['created_at'] ?? ''}');
    final dateLabel = when == null ? '—' : DateHelper.formatRuDate(when).replaceAll(' г.', '');
    final localSets =
        exercises.fold<int>(0, (sum, ex) => sum + ((ex['sets'] is List) ? (ex['sets'] as List).length : 0));
    final setsCount = clientId != null ? localSets : _session['sets_count'] ?? localSets;
    final trainer = _session['trainer_name']?.toString().trim();
    final trainerShort = (trainer == null || trainer.isEmpty)
        ? '—'
        : trainer.split(RegExp(r'\s+')).first;
    final calories = _session['calories'];
    final caloriesText = calories == null || '$calories'.isEmpty || '$calories' == 'null'
        ? '—'
        : '$calories ккал';

    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onRefresh: _loading ? null : _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              physics: fitAlwaysScroll,
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                HubBackTitle(title: _detailTitle()),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < muscles.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _card,
                                  borderRadius: BorderRadius.circular(111),
                                  border: Border.all(color: _border),
                                ),
                                // Open Sans sits optically low — nudge + tight strut.
                                child: Transform.translate(
                                  offset: const Offset(0, -1),
                                  child: Text(
                                    muscles[i],
                                    textAlign: TextAlign.center,
                                    strutStyle: const StrutStyle(
                                      fontSize: 14,
                                      height: 1,
                                      forceStrutHeight: true,
                                    ),
                                    style: GoogleFonts.openSans(
                                      color: _lime,
                                      fontSize: 14,
                                      height: 1,
                                      fontWeight: FontWeight.w400,
                                    ).copyWith(
                                      leadingDistribution: TextLeadingDistribution.even,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style: GoogleFonts.openSans(color: _label, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Stats — Figma nested: outer #232323 → inner #292929 → tiles
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(0),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _listBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _DetailStatTile(
                              iconAsset: 'assets/icons/workouts/duration.svg',
                              label: 'Длительность',
                              value: formatWorkoutDuration(
                                int.tryParse('${_session['duration_sec']}') ?? minutes * 60,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _DetailStatTile(
                              iconAsset: 'assets/icons/workouts/sets-stat.svg',
                              label: 'Подходы',
                              value: '$setsCount',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _DetailStatTile(
                              iconAsset: 'assets/icons/workouts/calories.svg',
                              label: 'Калории',
                              value: caloriesText,
                            ),
                            const SizedBox(width: 8),
                            _DetailStatTile(
                              iconAsset: 'assets/icons/workouts/trainer.svg',
                              label: 'Тренер',
                              value: trainerShort,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Exercises — Figma 450:6307
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          'Упражнения',
                          style: GoogleFonts.openSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
                        child: exercises.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text('Нет упражнений', style: GoogleFonts.openSans(color: _label)),
                                ),
                              )
                            : sections != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (var s = 0; s < sections.length; s++) ...[
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(8, s == 0 ? 4 : 16, 8, 8),
                                          child: Text(
                                            sections[s].name,
                                            style: GoogleFonts.openSans(
                                              color: _lime,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        for (var i = 0; i < sections[s].exercises.length; i++) ...[
                                          if (i > 0) const SizedBox(height: 8),
                                          _ExerciseDetailCard(exercise: sections[s].exercises[i]),
                                        ],
                                      ],
                                    ],
                                  )
                                : Column(
                                    children: [
                                      for (var i = 0; i < exercises.length; i++) ...[
                                        if (i > 0) const SizedBox(height: 8),
                                        _ExerciseDetailCard(exercise: exercises[i]),
                                      ],
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

class _DetailStatTile extends StatelessWidget {
  const _DetailStatTile({
    required this.label,
    required this.value,
    required this.iconAsset,
  });

  final String label;
  final String value;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: SvgPicture.asset(
                    iconAsset,
                    width: 16,
                    height: 16,
                    fit: BoxFit.contain,
                    allowDrawingOutsideViewBox: false,
                    placeholderBuilder: (_) => const Icon(Icons.circle, size: 16, color: _lime),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.openSans(color: _label, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _listBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Text(
                value,
                style: GoogleFonts.openSans(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseDetailCard extends StatelessWidget {
  const _ExerciseDetailCard({required this.exercise});

  final Map<String, dynamic> exercise;

  @override
  Widget build(BuildContext context) {
    final sets = exercise['sets'] is List
        ? (exercise['sets'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final delta = double.tryParse('${exercise['weight_delta_kg']}'.replaceAll(',', '.'));
    final deltaColor = (delta ?? 0) >= 0 ? _prGreen : _prRed;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              exercise['name']?.toString() ?? 'Упражнение',
              style: GoogleFonts.openSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          // Figma: one #292929 container holding 3 columns
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _listBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SetColumn(
                    iconAsset: 'assets/icons/workouts/sets.svg',
                    label: 'Подход',
                    values: [
                      for (var i = 0; i < sets.length; i++) '${sets[i]['set_index'] ?? i + 1}',
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SetColumn(
                    iconAsset: 'assets/icons/workouts/weight-kg.svg',
                    label: 'Вес',
                    values: [
                      for (final s in sets) '${s['weight_kg'] ?? '—'} кг',
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SetColumn(
                    iconAsset: 'assets/icons/workouts/reps.svg',
                    label: 'Повторения',
                    values: [
                      for (final s in sets) '${s['reps'] ?? '—'}',
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (delta != null && delta != 0) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/icons/workouts/info.svg',
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(deltaColor, BlendMode.srcIn),
                    placeholderBuilder: (_) => Icon(Icons.info_outline, size: 16, color: deltaColor),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1).replaceAll('.', ',')} кг к прошлой тренировке',
                      style: GoogleFonts.openSans(color: deltaColor, fontSize: 13),
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
}

class _SetColumn extends StatelessWidget {
  const _SetColumn({
    required this.iconAsset,
    required this.label,
    required this.values,
  });

  final String iconAsset;
  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconAsset,
              width: 16,
              height: 16,
              placeholderBuilder: (_) => const Icon(Icons.circle, size: 14, color: _label),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.openSans(color: _label, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (values.isEmpty)
          const _ValueCell(text: '—')
        else
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ValueCell(text: values[i]),
          ],
      ],
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _cell,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        style: GoogleFonts.openSans(color: Colors.white, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }
}
