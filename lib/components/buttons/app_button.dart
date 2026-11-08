import 'package:flutter/material.dart';
import 'package:trainhub/core/constants/border_radius_constants.dart';
import 'package:trainhub/core/constants/spacing.dart';

/// Visual style variants for [AppButton].
enum AppButtonVariant { filled, outlined, text, icon }

/// Reusable application button with loading and disabled states.
class AppButton extends StatelessWidget {
  /// Creates a filled / outlined / text / icon button.
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.expand = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// Icon-only convenience constructor.
  const AppButton.icon({
    super.key,
    required IconData this.icon,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.backgroundColor,
    this.foregroundColor,
  })  : label = '',
        variant = AppButtonVariant.icon,
        expand = false;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool isDisabled;
  final IconData? icon;
  final bool expand;
  final Color? backgroundColor;
  final Color? foregroundColor;

  bool get _enabled => onPressed != null && !isDisabled && !isLoading;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild(context);

    Widget button;
    switch (variant) {
      case AppButtonVariant.filled:
        button = ElevatedButton(
          onPressed: _enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            minimumSize: Size(expand ? double.infinity : 0, 48),
            shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.mdAll),
          ),
          child: child,
        );
      case AppButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: _enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            minimumSize: Size(expand ? double.infinity : 0, 48),
            shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.mdAll),
          ),
          child: child,
        );
      case AppButtonVariant.text:
        button = TextButton(
          onPressed: _enabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            minimumSize: Size(expand ? double.infinity : 0, 48),
          ),
          child: child,
        );
      case AppButtonVariant.icon:
        button = IconButton(
          onPressed: _enabled ? onPressed : null,
          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
          ),
        );
    }

    return button;
  }

  Widget _buildChild(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    if (icon != null && label.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
        ],
      );
    }

    if (icon != null && label.isEmpty) {
      return Icon(icon, size: 20);
    }

    return Text(label);
  }
}
