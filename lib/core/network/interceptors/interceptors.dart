import 'package:dio/dio.dart';
import 'package:trainhub/core/logger/app_logger.dart';
import 'package:trainhub/core/network/auth_session.dart';
import 'package:trainhub/services/local_storage/storage_service.dart';

enum _RefreshOutcome { ok, invalid, unavailable }

/// Renews the access token once on 401, then retries the original request.
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor(this._storage, this._dio, this._authSession);

  final StorageService _storage;
  final Dio _dio;
  final AuthSession _authSession;
  Future<_RefreshOutcome>? _refreshing;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;
    final retried = err.requestOptions.extra['retried'] == true;
    final refresh = _storage.getRefreshToken();
    if (status != 401 || retried || refresh == null || refresh.isEmpty || path.contains('/auth/')) {
      handler.next(err);
      return;
    }

    final outcome = await (_refreshing ??= _refresh(refresh));
    _refreshing = null;
    if (outcome == _RefreshOutcome.invalid) {
      await _storage.clearAuth();
      _authSession.notifyInvalidated();
      handler.next(err);
      return;
    }
    if (outcome == _RefreshOutcome.unavailable) {
      // Keep tokens: server/network blip (e.g. DB down) must not wipe a valid session.
      handler.next(err);
      return;
    }

    try {
      final request = err.requestOptions;
      request.extra['retried'] = true;
      request.headers['Authorization'] = 'Bearer ${_storage.getToken()}';
      final response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  Future<_RefreshOutcome> _refresh(String refresh) async {
    final plain = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ),
    );
    try {
      final response = await plain.post<dynamic>('/auth/refresh', data: {'refresh_token': refresh});
      final body = response.data;
      final data = body is Map && body['data'] is Map ? body['data'] as Map : body;
      if (data is! Map) return _RefreshOutcome.invalid;
      final access = data['access_token']?.toString();
      final next = data['refresh_token']?.toString();
      if (access == null || access.isEmpty) return _RefreshOutcome.invalid;
      await _storage.saveToken(access);
      if (next != null && next.isNotEmpty) await _storage.saveRefreshToken(next);
      return _RefreshOutcome.ok;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final code = _errorCode(error.response?.data);
      if (status == 401 || status == 403 || code == 'INVALID_TOKEN' || code == 'UNAUTHORIZED') {
        return _RefreshOutcome.invalid;
      }
      return _RefreshOutcome.unavailable;
    } catch (_) {
      return _RefreshOutcome.unavailable;
    } finally {
      plain.close();
    }
  }

  String? _errorCode(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final code = error['code']?.toString();
        if (code != null && code.isNotEmpty) return code;
      }
      final code = data['code']?.toString();
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }
}

/// Attaches the Bearer authorization token to outgoing requests.
///
/// Reads the token from [StorageService]. Skips attachment when empty.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage);

  final StorageService _storage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _storage.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Logs basic request metadata in debug builds.
class RequestInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.d(
      '→ ${options.method} ${options.uri}\n'
      'headers: ${options.headers}\n'
      'query: ${options.queryParameters}\n'
      'data: ${options.data}',
    );
    handler.next(options);
  }
}

/// Logs successful responses in debug builds.
class ResponseInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    AppLogger.d(
      '← ${response.statusCode} ${response.requestOptions.uri}\n'
      'data: ${response.data}',
    );
    handler.next(response);
  }
}

/// Maps Dio errors into structured logs before they bubble up.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.e(
      '✕ ${err.requestOptions.method} ${err.requestOptions.uri}\n'
      'type: ${err.type}\n'
      'status: ${err.response?.statusCode}\n'
      'message: ${err.message}\n'
      'data: ${err.response?.data}',
      err,
      err.stackTrace,
    );
    handler.next(err);
  }
}

/// Pretty Dio logger that prints compact, readable request/response blocks.
///
/// Only emits output when [enabled] is true (typically debug / non-prod).
class PrettyLoggerInterceptor extends Interceptor {
  PrettyLoggerInterceptor({this.enabled = true});

  final bool enabled;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      AppLogger.i('HTTP REQUEST ━━━ ${options.method} ${options.uri}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (enabled) {
      AppLogger.i(
        'HTTP RESPONSE ━━━ ${response.statusCode} ${response.requestOptions.uri}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      AppLogger.w(
        'HTTP ERROR ━━━ ${err.type} ${err.requestOptions.uri}',
      );
    }
    handler.next(err);
  }
}
