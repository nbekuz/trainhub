import 'package:flutter/services.dart';

/// Russian phone helpers: display `+7 999-999-99-99`, API `+79999999999`.
class RuPhone {
  RuPhone._();

  static final _nonDigit = RegExp(r'\D');

  /// Digits only from any raw input.
  static String digitsOnly(String raw) => raw.replaceAll(_nonDigit, '');

  /// 10-digit national number (no country code).
  ///
  /// The UI always shows `+7 …`, so [digitsOnly] of the field text includes that
  /// country `7`. We always strip one leading 7/8 so typing does not produce
  /// doubled sevens (`+7 77…`).
  static String nationalDigits(String? raw) {
    var digits = digitsOnly(raw ?? '');
    if (digits.isEmpty) return '';

    // 8XXXXXXXXXX / 7XXXXXXXXXX / +7… paste
    while (digits.length >= 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }

    // Field value is always formatted with `+7`, so one leading 7/8 is the
    // country code — never part of the national number.
    if (digits.startsWith('7') || digits.startsWith('8')) {
      digits = digits.substring(1);
    }

    if (digits.length > 10) digits = digits.substring(0, 10);
    return digits;
  }

  /// UI value with stable `+7` prefix.
  /// When [emptyIfBlank] is true and there are no national digits, returns `''`
  /// (for optional fields like WhatsApp).
  static String formatDisplay(String? raw, {bool emptyIfBlank = false}) {
    final national = nationalDigits(raw);
    if (national.isEmpty) return emptyIfBlank ? '' : '+7 ';

    final buffer = StringBuffer('+7 ');
    buffer.write(national.substring(0, national.length.clamp(0, 3)));
    if (national.length > 3) {
      buffer.write('-');
      buffer.write(national.substring(3, national.length.clamp(3, 6)));
    }
    if (national.length > 6) {
      buffer.write('-');
      buffer.write(national.substring(6, national.length.clamp(6, 8)));
    }
    if (national.length > 8) {
      buffer.write('-');
      buffer.write(national.substring(8, national.length.clamp(8, 10)));
    }
    return buffer.toString();
  }

  /// E.164 for API (`+79991234567`), or null when incomplete/empty.
  static String? toApi(String? raw) {
    final national = nationalDigits(raw);
    if (national.length < 10) return null;
    return '+7$national';
  }
}

/// Keeps the field in `+7 999-999-99-99` while typing.
class RuPhoneInputFormatter extends TextInputFormatter {
  const RuPhoneInputFormatter({this.allowEmpty = false});

  /// When true, clearing the field stays empty (optional WhatsApp).
  final bool allowEmpty;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final rawDigits = RuPhone.digitsOnly(newValue.text);
    // Only country code left, or wiped — keep optional fields blank.
    if (allowEmpty && (rawDigits.isEmpty || rawDigits == '7' || rawDigits == '8')) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final formatted = RuPhone.formatDisplay(newValue.text, emptyIfBlank: allowEmpty);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
