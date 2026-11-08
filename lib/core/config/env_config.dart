import 'package:trainhub/core/config/api_config.dart';

/// Supported runtime environments for the application.
enum AppEnvironment {
  /// Local / developer builds.
  development,

  /// Pre-production verification builds.
  staging,

  /// Store / production builds.
  production,
}

/// Environment-specific configuration.
///
/// Selected at startup via `--dart-define=ENV=staging` (or production).
/// Defaults to [AppEnvironment.development].
class EnvConfig {
  EnvConfig._();

  static late final AppEnvironment environment;
  static late final String appName;
  static late final bool enableLogging;
  static late final String apiBaseUrl;

  /// Initializes environment values from compile-time dart-defines.
  ///
  /// Example:
  /// ```bash
  /// flutter run --dart-define=ENV=production
  /// ```
  static void init() {
    const envName = String.fromEnvironment('ENV', defaultValue: 'production');

    environment = switch (envName.toLowerCase()) {
      'staging' => AppEnvironment.staging,
      'production' || 'prod' => AppEnvironment.production,
      _ => AppEnvironment.development,
    };

    switch (environment) {
      case AppEnvironment.development:
        appName = 'TrainHub';
        enableLogging = true;
        apiBaseUrl = ApiConfig.devBaseUrl + ApiConfig.apiVersion;
      case AppEnvironment.staging:
        appName = 'TrainHub';
        enableLogging = true;
        apiBaseUrl = ApiConfig.stagingBaseUrl + ApiConfig.apiVersion;
      case AppEnvironment.production:
        appName = 'TrainHub';
        enableLogging = false;
        apiBaseUrl = ApiConfig.baseUrl + ApiConfig.apiVersion;
    }
  }

  static bool get isDevelopment => environment == AppEnvironment.development;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get isProduction => environment == AppEnvironment.production;
}
