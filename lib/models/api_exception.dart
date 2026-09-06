// Exception types raised by the API service.

/// Exception raised when the backend returns a non-2xx HTTP status.
class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException(this.statusCode, this.body);

  /// Human-readable message suitable for display in the UI.
  String get message => body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// Thrown when the backend returns 401 or 403, indicating the current
/// credentials have been revoked or expired.
///
/// The UI layer should catch this separately from generic
/// [ApiException] and prompt the user to re-authenticate rather than
/// showing a raw error message.
class AuthException extends ApiException {
  const AuthException(super.statusCode, super.body);

  @override
  String get message => 'Session expired. Please log in again from Settings.';
}
