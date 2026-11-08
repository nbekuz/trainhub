import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/weight_dynamics_chart.dart';
import 'package:trainhub/routes/route_names.dart';

const _lime = Color(0xFFC4F52B);
const _up = Color(0xFFC4F52B);
const _down = Color(0xFFFF5C5C);
const _outerBg = Color(0xFF292929);
const _innerBg = Color(0xFF232323);
const _border = Color(0xFF323232);
const _label = Color(0xFFA0A0A0);

num? _numOf(dynamic raw) {
  if (raw == null) return null;
  return num.tryParse('$raw'.replaceAll(',', '.').replaceAll(' ', ''));
}

String _fmt(num? value, {int digits = 1, String suffix = ''}) {
  if (value == null) return '—';
  final text = value.toStringAsFixed(digits).replaceAll('.', ',');
  return suffix.isEmpty ? text : '$text$suffix';
}

String _deltaText(num? delta, {String unit = '', bool asPct = false}) {
  if (delta == null) return '—';
  final sign = delta > 0 ? '+' : '';
  final body = delta.toStringAsFixed(1).replaceAll('.', ',');
  if (asPct) return '$body%';
  return unit.isEmpty ? '$sign$body' : '$sign$body $unit';
}

Color _deltaColor(num? delta, {required bool upIsGood}) {
  if (delta == null || delta == 0) return _label;
  final positive = delta > 0;
  if (upIsGood) return positive ? _up : _down;
  return positive ? _down : _up;
}

DateTime? _parseAt(Map<String, dynamic> item) {
  return DateHelper.parseLocal(
    item['recorded_at']?.toString() ?? item['created_at']?.toString() ?? item['taken_on']?.toString() ?? '',
  );
}

Map<String, dynamic>? _asMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

/// Profile tab «Прогресс» — summary + weight chart + body params + photos.
class ProgressTab extends ConsumerStatefulWidget {
  const ProgressTab({super.key, this.home = const {}});

  final Map<String, dynamic> home;

  @override
  ConsumerState<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends ConsumerState<ProgressTab> {
  Map<String, dynamic> _current = const {};
  Map<String, dynamic> _previous = const {};
  List<({DateTime at, double value})> _weightPoints = const [];
  List<_BodyRow> _bodyRows = const [];
  List<Map<String, dynamic>> _photos = const [];
  Map<String, dynamic> _volume = const {};
  List<Map<String, dynamic>> _strength = const [];
  int _days = 30;
  int? _selectedPoint;

  @override
  void initState() {
    super.initState();
    _seedFromHome();
    _load();
  }

  void _seedFromHome() {
    final home = widget.home;
    final chart = home['weight_chart'];
    final points = <({DateTime at, double value})>[];
    if (chart is List) {
      for (final item in chart.whereType<Map>()) {
        final at = DateTime.tryParse(item['date']?.toString() ?? '')?.toLocal();
        final value = _numOf(item['weight_kg'])?.toDouble();
        if (at != null && value != null) points.add((at: at, value: value));
      }
    }
    _weightPoints = points;
    _current = {
      if (_numOf(home['weight_kg']) != null) 'weight_kg': _numOf(home['weight_kg']),
      if (_numOf(home['body_fat_pct']) != null) 'body_fat_pct': _numOf(home['body_fat_pct']),
      if (_numOf(home['muscle_mass_kg']) != null) 'muscle_mass_kg': _numOf(home['muscle_mass_kg']),
    };
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        FitApi.clientProgress(force: true),
        FitApi.clientMeasurements(force: true),
        FitApi.measurementChart('weight_kg', force: true),
        FitApi.photoProgress(force: true),
        FitApi.volumeProgress(days: _days),
        FitApi.strengthProgress(),
      ]);
      if (!mounted) return;

      final progress = results[0] as Map<String, dynamic>;
      final measurements = results[1] as List<Map<String, dynamic>>;
      final chart = results[2] as List<({DateTime at, double value})>;
      final photos = results[3] as List<Map<String, dynamic>>;
      final volume = results[4] as Map<String, dynamic>;
      final strength = results[5] as List<Map<String, dynamic>>;

