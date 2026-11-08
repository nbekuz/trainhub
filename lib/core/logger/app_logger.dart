import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Pretty application logger enabled only in debug builds.
///
/// Use [AppLogger.d], [AppLogger.i], [AppLogger.w], [AppLogger.e] throughout
/// the codebase instead of `print`.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: kDebugMode ? Level.debug : Level.off,
  );

  /// Debug-level log.
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Info-level log.
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning-level log.
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error-level log.
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
}
