import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';

const _lime = Color(0xFFC4F52B);
const _outerBg = Color(0xFF292929);
const _border = Color(0xFF323232);
const _label = Color(0xFFA0A0A0);
const _tooltip = Color(0xFFFFB84D);

typedef WeightPoint = ({DateTime at, double value});

/// Figma «Динамика веса» card — shared by Обзор and Прогресс.
class WeightDynamicsCard extends StatelessWidget {
  const WeightDynamicsCard({
    super.key,
    required this.days,
    required this.points,
    required this.selected,
    required this.onPickDays,
    required this.onSelect,
    this.emptyHint = 'Нет данных',
  });

  final int days;
  final List<WeightPoint> points;
  final int? selected;
  final VoidCallback onPickDays;
  final ValueChanged<int> onSelect;
  final String emptyHint;

  static List<WeightPoint> parseHomeChart(Object? raw) {
    if (raw is! List) return const [];
    final out = <WeightPoint>[];
    for (final item in raw.whereType<Map>()) {
      final at = DateTime.tryParse(item['date']?.toString() ?? '')?.toLocal();
      final value = double.tryParse('${item['weight_kg']}'.replaceAll(',', '.'));
      if (at != null && value != null) out.add((at: at, value: value));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  static List<WeightPoint> filterByDays(List<WeightPoint> all, int days) {
    if (days <= 0) return all;
    final from = DateTime.now().subtract(Duration(days: days));
    return [for (final p in all) if (!p.at.isBefore(from)) p];
  }

  @override
  Widget build(BuildContext context) {
    final daysLabel = days == 0 ? 'Всё время' : '$days дней';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Динамика веса',
                      style: GoogleFonts.openSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Анализ по кг',
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
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPickDays,
                  borderRadius: BorderRadius.circular(111),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232323),
                      borderRadius: BorderRadius.circular(111),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          daysLabel,
                          style: GoogleFonts.openSans(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            height: 212,
            padding: const EdgeInsets.fromLTRB(6, 10, 8, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: points.length < 2
                ? Center(
                    child: Text(emptyHint, style: GoogleFonts.openSans(color: _label)),
                  )
                : _WeightChart(
                    points: points,
                    selected: selected ?? points.length - 1,
                    onSelect: onSelect,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Self-contained block for Обзор: parses `home['weight_chart']`, period + selection.
class OverviewWeightDynamics extends StatefulWidget {
  const OverviewWeightDynamics({super.key, required this.home});

  final Map<String, dynamic> home;

  @override
  State<OverviewWeightDynamics> createState() => _OverviewWeightDynamicsState();
}

class _OverviewWeightDynamicsState extends State<OverviewWeightDynamics> {
  int _days = 30;
  int? _selected;
  List<WeightPoint> _all = const [];

  @override
  void initState() {
    super.initState();
    _syncFromHome();
    _loadFullChart();
  }

  @override
  void didUpdateWidget(covariant OverviewWeightDynamics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.home != widget.home) {
      _syncFromHome();
      _loadFullChart();
    }
  }

  void _syncFromHome() {
    final parsed = WeightDynamicsCard.parseHomeChart(widget.home['weight_chart']);
    if (parsed.isNotEmpty) {
      _all = parsed;
      _selected = parsed.length - 1;
    }
  }

  Future<void> _loadFullChart() async {
    try {
      final chart = await FitApi.measurementChart('weight_kg');
      if (!mounted || chart.isEmpty) return;
      setState(() {
        _all = [for (final p in chart) (at: p.at, value: p.value)];
        final filtered = WeightDynamicsCard.filterByDays(_all, _days);
        _selected = filtered.isEmpty ? null : filtered.length - 1;
      });
    } catch (_) {}
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
    if (next == null) return;
    setState(() {
      _days = next;
      final filtered = WeightDynamicsCard.filterByDays(_all, _days);
      _selected = filtered.isEmpty ? null : filtered.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = WeightDynamicsCard.filterByDays(_all, _days);
    final selected = (_selected != null && _selected! < points.length)
        ? _selected
        : (points.isEmpty ? null : points.length - 1);
    return WeightDynamicsCard(
      days: _days,
      points: points,
      selected: selected,
      onPickDays: _pickDays,
      onSelect: (i) => setState(() => _selected = i),
      emptyHint: 'За выбранный период замеров веса нет',
    );
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.points, required this.selected, required this.onSelect});

  final List<WeightPoint> points;
  final int selected;
  final ValueChanged<int> onSelect;

  static const left = 30.0;
  static const right = 10.0;
  static const top = 28.0;
  static const bottom = 24.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final width = constraints.maxWidth - left - right;
            if (width <= 0 || points.isEmpty) return;
            final local = details.localPosition;
            var best = 0;
            var bestDist = double.infinity;
            for (var i = 0; i < points.length; i++) {
              final x = left + width * (points.length == 1 ? 0.5 : i / (points.length - 1));
              final d = (local.dx - x).abs();
              if (d < bestDist) {
                bestDist = d;
                best = i;
              }
            }
            onSelect(best);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _WeightChartPainter(points: points, selected: selected),
          ),
        );
      },
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter({required this.points, required this.selected});

  final List<WeightPoint> points;
  final int selected;

  static const _left = _WeightChart.left;
  static const _top = _WeightChart.top;
  static const _bottom = _WeightChart.bottom;
  static const _right = _WeightChart.right;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final chart = Rect.fromLTWH(
      _left,
      _top,
      math.max(0, size.width - _left - _right),
      math.max(0, size.height - _top - _bottom),
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    final values = [for (final p in points) p.value];
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    var step = 2.0;
    final rawSpan = (maxV - minV).abs();
    if (rawSpan > 12) step = 4.0;
    if (rawSpan < 1) {
      minV -= 4;
      maxV += 4;
    }
    minV = (minV / step).floor() * step;
    maxV = (maxV / step).ceil() * step;
    if (maxV <= minV) maxV = minV + step * 4;
    while ((maxV - minV) / step < 4) {
      minV -= step;
      maxV += step;
    }
    final span = maxV - minV;
    final tickCount = ((maxV - minV) / step).round().clamp(4, 6);

    final gridPaint = Paint()
      ..color = const Color(0xFF3A3A3A).withValues(alpha: 0.85)
      ..strokeWidth = 1;
    final axisStyle = GoogleFonts.openSans(
      color: _label,
      fontSize: 10,
      fontWeight: FontWeight.w400,
      height: 1,
    );

    for (var i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final y = chart.top + chart.height * t;
      _dashLine(canvas, Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = maxV - span * t;
      final tp = TextPainter(
        text: TextSpan(text: value.round().toString(), style: axisStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 6, y - tp.height / 2));
    }

    final pts = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = chart.left + chart.width * (points.length == 1 ? 0.5 : i / (points.length - 1));
      final y = chart.bottom - ((points[i].value - minV) / span) * chart.height;
      pts.add(Offset(x, y));
      _dashLine(canvas, Offset(x, chart.top), Offset(x, chart.bottom), gridPaint);
    }

    final linePath = _smoothPath(pts);
    final fillPath = Path.from(linePath)
      ..lineTo(pts.last.dx, chart.bottom)
      ..lineTo(pts.first.dx, chart.bottom)
      ..close();

    canvas.save();
    canvas.clipRect(chart.inflate(1));
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _lime.withValues(alpha: 0.22),
            _lime.withValues(alpha: 0.06),
            _lime.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(chart),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = _lime.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = _lime
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    final sel = selected.clamp(0, pts.length - 1);
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final active = i == sel;
      canvas.drawCircle(
        p,
        active ? 12 : 9,
        Paint()
          ..color = (active ? _tooltip : _lime).withValues(alpha: active ? 0.28 : 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      if (active) {
        canvas.drawCircle(p, 7.5, Paint()..color = _tooltip);
        canvas.drawCircle(p, 3.6, Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(p, 5.2, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3.6, Paint()..color = _lime);
      }
    }

    final focus = pts[sel];
    final badgeText = '${_fmtKg(points[sel].value)} кг';
    final badge = TextPainter(
      text: TextSpan(
        text: badgeText,
        style: GoogleFonts.openSans(
          color: const Color(0xFF1A1A1A),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    const padX = 10.0;
    const padY = 7.0;
    const tipH = 6.0;
    final bubbleW = badge.width + padX * 2;
    final bubbleH = badge.height + padY * 2;
    var bubbleLeft = focus.dx - bubbleW / 2;
    bubbleLeft = bubbleLeft.clamp(4.0, size.width - bubbleW - 4);
    var bubbleTop = focus.dy - 14 - tipH - bubbleH;
    if (bubbleTop < 2) bubbleTop = 2;
    final bubbleRect = Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleW, bubbleH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(10)),
      Paint()..color = _tooltip,
    );
    final tipX = focus.dx.clamp(bubbleLeft + 8, bubbleLeft + bubbleW - 8);
    final tip = Path()
      ..moveTo(tipX - 5.5, bubbleTop + bubbleH - 0.5)
      ..lineTo(tipX, bubbleTop + bubbleH + tipH)
      ..lineTo(tipX + 5.5, bubbleTop + bubbleH - 0.5)
      ..close();
    canvas.drawPath(tip, Paint()..color = _tooltip);
    badge.paint(canvas, Offset(bubbleLeft + padX, bubbleTop + padY));

    final df = DateFormat('dd.MM');
    final labelIndexes = _xLabelIndexes(points.length);
    for (final i in labelIndexes) {
      final active = i == sel;
      final tp = TextPainter(
        text: TextSpan(
          text: df.format(points[i].at),
          style: GoogleFonts.openSans(
            color: active ? Colors.white : _label,
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            height: 1,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      var lx = pts[i].dx - tp.width / 2;
      lx = lx.clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(lx, size.height - 16));
    }
  }

  Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    return path;
  }

  String _fmtKg(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }

  Set<int> _xLabelIndexes(int n) {
    if (n <= 1) return {0};
    if (n == 2) return {0, 1};
    if (n <= 5) return {for (var i = 0; i < n; i++) i};
    return {0, n ~/ 4, n ~/ 2, (n * 3) ~/ 4, n - 1};
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 3.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final direction = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + direction * drawn;
      final end = a + direction * math.min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.selected != selected;
}
