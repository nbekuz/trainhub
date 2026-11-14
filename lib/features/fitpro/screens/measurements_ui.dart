import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_cache.dart';
import 'package:trainhub/features/fitpro/session.dart';

/// Full-screen dim + blur behind a bottom sheet (Figma: #232323 @ 50% + blur).
Widget _blurredSheetBarrier({required BuildContext context, required Widget child}) {
  return SizedBox(
    height: MediaQuery.sizeOf(context).height,
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const ColoredBox(color: Color(0x80232323)),
            ),
          ),
        ),
        Align(alignment: Alignment.bottomCenter, child: child),
      ],
    ),
  );
}

const _girthFields = <({String key, String label, String asset, double min, double max})>[
  (key: 'neck_cm', label: 'Шея', asset: 'assets/icons/main-params/neck.svg', min: 25, max: 55),
  (key: 'shoulders_cm', label: 'Плечи', asset: 'assets/icons/main-params/shoulders.svg', min: 70, max: 160),
  (key: 'chest_cm', label: 'Грудь', asset: 'assets/icons/main-params/chest.svg', min: 70, max: 150),
  (key: 'waist_cm', label: 'Талия', asset: 'assets/icons/main-params/waist.svg', min: 50, max: 140),
  (key: 'hips_cm', label: 'Ягодицы', asset: 'assets/icons/main-params/glutes.svg', min: 70, max: 150),
  (key: 'thigh_cm', label: 'Бедра', asset: 'assets/icons/main-params/thighs.svg', min: 35, max: 90),
  (key: 'arm_right_cm', label: 'Бицепс (правый)', asset: 'assets/icons/main-params/right_biceps.svg', min: 18, max: 55),
  (key: 'arm_left_cm', label: 'Бицепс (левый)', asset: 'assets/icons/main-params/left_biceps.svg', min: 18, max: 55),
  (key: 'forearm_cm', label: 'Предплечье', asset: 'assets/icons/main-params/forearm.svg', min: 15, max: 45),
];

/// Composition metrics that feed Progress charts (fat / muscle / water).
const _compositionFields = <({String key, String label, String asset, String unit, double min, double max, double step})>[
  (
    key: 'body_fat_pct',
    label: 'Процент жира',
    asset: 'assets/icons/main-params/oil.svg',
    unit: '%',
    min: 3,
    max: 50,
    step: 0.1,
  ),
  (
    key: 'muscle_mass_kg',
    label: 'Мышечная масса',
    asset: 'assets/icons/main-params/bicep.svg',
    unit: 'кг',
    min: 20,
    max: 90,
    step: 0.1,
  ),
  (
    key: 'water_pct',
    label: 'Вода',
    asset: 'assets/icons/main-params/progres.svg',
    unit: '%',
    min: 30,
    max: 80,
    step: 0.1,
  ),
];

/// Label and unit for a `body_measurements` column, in the order shown in «Замеры».
final measurementFields = <({String key, String label, String unit})>[
  (key: 'weight_kg', label: 'Вес', unit: 'кг'),
  for (final f in _compositionFields) (key: f.key, label: f.label, unit: f.unit),
  for (final f in _girthFields) (key: f.key, label: f.label, unit: 'см'),
];

String _formatCm(num? value) {
  if (value == null) return '—';
  return value.toStringAsFixed(1).replaceAll('.', ',');
}

String _formatKg(num? value) {
  if (value == null) return '—';
  return '${value.toStringAsFixed(1).replaceAll('.', ',')} кг';
}

int? _ageFromBirth(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final birth = DateTime.tryParse(raw);
  if (birth == null) return null;
  final now = DateTime.now();
  var age = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
  return age < 0 ? null : age;
}

String _genderLabel(String? raw) {
  final value = (raw ?? '').toLowerCase();
  if (value == 'male' || value == 'm' || value == 'мужской') return 'Мужской';
  if (value == 'female' || value == 'f' || value == 'женский') return 'Женский';
  return raw?.isNotEmpty == true ? raw! : '—';
}

