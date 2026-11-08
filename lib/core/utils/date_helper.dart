import 'package:intl/intl.dart';

/// Date/time formatting. Server timestamps are UTC ISO; UI shows local Russian.
class DateHelper {
  DateHelper._();

  static const _monthsRu = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const _monthsRuShort = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];

  static final DateFormat _date = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _display = DateFormat('MMM d, yyyy');
  static final DateFormat _time = DateFormat('HH:mm');

  /// Formats [date] as `yyyy-MM-dd`.
  static String formatDate(DateTime date) => _date.format(date);

  /// Formats [date] as `yyyy-MM-dd HH:mm`.
  static String formatDateTime(DateTime date) => _dateTime.format(date);

  /// Formats [date] as a human-readable display string.
  static String formatDisplay(DateTime date) => _display.format(date);

  /// Formats [date] as `HH:mm`.
  static String formatTime(DateTime date) => _time.format(date.toLocal());

  /// Parses ISO-8601 / common date string (keeps UTC awareness when present).
  static DateTime? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  /// Parses server time and converts to device local.
  static DateTime? parseLocal(String? value) {
    final parsed = tryParse(value);
    return parsed?.toLocal();
  }

  /// `18:15 26 октября 2020 г.`
  static String formatRuDateTime(DateTime date) {
    final local = date.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final month = _monthsRu[local.month - 1];
    return '$hh:$mm ${local.day} $month ${local.year} г.';
  }

  /// `26 октября 2020 г.`
  static String formatRuDate(DateTime date) {
    final local = date.toLocal();
    final month = _monthsRu[local.month - 1];
    return '${local.day} $month ${local.year} г.';
  }

  /// `14 сентября 2026` (no «г.»)
  static String formatRuDayMonthYear(DateTime date) {
    final local = date.toLocal();
    return '${local.day} ${_monthsRu[local.month - 1]} ${local.year}';
  }

  /// `14 авг 2026`
  static String formatRuShortDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day} ${_monthsRuShort[local.month - 1]} ${local.year}';
  }

  /// Accepts ISO / DateTime / null → Russian local string, or [fallback].
  static String formatRuAny(Object? raw, {String fallback = '—', bool withTime = true}) {
    if (raw == null) return fallback;
    if (raw is DateTime) {
      return withTime ? formatRuDateTime(raw) : formatRuDate(raw);
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == '—' || text == 'null') return fallback;
    final local = parseLocal(text);
    if (local == null) return fallback;
    return withTime ? formatRuDateTime(local) : formatRuDate(local);
  }

  /// Short date from ISO / DateTime, e.g. `14 авг 2026`.
  static String formatRuShortAny(Object? raw, {String fallback = '—'}) {
    if (raw == null) return fallback;
    if (raw is DateTime) return formatRuShortDate(raw);
    final local = parseLocal(raw.toString());
    if (local == null) return fallback;
    return formatRuShortDate(local);
  }

  /// Day + full month + year from ISO / DateTime, e.g. `14 сентября 2026`.
  static String formatRuDayMonthYearAny(Object? raw, {String fallback = '—'}) {
    if (raw == null) return fallback;
    if (raw is DateTime) return formatRuDayMonthYear(raw);
    final local = parseLocal(raw.toString());
    if (local == null) return fallback;
    return formatRuDayMonthYear(local);
  }

  /// Returns a relative label like "Just now", "5m ago", "Yesterday".
  static String timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date.toLocal());

    if (diff.inSeconds < 60) return 'Только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    if (diff.inDays == 1) return 'Вчера';
    if (diff.inDays < 7) return '${diff.inDays} дн назад';
    return formatRuDate(date);
  }
}
