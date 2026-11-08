/// Generic API envelope used when backends wrap payloads.
///
/// Adapt field names to match your API contract.
class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    this.message,
    this.data,
  });

  final bool success;
  final String? message;
  final T? data;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json)? fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String?,
      data: json['data'] == null
          ? null
          : fromJsonT != null
              ? fromJsonT(json['data'])
              : json['data'] as T?,
    );
  }
}
