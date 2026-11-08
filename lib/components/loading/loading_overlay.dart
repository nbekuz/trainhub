import 'package:flutter/material.dart';
import 'package:trainhub/core/theme/app_colors.dart';

/// Global full-screen loading overlay.
///
/// Usage:
/// ```dart
/// Loading.show(context);
/// // ... async work
/// Loading.hide();
/// ```
class Loading {
  Loading._();

  static OverlayEntry? _entry;

  /// Shows a blocking loading overlay.
  static void show(BuildContext context, {String? message}) {
    if (_entry != null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (_) => _LoadingView(message: message),
    );
    overlay.insert(_entry!);
  }

  /// Hides the loading overlay if visible.
  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  /// Whether the overlay is currently visible.
  static bool get isShowing => _entry != null;
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      message!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