      final current = _asMap(progress['current']) ??
          _asMap(progress['latest']) ??
          _asMap(progress['now']) ??
          (measurements.isNotEmpty ? _newest(measurements) : null) ??
          _current;
      final previous = _asMap(progress['previous']) ??
          _asMap(progress['prior']) ??
          _asMap(progress['before']) ??
          _secondNewest(measurements) ??
          const <String, dynamic>{};

      final bodyKeys = const [
        (key: 'shoulders_cm', label: 'Плечи', asset: 'assets/icons/main-params/shoulders.svg'),
        (key: 'chest_cm', label: 'Грудь', asset: 'assets/icons/main-params/chest.svg'),
        (key: 'waist_cm', label: 'Талия', asset: 'assets/icons/main-params/waist.svg'),
        (key: 'thigh_cm', label: 'Бедра', asset: 'assets/icons/main-params/thighs.svg'),
      ];
      final bodyRows = <_BodyRow>[];
      for (final field in bodyKeys) {
        try {
          final points = await FitApi.measurementChart(field.key, force: true);
          if (points.length < 2 && _numOf(current[field.key]) == null) continue;
          final values = [for (final p in points) p.value];
          final now = values.isNotEmpty ? values.last : _numOf(current[field.key])?.toDouble();
          final prev = values.length >= 2 ? values[values.length - 2] : _numOf(previous[field.key])?.toDouble();
          if (now == null) continue;
          bodyRows.add(_BodyRow(
            key: field.key,
            label: field.label,
            asset: field.asset,
            value: now,
            delta: prev == null ? null : now - prev,
            spark: values.length >= 2 ? values : [prev ?? now, now],
          ));
        } catch (_) {
          final now = _numOf(current[field.key])?.toDouble();
          final prev = _numOf(previous[field.key])?.toDouble();
          if (now == null) continue;
          bodyRows.add(_BodyRow(
            key: field.key,
            label: field.label,
            asset: field.asset,
            value: now,
            delta: prev == null ? null : now - prev,
            spark: prev == null ? [now] : [prev, now],
          ));
        }
      }

