/// Form field validators returning null on success or an error message.
class Validator {
  Validator._();

  /// Requires a non-empty value.
  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  /// Validates a basic email pattern.
  static String? email(String? value) {
    final requiredError = required(value, field: 'Email');
    if (requiredError != null) return requiredError;

    final regex = RegExp(r'^[\w.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!regex.hasMatch(value!.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Validates password length (default min 8).
  static String? password(String? value, {int minLength = 8}) {
    final requiredError = required(value, field: 'Password');
    if (requiredError != null) return requiredError;

    if (value!.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }

  /// Confirms that [value] matches [other].
  static String? confirmPassword(String? value, String? other) {
    final requiredError = required(value, field: 'Confirm password');
    if (requiredError != null) return requiredError;
    if (value != other) return 'Passwords do not match';
    return null;
  }

  /// Validates a phone number with a simple digit-length check.
  static String? phone(String? value, {int minLength = 9}) {
    final requiredError = required(value, field: 'Phone');
    if (requiredError != null) return requiredError;

    final digits = value!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < minLength) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  /// Validates minimum string length.
  static String? minLength(String? value, int min, {String field = 'Value'}) {
    final requiredError = required(value, field: field);
    if (requiredError != null) return requiredError;
    if (value!.length < min) return '$field must be at least $min characters';
    return null;
  }

  /// Validates maximum string length.
  static String? maxLength(String? value, int max, {String field = 'Value'}) {
    if (value != null && value.length > max) {
      return '$field must be at most $max characters';
    }
    return null;
  }
}