num? _numOf(dynamic raw) {
  if (raw == null) return null;
  return num.tryParse('$raw'.replaceAll(',', '.').replaceAll(' ', ''));
}

/// Profile tab «Замеры» — основные параметры + обхваты тела.
class MeasuresTab extends ConsumerStatefulWidget {
  const MeasuresTab({super.key, this.home = const {}});

  final Map<String, dynamic> home;

  @override
  ConsumerState<MeasuresTab> createState() => _MeasuresTabState();
}

class _MeasuresTabState extends ConsumerState<MeasuresTab> {
  Map<String, dynamic> _latest = const {};
  Map<String, DateTime> _fieldDates = const {};
  DateTime? _latestAt;
  StreamSubscription<String>? _cacheSub;

  static const _measureKeys = <String>[
    'weight_kg',
    'neck_cm',
    'shoulders_cm',
    'chest_cm',
    'waist_cm',
    'hips_cm',
    'thigh_cm',
    'arm_right_cm',
    'arm_left_cm',
    'forearm_cm',
    'back_cm',
    'calf_cm',
    'arm_cm',
    'body_fat_pct',
    'muscle_mass_kg',
    'water_pct',
  ];

  @override
  void initState() {
    super.initState();
    final cached = FitCache.I.peek<List<Map<String, dynamic>>>('measurements');
    if (cached != null) _applyItems(cached);
    _cacheSub = FitCache.I.updates.listen((key) {
      if (key != 'measurements' || !mounted) return;
      final next = FitCache.I.peek<List<Map<String, dynamic>>>('measurements');
      if (next != null) _applyItems(next);
    });
    _load(silent: true);
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  void _applyItems(List<Map<String, dynamic>> items) {
    // Each POST saves one field as a new row — merge latest non-null per key.
    final merged = <String, dynamic>{};
    final dates = <String, DateTime>{};
    DateTime? at;

    final sorted = [...items];
    sorted.sort((a, b) {
      final aAt = DateTime.tryParse(a['recorded_at']?.toString() ?? a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = DateTime.tryParse(b['recorded_at']?.toString() ?? b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });

    for (final item in sorted) {
      final stamp = DateTime.tryParse(item['recorded_at']?.toString() ?? item['created_at']?.toString() ?? '')?.toLocal();
      if (stamp != null && (at == null || stamp.isAfter(at))) at = stamp;
      for (final key in _measureKeys) {
        if (merged.containsKey(key)) continue;
        final value = _numOf(item[key]);
        if (value == null) continue;
        merged[key] = value;
        if (stamp != null) dates[key] = stamp;
      }
    }

    setState(() {
      _latest = merged;
      _fieldDates = dates;
      _latestAt = at;
    });
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await FitApi.clientMeasurements(force: true);
      if (!mounted) return;
      _applyItems(items);
    } catch (error) {
      if (!mounted || silent) return;
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _saveField(String key, double value) async {
    try {
      await FitApi.createMeasurement({key: value});
      Toast.success('Замер сохранён');
      await _load(silent: false);
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _editGirth(({String key, String label, String asset, double min, double max}) field) async {
    final current = _numOf(_latest[field.key])?.toDouble();
    final saved = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => _blurredSheetBarrier(
        context: context,
        child: MeasureEditSheet(
          label: field.label,
          asset: field.asset,
          unit: 'см',
          min: field.min,
          max: field.max,
          step: 0.5,
          initial: current ?? ((field.min + field.max) / 2),
          lastValue: current,
          lastDate: _fieldDates[field.key] ?? _latestAt,
        ),
      ),
    );
    if (saved != null) await _saveField(field.key, saved);
  }

  Future<double?> _promptNumberModal({
    required String title,
    required String hint,
    required String unit,
    double? current,
    double min = 1,
    double max = 300,
  }) {
    return showDialog<double>(
      context: context,
      builder: (context) => _NumberPromptDialog(
        title: title,
        hint: hint,
        unit: unit,
        current: current,
        min: min,
        max: max,
      ),
    );
  }

  Future<void> _editWeight() async {
    final current = (_numOf(_latest['weight_kg']) ?? _numOf(widget.home['weight_kg']))?.toDouble();
    final saved = await _promptNumberModal(
      title: 'Вес',
      hint: 'Например, 78,5',
      unit: 'кг',
      current: current,
      min: 30,
      max: 200,
    );
    if (saved != null) await _saveField('weight_kg', saved);
  }

  Future<void> _editHeight() async {
    final user = ref.read(fitSessionProvider).user;
    final current = (_numOf(user?.heightCm) ?? _numOf(widget.home['height_cm']))?.toDouble();
    final saved = await _promptNumberModal(
      title: 'Рост',
      hint: 'Например, 178',
      unit: 'см',
      current: current,
      min: 100,
      max: 250,
    );
    if (saved == null) return;
    try {
      final updated = await FitApi.patchMe(heightCm: saved.round());
      if (!mounted) return;
      ref.read(fitSessionProvider.notifier).signIn(updated);
      Toast.success('Рост сохранён');
      setState(() {});
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _editComposition(
    ({String key, String label, String asset, String unit, double min, double max, double step}) field,
  ) async {
    final current =
        (_numOf(_latest[field.key]) ?? _numOf(widget.home[field.key]))?.toDouble();
    final saved = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => _blurredSheetBarrier(
        context: context,
        child: MeasureEditSheet(
          label: field.label,
          asset: field.asset,
          unit: field.unit,
          min: field.min,
          max: field.max,
          step: field.step,
          initial: current ?? ((field.min + field.max) / 2),
          lastValue: current,
          lastDate: _fieldDates[field.key] ?? _latestAt,
        ),
      ),
    );
    if (saved != null) await _saveField(field.key, saved);
  }

  Future<void> _addAny() async {
    final missing = _girthFields.where((item) => _numOf(_latest[item.key]) == null).toList();
    if (missing.isEmpty) {
      Toast.info('Все обхваты уже добавлены');
      return;
    }
    final field = await showModalBottomSheet<({String key, String label, String asset, double min, double max})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => _blurredSheetBarrier(
        context: context,
        child: Material(
          color: const Color(0xFF1C1C1C),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Добавить замер', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                for (final item in missing)
                  ListTile(
                    leading: _ParamIcon(asset: item.asset, size: 28),
                    title: Text(item.label, style: const TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(context, item),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
    if (field != null) await _editGirth(field);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(fitSessionProvider).user;
    final weight = _numOf(_latest['weight_kg']) ?? _numOf(widget.home['weight_kg']);
    final height = _numOf(user?.heightCm) ?? _numOf(widget.home['height_cm']);
    final age = _ageFromBirth(user?.birthDate);
    final gender = _genderLabel(user?.gender ?? widget.home['gender']?.toString());
    final fat = _numOf(_latest['body_fat_pct']) ?? _numOf(widget.home['body_fat_pct']);
    final muscle = _numOf(_latest['muscle_mass_kg']) ?? _numOf(widget.home['muscle_mass_kg']);
    final water = _numOf(_latest['water_pct']) ?? _numOf(widget.home['water_pct']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MainParamsCard(
          gender: gender,
          weightLabel: weight == null ? '—' : _formatKg(weight),
          heightLabel: height == null ? '—' : '${height.round()} см',
          ageLabel: age == null ? '—' : '$age лет',
          onWeightTap: _editWeight,
          onHeightTap: _editHeight,
        ),
        const SizedBox(height: 18),
        _CompositionCard(
          fatLabel: fat == null ? '—' : '${_formatCm(fat)} %',
          muscleLabel: muscle == null ? '—' : _formatKg(muscle),
          waterLabel: water == null ? '—' : '${_formatCm(water)} %',
          onFatTap: () => _editComposition(_compositionFields[0]),
          onMuscleTap: () => _editComposition(_compositionFields[1]),
          onWaterTap: () => _editComposition(_compositionFields[2]),
        ),
        const SizedBox(height: 18),
        _GirthsCard(
          latest: _latest,
          onAdd: _addAny,
          onEdit: _editGirth,
        ),
      ],
    );
  }
}

abstract final class _MainParamAssets {
  static const gender = 'assets/icons/main-params/gender.svg';
  static const weight = 'assets/icons/main-params/weight.svg';
  static const height = 'assets/icons/main-params/heigth.svg';
  static const age = 'assets/icons/main-params/age.svg';
}

/// Outer #232323 + 2×2 inner tiles #292929 (Figma: Основные параметры).
class _MainParamsCard extends StatelessWidget {
  const _MainParamsCard({
    required this.gender,
    required this.weightLabel,
    required this.heightLabel,
    required this.ageLabel,
    required this.onWeightTap,
    required this.onHeightTap,
  });

  final String gender;
  final String weightLabel;
  final String heightLabel;
  final String ageLabel;
  final VoidCallback onWeightTap;
  final VoidCallback onHeightTap;

  static const _outerBg = Color(0xFF232323);
  static const _border = Color(0xFF323232);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Основные параметры',
            style: GoogleFonts.openSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Вес и рост можно изменить — нажмите на карточку',
            style: GoogleFonts.openSans(
              color: const Color(0xFFA0A0A0),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MainParamTile(
                    asset: _MainParamAssets.gender,
                    label: 'Пол',
                    value: gender,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onWeightTap,
                    child: _MainParamTile(
                      asset: _MainParamAssets.weight,
                      label: 'Вес',
                      value: weightLabel,
                      editable: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onHeightTap,
                    child: _MainParamTile(
                      asset: _MainParamAssets.height,
                      label: 'Рост',
                      value: heightLabel,
                      editable: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MainParamTile(
                    asset: _MainParamAssets.age,
                    label: 'Возраст',
                    value: ageLabel,
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

/// Fat / muscle / water — same createMeasurement path as weight (feeds Progress).
class _CompositionCard extends StatelessWidget {
  const _CompositionCard({
    required this.fatLabel,
    required this.muscleLabel,
    required this.waterLabel,
    required this.onFatTap,
    required this.onMuscleTap,
    required this.onWaterTap,
  });

  final String fatLabel;
  final String muscleLabel;
  final String waterLabel;
  final VoidCallback onFatTap;
  final VoidCallback onMuscleTap;
  final VoidCallback onWaterTap;

  static const _outerBg = Color(0xFF232323);
  static const _border = Color(0xFF323232);
  static const _label = Color(0xFFA0A0A0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Состав тела',
            style: GoogleFonts.openSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Нажмите, чтобы добавить замер — данные попадут в Прогресс',
            style: GoogleFonts.openSans(
              color: _label,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onFatTap,
                  child: _MainParamTile(
                    asset: 'assets/icons/main-params/oil.svg',
                    label: 'Жир',
                    value: fatLabel,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onMuscleTap,
                  child: _MainParamTile(
                    asset: 'assets/icons/main-params/bicep.svg',
                    label: 'Мышцы',
                    value: muscleLabel,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onWaterTap,
            child: _MainParamTile(
              asset: 'assets/icons/main-params/progres.svg',
              label: 'Вода',
              value: waterLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Outer card (header) + inner card (measurement rows).
/// Inner card: 0 outer margin — flush to parent left/right/bottom.
class _GirthsCard extends StatelessWidget {
  const _GirthsCard({
    required this.latest,
    required this.onAdd,
    required this.onEdit,
  });

  final Map<String, dynamic> latest;
  final VoidCallback onAdd;
  final Future<void> Function(({String key, String label, String asset, double min, double max})) onEdit;

  static const _lime = Color(0xFFC4F52B);
  static const _outerBg = Color(0xFF232323);
  static const _innerBg = Color(0xFF292929);
  static const _border = Color(0xFF3A3A3A);
  static const _divider = Color(0xFF353535);
  static const _label = Color(0xFFA0A0A0);

  @override
  Widget build(BuildContext context) {
    final added = _girthFields.where((item) => _numOf(latest[item.key]) != null).toList();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — outer card ichida, inner card tashqarisida
          Padding(
            padding: EdgeInsets.fromLTRB(28, 28, 28, added.isEmpty ? 28 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Обхваты тела',
                        style: GoogleFonts.openSans(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Все параметры в см',
                        style: GoogleFonts.openSans(
                          color: _label,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _border, width: 1.5),
                    ),
                    child: const Icon(Icons.add, color: _lime, size: 24),
                  ),
                ),
              ],
            ),
          ),
          // Inner card — faqat qo‘shilgan o‘lchovlar
          if (added.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 16),
              decoration: BoxDecoration(
                color: _innerBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(29),
                  bottomRight: Radius.circular(29),
                ),
                border: Border.all(color: _border, width: 1),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < added.length; i++) ...[
                    if (i > 0) const Divider(height: 1, thickness: 1, color: _divider),
                    _GirthRow(
                      asset: added[i].asset,
                      label: added[i].label,
                      value: _formatCm(_numOf(latest[added[i].key])),
                      onEdit: () => onEdit(added[i]),
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

class _MainParamTile extends StatelessWidget {
  const _MainParamTile({
    required this.asset,
    required this.label,
    required this.value,
    this.editable = false,
  });

  final String asset;
  final String label;
  final String value;
  final bool editable;

  static const _tileBg = Color(0xFF232323);
  static const _valueBg = Color(0xFF292929);
  static const _border = Color(0xFF323232);
  static const _labelColor = Color(0xFFA0A0A0);
  static const _lime = Color(0xFFC4F52B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _tileBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: editable ? _lime.withValues(alpha: 0.45) : _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _ParamIcon(asset: asset, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.openSans(
                    color: _labelColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (editable) const _ParamIcon(asset: 'assets/icons/main-params/pen.svg', size: 16),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _valueBg,
              borderRadius: BorderRadius.circular(12),
              border: editable ? Border.all(color: const Color(0xFF3A3A3A)) : null,
            ),
            child: Text(
              value,
              style: GoogleFonts.openSans(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GirthRow extends StatelessWidget {
  const _GirthRow({
    required this.asset,
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String asset;
  final String label;
  final String value;
  final VoidCallback onEdit;

  static const _label = Color(0xFFA0A0A0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ParamIcon(asset: asset, size: 27),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.openSans(
                color: _label,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: GoogleFonts.openSans(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onEdit,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: _ParamIcon(asset: 'assets/icons/main-params/pen.svg', size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamIcon extends StatelessWidget {
  const _ParamIcon({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        allowDrawingOutsideViewBox: true,
        placeholderBuilder: (_) => Icon(Icons.accessibility_new, size: size * 0.85, color: AppColors.fitGrey),
        errorBuilder: (_, error, stack) => Icon(Icons.accessibility_new, size: size * 0.85, color: AppColors.fitGrey),
      ),
    );
  }
}

class MeasureEditSheet extends StatefulWidget {
  const MeasureEditSheet({
    super.key,
    required this.label,
    required this.asset,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.initial,
    this.lastValue,
    this.lastDate,
  });

  final String label;
  final String asset;
  final String unit;
  final double min;
  final double max;
  final double step;
  final double initial;
  final double? lastValue;
  final DateTime? lastDate;

  @override
  State<MeasureEditSheet> createState() => _MeasureEditSheetState();
}

class _MeasureEditSheetState extends State<MeasureEditSheet> {
  late double _value;
  late final ScrollController _scroll;
  static const _itemWidth = 40.0;
  static const _dune = Color(0xFF323232);

  List<double> get _ticks {
    final out = <double>[];
    for (var v = widget.min; v <= widget.max + 0.001; v += widget.step) {
      out.add(double.parse(v.toStringAsFixed(1)));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _value = _snap(widget.initial);
    final index = ((_value - widget.min) / widget.step).round().clamp(0, _ticks.length - 1);
    _scroll = ScrollController(initialScrollOffset: index * _itemWidth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(index * _itemWidth);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _snap(double raw) {
    final steps = ((raw - widget.min) / widget.step).round();
    return (widget.min + steps * widget.step).clamp(widget.min, widget.max);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final index = (_scroll.offset / _itemWidth).round().clamp(0, _ticks.length - 1);
    final next = _ticks[index];
    if (next != _value) setState(() => _value = next);
  }

  Color _tickColor(int distance) {
    return switch (distance) {
      0 => AppColors.accent,
      1 => const Color(0xFF979797),
      2 => const Color(0xFF4A4A4A),
      _ => const Color(0xFF2D2D35),
    };
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return '—';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  Widget _tickMark({required Color color, required bool selected}) {
    return Container(
      width: selected ? 2 : 1,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
        boxShadow: selected
            ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), blurRadius: 8)]
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.lastValue;
    final date = widget.lastDate;
    final sidePad = (MediaQuery.sizeOf(context).width - 32 - _itemWidth) / 2;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF232323),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _dune)),
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 5,
            decoration: BoxDecoration(color: const Color(0xFF4A4A4A), borderRadius: BorderRadius.circular(100)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Изменить замер',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _ParamIcon(asset: widget.asset, size: 90),
          Text(widget.label, style: const TextStyle(color: Color(0xFF979797), fontSize: 16)),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_formatCm(_value)} ',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: widget.unit,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
                  _onScroll();
                }
                if (notification is ScrollEndNotification) {
                  final index = (_scroll.offset / _itemWidth).round().clamp(0, _ticks.length - 1);
                  _scroll.animateTo(
                    index * _itemWidth,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                  );
                }
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemExtent: _itemWidth,
                padding: EdgeInsets.symmetric(horizontal: sidePad),
                itemCount: _ticks.length,
                itemBuilder: (context, index) {
                  final tick = _ticks[index];
                  final selectedIndex = ((_value - widget.min) / widget.step).round().clamp(0, _ticks.length - 1);
                  final distance = (index - selectedIndex).abs();
                  final selected = distance == 0;
                  final color = _tickColor(distance);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _tickMark(color: color, selected: selected),
                      const SizedBox(height: 4),
                      Text(
                        tick.toStringAsFixed(1).replaceAll('.', ','),
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          height: 1.1,
                          fontWeight: FontWeight.w400,
                          shadows: selected
                              ? [Shadow(color: AppColors.accent.withValues(alpha: 0.8), blurRadius: 12)]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _tickMark(color: color, selected: selected),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            last == null ? 'Последний размер: —' : 'Последний размер: ${_formatCm(last)} ${widget.unit}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF979797), fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Дата: ${_dateLabel(date)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF979797), fontSize: 14),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: _dune),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _value),
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
    );
  }
}

class _NumberPromptDialog extends StatefulWidget {
  const _NumberPromptDialog({
    required this.title,
    required this.hint,
    required this.unit,
    required this.min,
    required this.max,
    this.current,
  });

  final String title;
  final String hint;
  final String unit;
  final double? current;
  final double min;
  final double max;

  @override
  State<_NumberPromptDialog> createState() => _NumberPromptDialogState();
}

class _NumberPromptDialogState extends State<_NumberPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _controller = TextEditingController(
      text: current == null
          ? ''
          : current.toStringAsFixed(current == current.roundToDouble() ? 0 : 1).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (n == null || n < widget.min || n > widget.max) {
      Toast.info('Введите значение от ${widget.min} до ${widget.max}');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF232323),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF323232)),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFF979797), fontWeight: FontWeight.w400),
          suffixText: widget.unit,
          suffixStyle: const TextStyle(color: Color(0xFF979797), fontSize: 16),
          filled: true,
          fillColor: const Color(0xFF292929),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF323232)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF323232)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: AppColors.accent)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Сохранить', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
