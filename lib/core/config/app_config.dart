import 'package:trainhub/core/config/api_config.dart';
import 'package:trainhub/core/config/env_config.dart';
import 'package:trainhub/core/constants/app_constants.dart';

/// Aggregated app configuration resolved at startup.
///
/// Prefer reading values from here rather than reaching into individual
/// config files from feature code.
class AppConfig {
  AppConfig._();

  /// Display name based on the active environment.
  static String get appName => EnvConfig.appName;

  /// Fallback display name when env is not initialized.
  static const String defaultAppName = AppConstants.appName;

  /// Effective API base URL.
  ///
  /// Uses [EnvConfig.apiBaseUrl] when available, otherwise [ApiConfig.baseUrl].
  static String get apiBaseUrl {
    try {
      return EnvConfig.apiBaseUrl;
    } catch (_) {
      return ApiConfig.baseUrl;
    }
  }

  /// Whether debug/network logging is enabled.
  static bool get enableLogging {
    try {
      return EnvConfig.enableLogging;
    } catch (_) {
      return true;
    }
  }
}
