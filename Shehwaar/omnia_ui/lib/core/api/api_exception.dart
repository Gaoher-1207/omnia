/// One field-level problem reported by the backend (`error.details[]`).
class FieldError {
  const FieldError(this.field, this.message);
  final String field, message;
}

/// Every failed API call surfaces as this: HTTP errors from the backend's
/// `{"error": {...}}` envelope, plus network problems (statusCode 0).
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const [],
  });

  factory ApiException.network([String? message]) => ApiException(
    statusCode: 0,
    code: 'network_error',
    message:
        message ??
        "Can't reach OMNIA right now. Check your connection and try again.",
  );

  final int statusCode;
  final String code, message;
  final List<FieldError> details;

  bool get isNetwork => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isUnavailable => statusCode == 503;

  /// The message for one form field, matched on the last path segment.
  String? fieldMessage(String field) {
    for (final detail in details) {
      if (detail.field == field || detail.field.endsWith('.$field')) {
        return detail.message;
      }
    }
    return null;
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// A short, human message for any error a screen might catch.
String friendlyError(Object error) => error is ApiException
    ? error.message
    : 'Something went wrong. Please try again.';
