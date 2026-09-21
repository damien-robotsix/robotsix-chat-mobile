import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/api_exception.dart';
import 'observability.dart';

// ---------------------------------------------------------------------------
// Network resilience helpers
// ---------------------------------------------------------------------------
//
// Fleet-wide network resilience convention: explicit timeouts plus retry
// with exponential backoff for transient failures.  Shared by the HTTP
// services so retry/timeout behaviour is consistent across the app.

/// Timeout applied while establishing a connection / awaiting the initial
/// response (including SSE stream handshakes).
const Duration kConnectionTimeout = Duration(seconds: 15);

/// Timeout applied while reading a (non-streaming) response body.
const Duration kReadTimeout = Duration(seconds: 30);

/// Per-retry backoff schedule: the delay applied *before* attempt N+1.
///
/// Attempt 1 fails -> wait 100ms -> attempt 2 fails -> wait 300ms ->
/// attempt 3 fails -> wait 1000ms -> attempt 4 ...  With the default of
/// 3 attempts only the first two delays are ever used; the third is kept
/// so callers that raise [withRetry]'s `maxAttempts` inherit a sensible
/// schedule.
const List<Duration> kRetryBackoff = <Duration>[
  Duration(milliseconds: 100),
  Duration(milliseconds: 300),
  Duration(milliseconds: 1000),
];

/// Classify [error] as transient (worth retrying) or fatal.
///
/// Transient failures are network-level errors ([SocketException],
/// [http.ClientException], [HttpException], [TimeoutException]) and server
/// responses that may succeed on a retry (HTTP 408, 429 and any 5xx).
///
/// Fatal failures are authentication errors ([AuthException] / HTTP
/// 401 / 403), other 4xx client errors and malformed payloads
/// ([FormatException]) — retrying these cannot help.
bool isTransientError(dynamic error) {
  if (error is AuthException) return false;
  if (error is ApiException) {
    final code = error.statusCode;
    return code == 408 || code == 429 || code >= 500;
  }
  if (error is TimeoutException) return true;
  if (error is SocketException) return true;
  if (error is http.ClientException) return true;
  if (error is HttpException) return true;
  if (error is FormatException) return false;
  return false;
}

/// Run [fn], retrying on transient failures with exponential backoff.
///
/// Makes up to [maxAttempts] attempts (default 3), waiting per
/// [kRetryBackoff] between them.  Errors classified as fatal by
/// [isTransientError] are rethrown immediately; the last error is
/// rethrown once attempts are exhausted.  Each retry is reported to
/// Crashlytics (tagged with [label] when provided) for observability.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  String? label,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await fn();
    } catch (error, stackTrace) {
      final canRetry = attempt < maxAttempts && isTransientError(error);
      if (!canRetry) rethrow;
      await Observability.recordError(
        error,
        stackTrace,
        reason:
            'retrying transient failure'
            "${label != null ? ' [$label]' : ''}"
            ' (attempt $attempt/$maxAttempts)',
      );
      final delay =
          kRetryBackoff[(attempt - 1).clamp(0, kRetryBackoff.length - 1)];
      await Future<void>.delayed(delay);
    }
  }
}
