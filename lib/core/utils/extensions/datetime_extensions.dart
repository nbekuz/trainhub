import 'package:trainhub/core/utils/date_helper.dart';

/// [DateTime] convenience extensions.
extension DateTimeExtensions on DateTime {
  /// `yyyy-MM-dd`
  String get asDate => DateHelper.formatDate(this);

  /// `yyyy-MM-dd HH:mm`
  String get asDateTime => DateHelper.formatDateTime(this);

  /// Human-readable display format.
  String get asDisplay => DateHelper.formatDisplay(this);

  /// Local Russian: `18:15 26 октября 2020 г.`
  String get asRuDateTime => DateHelper.formatRuDateTime(this);

  /// Local Russian date only: `26 октября 2020 г.`
  String get asRuDate => DateHelper.formatRuDate(this);

  /// Relative time label.
  String get asTimeAgo => DateHelper.timeAgo(this);

  /// Whether this date is today (local).
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }
}
