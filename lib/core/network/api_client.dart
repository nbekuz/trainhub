import 'package:dio/dio.dart';
import 'package:trainhub/core/config/app_config.dart';
import 'package:trainhub/core/constants/app_constants.dart';
import 'package:trainhub/core/network/auth_session.dart';
import 'package:trainhub/core/network/interceptors/interceptors.dart';
import 'package:trainhub/services/local_storage/storage_service.dart';

/// Configures and owns the shared [Dio] instance.
///
/// This is the ONLY place that should construct or configure Dio.
/// Feature/API services must go through [ApiService], never Dio directly.
class ApiClient {
  /// Creates an [ApiClient] wired with interceptors and timeouts.
  ApiClient(StorageService storage, AuthSession authSession) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(
          seconds: AppConstants.connectTimeoutSeconds,
        ),
        receiveTimeout: const Duration(
          seconds: AppConstants.receiveTimeoutSeconds,
        ),
        sendTimeout: const Duration(
          seconds: AppConstants.sendTimeoutSeconds,
        ),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
      ),
    );

    _dio.interceptors.addAll([
      AuthInterceptor(storage),
      RequestInterceptor(),
      ResponseInterceptor(),
      ErrorInterceptor(),
      PrettyLoggerInterceptor(enabled: AppConfig.enableLogging),
      TokenRefreshInterceptor(storage, _dio, authSession),
    ]);
  }

  late final Dio _dio;

  /// Exposed solely for [ApiService]. Do not use outside the network layer.
  Dio get dio => _dio;

  /// Updates the base URL at runtime (e.g. after env switch in debug tools).
  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }
}
