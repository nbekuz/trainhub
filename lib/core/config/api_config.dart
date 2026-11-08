/// API configuration.
///
/// Change the URL constants in this file to retarget all network calls.
/// [EnvConfig] selects which URL is active based on `--dart-define=ENV=...`.
class ApiConfig {
  ApiConfig._();

  /// Production / default API base URL.
  ///
  /// For most projects, editing this single line is enough.
  static const String baseUrl = 'https://apitrain.reyt.uz/api/v1/app';
  static const String devBaseUrl = 'https://apitrain.reyt.uz/api/v1/app';
  static const String stagingBaseUrl = 'https://apitrain.reyt.uz/api/v1/app';

  /// Optional API version prefix (leave empty if unused).
  static const String apiVersion = '';
}
