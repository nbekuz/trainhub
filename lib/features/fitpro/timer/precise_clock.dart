import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wall-clock based ticker that avoids drift from `Timer.periodic` decrement.
class PreciseClock {
  PreciseClock({this.onTick, this.interval = const Duration(milliseconds: 100)});

  VoidCallback? onTick;
  final Duration interval;

  Timer? _timer;
  DateTime? _anchor;
  Duration _accumulated = Duration.zero;
  bool _running = false;

  bool get isRunning => _running;

  Duration get elapsed {
    if (!_running || _anchor == null) return _accumulated;
    return _accumulated + DateTime.now().difference(_anchor!);
  }

  void start() {
    if (_running) return;
    _running = true;
    _anchor = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick?.call());
    onTick?.call();
  }

  void pause() {
    if (!_running) return;
    _accumulated = elapsed;
    _anchor = null;
    _running = false;
    _timer?.cancel();
    _timer = null;
    onTick?.call();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _anchor = null;
    _accumulated = Duration.zero;
    onTick?.call();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Recalculate after app resume; wall clock keeps elapsed correct.
  void sync() => onTick?.call();
}

/// Countdown that stores an absolute end time while running.
class PreciseCountdown {
  PreciseCountdown({this.onTick, this.onFinished, this.interval = const Duration(milliseconds: 100)});

  VoidCallback? onTick;
  VoidCallback? onFinished;
  final Duration interval;

  Timer? _timer;
  DateTime? _endsAt;
  Duration _remaining = Duration.zero;
  bool _running = false;
  bool _finishedNotified = false;

  bool get isRunning => _running;
  bool get isFinished => !_running && _remaining <= Duration.zero && _finishedNotified;

  Duration get remaining {
    if (_running && _endsAt != null) {
      final left = _endsAt!.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }
    return _remaining.isNegative ? Duration.zero : _remaining;
  }

  int get remainingSeconds => remaining.inMilliseconds <= 0 ? 0 : (remaining.inMilliseconds / 1000).ceil();

  void start(Duration duration) {
    _timer?.cancel();
    _finishedNotified = false;
    _remaining = duration;
    if (duration <= Duration.zero) {
      _running = false;
      _endsAt = null;
      _finishedNotified = true;
      onTick?.call();
      onFinished?.call();
      return;
    }
    _running = true;
    _endsAt = DateTime.now().add(duration);
    _timer = Timer.periodic(interval, (_) => _pulse());
    onTick?.call();
  }

  void pause() {
    if (!_running) return;
    _remaining = remaining;
    _endsAt = null;
    _running = false;
    _timer?.cancel();
    _timer = null;
    onTick?.call();
  }

  void resume() {
    if (_running || _remaining <= Duration.zero) return;
    _finishedNotified = false;
    _running = true;
    _endsAt = DateTime.now().add(_remaining);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _pulse());
    onTick?.call();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _endsAt = null;
    _remaining = Duration.zero;
    onTick?.call();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void sync() => _pulse();

  void _pulse() {
    if (_running && remaining <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
      _running = false;
      _endsAt = null;
      _remaining = Duration.zero;
      if (!_finishedNotified) {
        _finishedNotified = true;
        onTick?.call();
        onFinished?.call();
      } else {
        onTick?.call();
      }
      return;
    }
    onTick?.call();
  }
}

String formatMmSs(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final m = (safe ~/ 60).toString().padLeft(2, '0');
  final s = (safe % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String formatDurationMmSs(Duration duration) => formatMmSs(duration.inSeconds);
