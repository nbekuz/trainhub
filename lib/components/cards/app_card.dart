import 'package:flutter/material.dart';
import 'package:trainhub/core/constants/border_radius_constants.dart';
import 'package:trainhub/core/constants/spacing.dart';

/// Lightweight surface container for interactive or grouped content.
///
/// Prefer plain layouts when a card is not required for understanding.
class AppCard extends StatelessWidget {
  /// Creates an [AppCard].
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppBorderRadius.lgAll;
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );
  }
}
