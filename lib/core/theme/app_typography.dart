import 'package:flutter/material.dart';
import 'package:trainhub/core/theme/app_colors.dart';

/// Typography scale built on Material 3 text roles.
///
/// Drop custom font files into `assets/fonts/` and set [displayFont] /
/// [bodyFont], then register them in `pubspec.yaml`.
class AppTypography {
  AppTypography._();

  /// Optional display font family (null = platform default).
  static const String? displayFont = null;

  /// Optional body font family (null = platform default).
  static const String? bodyFont = null;

  static TextTheme get textTheme {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.5,
        color: AppColors.lightOnSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: AppColors.lightOnSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: AppColors.lightOnSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.lightOnSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.lightOnSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppColors.lightOnSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppColors.lightOnSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: AppColors.lightOnSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: AppColors.lightOnSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.lightOnSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.lightOnSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: AppColors.grey500,
      ),
      labelLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.2,
        color: AppColors.lightOnSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.2,
        color: AppColors.lightOnSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0.3,
        color: AppColors.grey500,
      ),
    );
  }
}
