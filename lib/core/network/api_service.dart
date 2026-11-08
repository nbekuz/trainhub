import 'package:dio/dio.dart';
import 'package:trainhub/core/exceptions/app_exceptions.dart';
import 'package:trainhub/core/network/api_client.dart';

/// Thin wrapper around Dio exposing only GET / POST / PUT / PATCH / DELETE.
///
/// Every feature API service MUST call these methods instead of using Dio.
class ApiService {
  /// Creates an [ApiService] backed by [ApiClient].
  ApiService(this._client);

  final ApiClient _client;

  /// Performs an HTTP GET request.
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      () => _client.dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  /// Performs an HTTP POST request.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      () => _client.dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  /// Performs an HTTP PUT request.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      () => _client.dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  /// Performs an HTTP PATCH request.
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      () => _client.dio.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  /// Performs an HTTP DELETE request.
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _request(
      () => _client.dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      ),
    );
  }

  /// POST with `multipart/form-data` (avatar, photo-progress, etc.).
  Future<Response<T>> postMultipart<T>(
    String path, {
    required FormData data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) {
    return _request(
      () => _client.dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(contentType: 'multipart/form-data'),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      ),
    );
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _mapDioException(e);
    } catch (e) {
      throw UnknownException(e.toString());
    }
  }

  AppException _mapDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutException();
      case DioExceptionType.connectionError:
        return const NetworkException();
      case DioExceptionType.badResponse:
        return _mapStatusCode(error);
      case DioExceptionType.cancel:
        return const ApiException('Request was cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkException('SSL certificate error.');
      case DioExceptionType.unknown:
        return UnknownException(
          error.message ?? 'An unexpected network error occurred.',
        );
    }
  }

  AppException _mapStatusCode(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final message = _extractMessage(data) ??
        error.message ??
        'Request failed with status $status';
    final code = _extractCode(data);

    if (status == 401 || status == 403) {
      return UnauthorizedException(message);
    }

    return ApiException(message, code: code, statusCode: status, data: data);
  }

  String? _extractCode(dynamic data) {
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

  String? _extractMessage(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      final detail = data['detail'];
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) return first['msg'] as String;
      }
      final candidates = ['message', 'error', 'detail', 'msg'];
      for (final key in candidates) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }
}
