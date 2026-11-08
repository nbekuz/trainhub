import 'package:flutter/material.dart';
import 'package:trainhub/components/toast/toast.dart';

/// Convenient [BuildContext] helpers for theme, media and navigation.
extension ContextExtensions on BuildContext {
  /// Shortcut to [Theme.of].
  ThemeData get theme => Theme.of(this);

  /// Shortcut to [ColorScheme].
  ColorScheme get colors => theme.colorScheme;

  /// Shortcut to [TextTheme].
  TextTheme get textTheme => theme.textTheme;

  /// Shortcut to [MediaQuery.sizeOf].
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Screen width.
  double get screenWidth => screenSize.width;

  /// Screen height.
  double get screenHeight => screenSize.height;

  /// Whether the current theme brightness is dark.
  bool get isDark => theme.brightness == Brightness.dark;

  /// Safe area padding.
  EdgeInsets get padding => MediaQuery.paddingOf(this);

  /// Shows a toast that drops from the top.
  void showSnack(String message) {
    Toast.info(message);
  }
}