      setState(() {
        _current = Map<String, dynamic>.from(current);
        _previous = Map<String, dynamic>.from(previous);
        _weightPoints = chart.isNotEmpty ? chart : _weightPoints;
        _bodyRows = bodyRows;
        _photos = photos;
        _volume = volume;
        _strength = strength;
        if (_weightPoints.isNotEmpty) _selectedPoint = _weightPoints.length - 1;
      });
    } catch (_) {
      // silent background load
    }
  }

  Map<String, dynamic> _newest(List<Map<String, dynamic>> items) {
    var best = items.first;
    var at = _parseAt(best);
    for (final item in items) {
      final stamp = _parseAt(item);
      if (stamp != null && (at == null || stamp.isAfter(at))) {
        at = stamp;
        best = item;
      }
    }
    return best;
  }

  Map<String, dynamic>? _secondNewest(List<Map<String, dynamic>> items) {
    if (items.length < 2) return null;
    final sorted = [...items]..sort((a, b) {
        final aa = _parseAt(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bb = _parseAt(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bb.compareTo(aa);
      });
    return sorted[1];
  }

  List<({DateTime at, double value})> get _filteredWeight {
    if (_days <= 0) return _weightPoints;
    final from = DateTime.now().subtract(Duration(days: _days));
    return [for (final p in _weightPoints) if (!p.at.isBefore(from)) p];
  }

  double? get _heightM {
    final user = ref.read(fitSessionProvider).user;
    final cm = _numOf(user?.heightCm) ?? _numOf(widget.home['height_cm']);
    if (cm == null || cm <= 0) return null;
    return cm / 100;
  }

  double? _bmiOf(Map<String, dynamic> source) {
    final w = _numOf(source['weight_kg'])?.toDouble();
    final h = _heightM;
    if (w == null || h == null || h <= 0) return null;
    return w / (h * h);
  }

  num? _delta(String key) {
    final now = _numOf(_current[key]);
    final prev = _numOf(_previous[key]);
    if (now != null && prev != null) return now - prev;
    if (key == 'weight_kg') return _numOf(widget.home['weight_delta_30d']);
    return null;
  }

  Future<void> _pickDays() async {
    final next = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [(30, '30 дней'), (90, '90 дней'), (0, 'Всё время')])
              ListTile(
                title: Text(option.$2, style: const TextStyle(color: Colors.white)),
                trailing: _days == option.$1 ? const Icon(Icons.check, color: _lime) : null,
                onTap: () => Navigator.pop(context, option.$1),
              ),
          ],
        ),
      ),
    );
    if (next != null) {
      setState(() => _days = next == 0 ? 90 : next);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weight = _numOf(_current['weight_kg']) ?? _numOf(widget.home['weight_kg']);
    final fat = _numOf(_current['body_fat_pct']) ?? _numOf(widget.home['body_fat_pct']);
    final muscle = _numOf(_current['muscle_mass_kg']) ?? _numOf(widget.home['muscle_mass_kg']);
    final bmi = _bmiOf(_current) ?? _bmiOf({'weight_kg': weight});
    final prevBmi = _bmiOf(_previous);
    final bmiDeltaPct = (bmi != null && prevBmi != null && prevBmi != 0) ? ((bmi - prevBmi) / prevBmi) * 100 : null;

    final weightDelta = _delta('weight_kg');
    final fatDelta = _delta('body_fat_pct');
    final muscleDelta = _delta('muscle_mass_kg');

    final points = _filteredWeight;
    final selected = (_selectedPoint != null && _selectedPoint! < points.length)
        ? _selectedPoint!
        : (points.isEmpty ? null : points.length - 1);

    return Column(
      children: [
        _SummaryCard(
          weight: weight,
          weightDelta: weightDelta,
          fat: fat,
          fatDelta: fatDelta,
          muscle: muscle,
          muscleDelta: muscleDelta,
          bmi: bmi,
          bmiDeltaPct: bmiDeltaPct,
        ),
        const SizedBox(height: 14),
        WeightDynamicsCard(
          days: _days,
          points: points,
          selected: selected,
          onPickDays: _pickDays,
          onSelect: (i) => setState(() => _selectedPoint = i),
        ),
        const SizedBox(height: 14),
        _VolumeCard(volume: _volume, strength: _strength),
        const SizedBox(height: 14),
        _BodyParamsCard(rows: _bodyRows),
        const SizedBox(height: 14),
        _PhotoProgressCard(sets: _photos),
      ],
    );
  }
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.volume, required this.strength});

  final Map<String, dynamic> volume;
  final List<Map<String, dynamic>> strength;

  @override
  Widget build(BuildContext context) {
    final total = _numOf(volume['total_volume_kg']);
    final series = (volume['series'] is List)
        ? [
            for (final item in (volume['series'] as List).whereType<Map>())
              _numOf(item['volume_kg'])?.toDouble() ?? 0.0,
          ]
        : const <double>[];
    final exercises = (volume['by_exercise'] is List)
        ? (volume['by_exercise'] as List).whereType<Map>().take(5).toList()
        : const <Map>[];
    final maxY = series.isEmpty ? 1.0 : series.reduce(math.max).clamp(1.0, double.infinity);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Объём тренировок', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            total == null ? 'Нет данных за период' : 'Сумма ${_fmt(total, digits: 0)} кг·повт',
            style: const TextStyle(color: _label, fontSize: 13),
          ),
          if (series.length >= 2) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in series)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: 8 + (48 * (v / maxY)),
                          decoration: BoxDecoration(
                            color: _lime.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var i = 0; i < exercises.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      exercises[i]['name']?.toString() ?? 'Упражнение',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _fmt(_numOf(exercises[i]['volume_kg']), digits: 0, suffix: ' кг'),
                    style: const TextStyle(color: _lime, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ] else if (strength.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var i = 0; i < strength.length && i < 5; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strength[i]['name']?.toString() ?? 'Упражнение',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${_fmt(_numOf(strength[i]['last_weight_kg']), digits: 0)} кг × ${_fmt(_numOf(strength[i]['last_reps']), digits: 0)}',
                    style: const TextStyle(color: _label, fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BodyRow {
  const _BodyRow({
    required this.key,
    required this.label,
    required this.asset,
    required this.value,
    required this.delta,
    required this.spark,
  });

  final String key;
  final String label;
  final String asset;
  final double value;
  final double? delta;
  final List<double> spark;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.weight,
    required this.weightDelta,
    required this.fat,
    required this.fatDelta,
    required this.muscle,
    required this.muscleDelta,
    required this.bmi,
    required this.bmiDeltaPct,
  });

  final num? weight;
  final num? weightDelta;
  final num? fat;
  final num? fatDelta;
  final num? muscle;
  final num? muscleDelta;
  final num? bmi;
  final num? bmiDeltaPct;

  static const _cardBg = Color(0xFF232323);

  @override
  Widget build(BuildContext context) {
    final bmiValue = bmi;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прогресс',
            style: GoogleFonts.openSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  asset: 'assets/icons/main-params/weight.svg',
                  label: 'Вес',
                  value: _fmt(weight, suffix: ' кг'),
                  delta: _deltaText(weightDelta, unit: 'кг'),
                  deltaColor: _deltaColor(weightDelta, upIsGood: false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  asset: 'assets/icons/main-params/progres.svg',
                  label: 'Процент жира',
                  value: _fmt(fat, suffix: ' %'),
                  delta: _deltaText(fatDelta, unit: '%'),
                  deltaColor: _deltaColor(fatDelta, upIsGood: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  asset: 'assets/icons/main-params/bicep.svg',
                  label: 'Мышечная масса',
                  value: _fmt(muscle, suffix: ' кг'),
                  delta: _deltaText(muscleDelta, unit: 'кг'),
                  deltaColor: _deltaColor(muscleDelta, upIsGood: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  asset: 'assets/icons/main-params/imt.svg',
                  label: 'ИМТ',
                  value: bmiValue == null ? '—' : bmiValue.toStringAsFixed(1),
                  delta: _deltaText(bmiDeltaPct, asPct: true),
                  deltaColor: _deltaColor(bmiDeltaPct, upIsGood: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Same chrome as measurements `_MainParamTile` (+ delta line).
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.asset,
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaColor,
  });

  final String asset;
  final String label;
  final String value;
  final String delta;
  final Color deltaColor;

  static const _tileBg = Color(0xFF232323);
  static const _valueBg = Color(0xFF292929);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _tileBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(asset, width: 18, height: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.openSans(
                    color: _label,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _valueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.openSans(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  delta,
                  style: GoogleFonts.openSans(
                    color: deltaColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _BodyParamsCard extends StatelessWidget {
  const _BodyParamsCard({required this.rows});

  final List<_BodyRow> rows;

  @override
  Widget build(BuildContext context) {
    final preview = rows.take(4).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Параметры тела',
                    style: GoogleFonts.openSans(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.push(RouteNames.body),
                  child: Row(
                    children: [
                      Text('Показать все', style: GoogleFonts.openSans(color: _lime, fontSize: 13, fontWeight: FontWeight.w600)),
                      const Icon(Icons.chevron_right, color: _lime, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (preview.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Замеров пока нет', style: GoogleFonts.openSans(color: _label)),
            )
          else
            for (var i = 0; i < preview.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0xFF353535)),
              _BodyParamRow(row: preview[i]),
            ],
        ],
      ),
    );
  }
}

class _BodyParamRow extends StatelessWidget {
  const _BodyParamRow({required this.row});

  final _BodyRow row;

  @override
  Widget build(BuildContext context) {
    final up = (row.delta ?? 0) >= 0;
    final color = up ? _up : _down;
    final delta = row.delta;
    final deltaLabel = delta == null
        ? ''
        : ' (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1).replaceAll('.', ',')} см)';
    return InkWell(
      onTap: () => context.push(RouteNames.body),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            SvgPicture.asset(row.asset, width: 36, height: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(row.label, style: GoogleFonts.openSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            _GlowSparkline(values: row.spark, color: color),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: row.value.toStringAsFixed(1).replaceAll('.', ','),
                    style: GoogleFonts.openSans(color: color, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: deltaLabel,
                    style: GoogleFonts.openSans(color: color, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _label, size: 18),
          ],
        ),
      ),
    );
  }
}

class _GlowSparkline extends StatelessWidget {
  const _GlowSparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 32,
      child: CustomPaint(painter: _GlowSparkPainter(values, color)),
    );
  }
}

class _GlowSparkPainter extends CustomPainter {
  _GlowSparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    // Pad to ≥4 points so the chart reads like Figma (not a tiny segment).
    var series = List<double>.from(values);
    while (series.length < 4) {
      series = [series.first, ...series];
    }
    if (series.length == 1) series = [series.first, series.first];

    const padY = 4.0;
    const padX = 3.0;
    final minV = series.reduce(math.min);
    final maxV = series.reduce(math.max);
    final span = (maxV - minV).abs() < 0.01 ? 1.0 : maxV - minV;

    Offset pointAt(int i) {
      final x = padX + (size.width - padX * 2) * i / (series.length - 1);
      final y = size.height - padY - ((series[i] - minV) / span) * (size.height - padY * 2);
      return Offset(x, y);
    }

    final pts = [for (var i = 0; i < series.length; i++) pointAt(i)];

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
    }

    final fill = Path()
      ..moveTo(pts.first.dx, size.height)
      ..lineTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      fill.lineTo(pts[i].dx, pts[i].dy);
    }
    fill
      ..lineTo(pts.last.dx, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.45),
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final p in pts) {
      canvas.drawCircle(p, 3.2, Paint()..color = Colors.white);
      canvas.drawCircle(p, 2.1, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _GlowSparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _PhotoProgressCard extends StatelessWidget {
  const _PhotoProgressCard({required this.sets});

  final List<Map<String, dynamic>> sets;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sets]..sort((a, b) {
        final aa = DateTime.tryParse(a['taken_on']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bb = DateTime.tryParse(b['taken_on']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bb.compareTo(aa);
      });
    final preview = sorted.take(2).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _innerBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Фото прогресс',
                  style: GoogleFonts.openSans(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              GestureDetector(
                onTap: () => context.push(RouteNames.photo),
                child: Row(
                  children: [
                    Text('Показать все', style: GoogleFonts.openSans(color: _lime, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Icon(Icons.chevron_right, color: _lime, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (preview.isEmpty)
            Text('Фото пока нет', style: GoogleFonts.openSans(color: _label))
          else
            for (var i = 0; i < preview.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _PhotoSetBlock(set: preview[i]),
            ],
        ],
      ),
    );
  }
}

class _PhotoSetBlock extends StatelessWidget {
  const _PhotoSetBlock({required this.set});

  final Map<String, dynamic> set;

  @override
  Widget build(BuildContext context) {
    final takenOn = DateHelper.parseLocal(set['taken_on']?.toString());
    final label = _relativeLabel(takenOn);
    final date = takenOn == null ? '' : DateHelper.formatRuDate(takenOn);
    final images = set['images'];
    final urls = <String>[];
    if (images is List) {
      for (final item in images.whereType<Map>()) {
        final url = item['image_url']?.toString() ?? item['url']?.toString() ?? '';
        if (url.isNotEmpty) urls.add(url);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: GoogleFonts.openSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (date.isNotEmpty)
                  TextSpan(
                    text: ' ($date)',
                    style: GoogleFonts.openSans(color: _label, fontSize: 13),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 0.85,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: i < urls.length
                          ? Image.network(
                              urls[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stackTrace) => const ColoredBox(
                                color: Color(0xFF1C1C1C),
                                child: Icon(Icons.photo, color: _label),
                              ),
                            )
                          : const ColoredBox(
                              color: Color(0xFF1C1C1C),
                              child: Icon(Icons.add_a_photo_outlined, color: _label),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _relativeLabel(DateTime? at) {
    if (at == null) return 'Фотосет';
    final days = DateTime.now().difference(at).inDays;
    if (days < 7) return 'На этой неделе';
    if (days < 35) return '1 месяц назад';
    final months = (days / 30).round();
    if (months == 1) return '1 месяц назад';
    if (months >= 2 && months <= 4) return '$months месяца назад';
    return '$months месяцев назад';
  }
}
