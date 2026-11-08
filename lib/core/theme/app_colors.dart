import 'package:flutter/material.dart';

/// Semantic and brand color tokens for light and dark themes.
class AppColors {
  AppColors._();

  // FitPro brand
  static const Color accent = Color(0xFFC7F137);
  static const Color primary = Color(0xFF000000);
  static const Color primaryLight = Color(0xFFFFD200);
  static const Color primaryDark = Color(0xFF0D0D0D);
  static const Color secondary = Color(0xFF292929);

  static const Color fitBg = Color(0xFF0D0D0D);
  static const Color fitCard = Color(0xFF242424);
  static const Color fitSurface = Color(0xFF292929);
  static const Color fitMuted = Color(0xFF2D2D35);
  static const Color fitGrey = Color(0xFF979797);
  static const Color fitBorder = Color(0xFF505050);
  static const Color fitGreen = Color(0xFF8ACA2B);

  // Neutrals
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF0B1220);
  static const Color grey50 = Color(0xFFF7F8FA);
  static const Color grey100 = Color(0xFFEEF1F5);
  static const Color grey200 = Color(0xFFDCE2EA);
  static const Color grey300 = Color(0xFFB8C2CF);
  static const Color grey400 = Color(0xFF8A96A8);
  static const Color grey500 = Color(0xFF5E6B7D);
  static const Color grey600 = Color(0xFF3F4B5C);
  static const Color grey700 = Color(0xFF2A3340);
  static const Color grey800 = Color(0xFF1A222D);
  static const Color grey900 = Color(0xFF111820);

  // Semantic
  static const Color success = Color(0xFF1F8A4C);
  static const Color warning = Color(0xFFC47D0E);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF1B6CA8);

  // Surfaces — light
  static const Color lightBackground = Color(0xFFF4F7F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF111820);
  static const Color lightOutline = Color(0xFFDCE2EA);

  // Surfaces — dark
  static const Color darkBackground = Color(0xFF0D0D0D);
  static const Color darkSurface = Color(0xFF242424);
  static const Color darkOnSurface = Color(0xFFF2F5F8);
  static const Color darkOutline = Color(0xFF2A3340);
}
