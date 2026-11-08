/// Base class for all application-level exceptions.
///
/// Every custom exception exposes a human-readable [message] suitable for UI.
abstract class AppException implements Exception {
  /// Creates an [AppException] with a readable [message] and optional [code].
  const AppException(this.message, {this.code});

  /// User-facing error description.
  final String message;

  /// Optional machine-readable error code from the backend.
  final String? code;

  @override
  String toString() => message;
}

/// Thrown when the device has no connectivity or the request never reaches the server.
class NetworkException extends AppException {
  const NetworkException([
    super.message = 'No internet connection. Please check your network.',
  ]);
}

/// Thrown for non-2xx HTTP responses that are not auth/timeout specific.
class ApiException extends AppException {
  const ApiException(
    super.message, {
    super.code,
    this.statusCode,
    this.data,
  });

  /// HTTP status code when available.
  final int? statusCode;

  /// Raw response payload for debugging or mapping.
  final dynamic data;
}

/// Thrown when the server responds with 401/403.
class UnauthorizedException extends AppException {
  const UnauthorizedException([
    super.message = 'Session expired. Please sign in again.',
  ]);
}

/// Thrown when a request exceeds the configured timeout.
///
/// Prefer importing this library explicitly to avoid clashing with
/// `dart:async` TimeoutException.
class TimeoutException extends AppException {
  const TimeoutException([
    super.message = 'The request timed out. Please try again.',
  ]);
}

/// Fallback for unexpected failures.
class UnknownException extends AppException {
  const UnknownException([
    super.message = 'Something went wrong. Please try again.',
  ]);
}
