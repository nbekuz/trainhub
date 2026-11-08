/// Application-wide constant values used across the template.
///
/// Keep feature-specific constants inside their own feature folders.
class AppConstants {
  AppConstants._();

  /// Default app display name.
  static const String appName = 'TrainHub';

  /// Default request timeout in seconds.
  static const int connectTimeoutSeconds = 30;

  /// Default receive timeout in seconds.
  static const int receiveTimeoutSeconds = 30;

  /// Default send timeout in seconds.
  static const int sendTimeoutSeconds = 30;

  /// Default toast auto-dismiss duration.
  static const Duration toastDuration = Duration(seconds: 3);

  /// Splash screen display duration before navigating home.
  static const Duration splashDuration = Duration(milliseconds: 1800);
}
