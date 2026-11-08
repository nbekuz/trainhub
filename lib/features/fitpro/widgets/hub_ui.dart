import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/core/theme/app_colors.dart';

class HubCard extends StatelessWidget {
  const HubCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.border});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.fitCard,
        borderRadius: BorderRadius.circular(22),
        border: border ?? const Border.fromBorderSide(BorderSide(color: Color(0xFF323232))),
      ),
      child: child,
    );
  }
}

class HubBackTitle extends StatelessWidget {
  const HubBackTitle({super.key, required this.title, this.trailing, this.onBack});

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack ?? () => context.pop(),
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          trailing ?? const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class HubSectionTitle extends StatelessWidget {
  const HubSectionTitle({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: const Row(
              children: [
                Text('Все', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: AppColors.accent, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class HubAvatar extends StatelessWidget {
  const HubAvatar({super.key, required this.letter, this.size = 48});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Color(0xFF3A3A3A), shape: BoxShape.circle),
      child: Text(
        letter.isEmpty ? 'U' : letter[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36),
      ),
    );
  }
}

class HubMenuTile extends StatelessWidget {
  const HubMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF5C5C) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: danger ? color : AppColors.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 16))),
            if (trailing != null)
              Text(trailing!, style: const TextStyle(color: AppColors.fitGrey))
            else if (!danger)
              const Icon(Icons.chevron_right, color: AppColors.fitGrey, size: 20),
          ],
        ),
      ),
    );
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  final List<num> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 28,
      child: CustomPaint(painter: _SparkPainter(values, color)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.map((v) => v.toDouble()).reduce((a, b) => a < b ? a : b);
    final maxV = values.map((v) => v.toDouble()).reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.01 ? 1.0 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i].toDouble() - minV) / span) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => oldDelegate.values != values || oldDelegate.color != color;
}

class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.values, this.labels = const []});

  final List<num> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(values, labels),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.labels);

  final List<num> values;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 28.0;
    final chart = Rect.fromLTWH(left, 8, size.width - left, size.height - 28);
    final minV = values.map((v) => v.toDouble()).reduce((a, b) => a < b ? a : b) - 2;
    final maxV = values.map((v) => v.toDouble()).reduce((a, b) => a > b ? a : b) + 2;
    final span = maxV - minV;

    final grid = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(color: AppColors.fitGrey, fontSize: 10);
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final value = maxV - span * i / 3;
      final tp = TextPainter(
        text: TextSpan(text: value.round().toString(), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 6));
    }

    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + chart.width * (values.length == 1 ? 0.5 : i / (values.length - 1));
      final y = chart.bottom - ((values[i].toDouble() - minV) / span) * chart.height;
      points.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    final last = points.last;
    canvas.drawCircle(last, 5, Paint()..color = AppColors.accent);
    final badge = TextPainter(
      text: TextSpan(
        text: values.last.toDouble().round().toString(),
        style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: last + const Offset(0, -16), width: badge.width + 12, height: 18),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.accent);
    badge.paint(canvas, Offset(rect.left + 6, rect.top + 2));

    for (var i = 0; i < labels.length && i < points.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(points[i].dx - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.values != values;
}
