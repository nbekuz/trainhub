/// Shared elapsed-time math for live workout + mini-card.
class WorkoutTimer {
  WorkoutTimer._();

  static DateTime? parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    final direct = DateTime.tryParse(text);
    if (direct != null) return direct.toLocal();
    // Postgres-ish: "2026-10-28 01:02:03.456+00"
    final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized)?.toLocal();
  }

  static bool isPaused(Map<String, dynamic>? session) {
    if (session == null) return false;
    if (session['timer_paused'] == true) return true;
    return parseDate(session['paused_at']) != null;
  }

  static int pauseSec(Map<String, dynamic>? session) {
    if (session == null) return 0;
    return int.tryParse('${session['pause_sec'] ?? 0}') ?? 0;
  }

  /// Active workout elapsed, excluding completed + current pause intervals.
  static Duration elapsed(Map<String, dynamic>? session, {DateTime? now}) {
    if (session == null) return Duration.zero;
    final started = parseDate(session['started_at']) ?? parseDate(session['created_at']);
    if (started == null) {
      final ms = int.tryParse('${session['started_at_ms'] ?? ''}');
      if (ms == null || ms <= 0) return Duration.zero;
      return _elapsedFromMs(ms, session, now: now);
    }
    final clock = now ?? DateTime.now();
    final pausedAt = parseDate(session['paused_at']);
    final end = pausedAt ?? clock;
    var sec = end.difference(started).inSeconds - pauseSec(session);
    if (sec < 0) sec = 0;
    return Duration(seconds: sec);
  }

  static Duration _elapsedFromMs(int startedMs, Map<String, dynamic> session, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final started = DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: false);
    final pausedAt = parseDate(session['paused_at']);
    final end = pausedAt ?? clock;
    var sec = end.difference(started).inSeconds - pauseSec(session);
    if (sec < 0) sec = 0;
    return Duration(seconds: sec);
  }

  static String format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  /// Apply local pause to a session map (immutable-style copy).
  static Map<String, dynamic> withPause(Map<String, dynamic> session, {DateTime? at}) {
    if (isPaused(session)) return Map<String, dynamic>.from(session);
    final copy = Map<String, dynamic>.from(session);
    copy['paused_at'] = (at ?? DateTime.now()).toUtc().toIso8601String();
    copy['timer_paused'] = true;
    return copy;
  }

  /// Apply local resume to a session map.
  static Map<String, dynamic> withResume(Map<String, dynamic> session, {DateTime? at}) {
    if (!isPaused(session)) return Map<String, dynamic>.from(session);
    final copy = Map<String, dynamic>.from(session);
    final pausedAt = parseDate(session['paused_at']);
    final clock = at ?? DateTime.now();
    var extra = 0;
    if (pausedAt != null) {
      extra = clock.difference(pausedAt).inSeconds;
      if (extra < 0) extra = 0;
    }
    copy['pause_sec'] = pauseSec(session) + extra;
    copy['paused_at'] = null;
    copy['timer_paused'] = false;
    return copy;
  }

  /// Ensure snapshot has a parseable start anchor for the mini-card.
  static Map<String, dynamic> withStartAnchor(Map<String, dynamic> session) {
    final copy = Map<String, dynamic>.from(session);
    final started = parseDate(copy['started_at']) ?? parseDate(copy['created_at']);
    if (started != null) {
      copy['started_at'] = started.toUtc().toIso8601String();
      copy['started_at_ms'] = started.millisecondsSinceEpoch;
    } else if (copy['started_at_ms'] == null) {
      final now = DateTime.now();
      copy['started_at'] = now.toUtc().toIso8601String();
      copy['started_at_ms'] = now.millisecondsSinceEpoch;
    }
    return copy;
  }
}
