import 'dart:async';

/// Debounces rapid invocations — useful for search fields and resize handlers.
class Debouncer {
  /// Creates a [Debouncer] that waits [delay] before running the last callback.
  Debouncer({this.delay = const Duration(milliseconds: 400)});

  /// Delay before the scheduled action runs.
  final Duration delay;

  Timer? _timer;

  /// Schedules [action], cancelling any previously pending call.
  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancels a pending action without running it.
  void cancel() => _timer?.cancel();

  /// Releases the internal timer. Call from `dispose`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
