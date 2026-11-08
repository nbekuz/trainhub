/// String manipulation helpers used across the app.
class StringHelper {
  StringHelper._();

  /// Returns true when [value] is null or blank after trim.
  static bool isNullOrEmpty(String? value) =>
      value == null || value.trim().isEmpty;

  /// Capitalizes the first character of [value].
  static String capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  /// Converts `snake_case` or `kebab-case` into Title Case words.
  static String titleCase(String value) {
    final cleaned = value.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (cleaned.isEmpty) return cleaned;
    return cleaned
        .split(RegExp(r'\s+'))
        .map(capitalize)
        .join(' ');
  }

  /// Truncates [value] to [maxLength] and appends an ellipsis when needed.
  static String truncate(String value, int maxLength, {String ellipsis = '…'}) {
    if (value.length <= maxLength) return value;
    if (maxLength <= ellipsis.length) return ellipsis.substring(0, maxLength);
    return '${value.substring(0, maxLength - ellipsis.length)}$ellipsis';
  }

  /// Masks all but the last [visible] characters (useful for tokens/phones).
  static String mask(String value, {int visible = 4, String maskChar = '*'}) {
    if (value.length <= visible) return value;
    final masked = maskChar * (value.length - visible);
    return '$masked${value.substring(value.length - visible)}';
  }
}
