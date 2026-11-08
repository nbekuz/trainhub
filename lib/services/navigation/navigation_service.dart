import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Imperative navigation helpers wrapping [GoRouter].
///
/// Prefer declarative `context.go` / `context.push` in widgets.
/// Use this service from non-UI layers (e.g. auth interceptors) when needed.
class NavigationService {
  /// Creates a [NavigationService] bound to a [GlobalKey] navigator.
  NavigationService(this.navigatorKey);

  /// Root navigator key shared with [GoRouter].
  final GlobalKey<NavigatorState> navigatorKey;

  /// Current [BuildContext] from the navigator, if mounted.
  BuildContext? get context => navigatorKey.currentContext;

  /// Replaces the stack with [location].
  void go(String location, {Object? extra}) {
    final ctx = context;
    if (ctx == null) return;
    ctx.go(location, extra: extra);
  }

  /// Pushes [location] onto the stack.
  Future<T?>? push<T extends Object?>(String location, {Object? extra}) {
    final ctx = context;
    if (ctx == null) return null;
    return ctx.push<T>(location, extra: extra);
  }

  /// Pops the current route when possible.
  void pop<T extends Object?>([T? result]) {
    final ctx = context;
    if (ctx == null) return;
    if (ctx.canPop()) ctx.pop(result);
  }
}
