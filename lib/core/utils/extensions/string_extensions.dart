import 'package:trainhub/core/utils/string_helper.dart';

/// String convenience extensions.
extension StringExtensions on String {
  /// Trims and checks emptiness.
  bool get isBlank => trim().isEmpty;

  /// Negation of [isBlank].
  bool get isNotBlank => !isBlank;

  /// Capitalizes the first character.
  String get capitalized => StringHelper.capitalize(this);

  /// Title-cases the string.
  String get titleCased => StringHelper.titleCase(this);

  /// Truncates with ellipsis.
  String ellipsize(int maxLength) => StringHelper.truncate(this, maxLength);
}

/// Nullable string helpers.
extension NullableStringExtensions on String? {
  bool get isNullOrBlank => this == null || this!.trim().isEmpty;
}
