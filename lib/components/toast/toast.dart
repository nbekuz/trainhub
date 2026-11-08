import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trainhub/core/constants/app_constants.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/services/navigation/navigation_service.dart';

/// Toast severity variants (Ant Design Message style).
enum ToastType { success, error, warning, info }

/// Global animated toast system built on [OverlayEntry].
///
/// Usage:
/// ```dart
/// Toast.success('Saved successfully');
/// Toast.error('Something went wrong');
/// Toast.warning('Check your input');
/// Toast.info('Heads up');
/// ```
class Toast {
  Toast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Shows a success toast.
  static void success(String message, {Duration? duration}) =>
      _show(message, ToastType.success, duration);

  /// Shows an error toast.
  static void error(String message, {Duration? duration}) =>
      _show(message, ToastType.error, duration);

  /// Shows a warning toast.
  static void warning(String message, {Duration? duration}) =>
      _show(message, ToastType.warning, duration);

  /// Shows an info toast.
  static void info(String message, {Duration? duration}) =>
      _show(message, ToastType.info, duration);

  /// Dismisses any visible toast immediately.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  static void _show(String message, ToastType type, Duration? duration) {
    final overlay = _findOverlay();
    if (overlay == null) return;

    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastHost(
        message: message,
        type: type,
        duration: duration ?? AppConstants.toastDuration,
        onDismissed: () {
          if (_entry == entry) {
            _entry?.remove();
            _entry = null;
          }
        },
      ),
    );

    _entry = entry;
    overlay.insert(entry);
  }

  static OverlayState? _findOverlay() {
    // Prefer the root navigator registered with GetIt / GoRouter.
    if (getIt.isRegistered<NavigationService>()) {
      final navContext = getIt<NavigationService>().context;
      if (navContext != null) {
        final overlay = Overlay.maybeOf(navContext, rootOverlay: true);
        if (overlay != null) return overlay;
      }
    }

    final focusContext =
        WidgetsBinding.instance.focusManager.primaryFocus?.context;
    if (focusContext != null) {
      return Overlay.maybeOf(focusContext, rootOverlay: true);
    }
    return null;
  }
}

/// Animated toast host that slides + fades from the top.
class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _drop;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 380),
    );
    _drop = Tween<double>(begin: -160, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
      reverseCurve: const Interval(0.2, 1, curve: Curves.easeIn),
    );

    _controller.forward();
    Future<void>.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + 10,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _drop.value),
            child: Opacity(opacity: _fade.value.clamp(0, 1), child: child),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: _ToastCard(message: widget.message, type: widget.type),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.message, required this.type});

  final String message;
  final ToastType type;

  Color get _mark {
    return switch (type) {
      ToastType.success => AppColors.accent,
      ToastType.error => const Color(0xFFFD6565),
      ToastType.warning => const Color(0xFFFEB94B),
      ToastType.info => AppColors.accent,
    };
  }

  IconData get _icon {
    return switch (type) {
      ToastType.success => Icons.check_rounded,
      ToastType.error => Icons.close_rounded,
      ToastType.warning => Icons.priority_high_rounded,
      ToastType.info => Icons.info_outline_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final onMark = type == ToastType.error ? Colors.white : Colors.black;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF3A3A3A)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _mark, shape: BoxShape.circle),
                  child: Icon(_icon, color: onMark, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
