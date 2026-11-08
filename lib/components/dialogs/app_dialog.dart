import 'package:flutter/material.dart';
import 'package:trainhub/components/buttons/app_button.dart';
import 'package:trainhub/core/constants/spacing.dart';

/// Reusable confirmation / info dialog helpers.
class AppDialog {
  AppDialog._();

  /// Shows a simple alert with an optional confirm action.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'OK',
    String? cancelLabel,
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          actions: [
            if (cancelLabel != null)
              AppButton(
                label: cancelLabel,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            AppButton(
              label: confirmLabel,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
  }

  /// Shows a confirm dialog that returns `true` only when confirmed.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
  }) async {
    final result = await show(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    );
    return result ?? false;
  }
}
