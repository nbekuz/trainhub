import 'package:flutter/material.dart';
import 'package:trainhub/core/constants/border_radius_constants.dart';
import 'package:trainhub/core/constants/spacing.dart';

/// Helper for presenting styled modal bottom sheets.
class AppBottomSheet {
  AppBottomSheet._();

  /// Shows a rounded modal bottom sheet with optional title.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    bool isScrollControlled = true,
    bool showDragHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.xl),
        ),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.md,
            bottom: bottomInset + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.lg),
              ],
              child,
            ],
          ),
        );
      },
    );
  }
}
