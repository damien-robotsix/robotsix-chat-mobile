import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Thin wrapper around Firebase Crashlytics for crash reporting and
/// structured error telemetry.
///
/// Every method is a safe no-op until [Firebase.initializeApp] has run
/// (e.g. in unit tests, or on a platform where Firebase is not
/// configured), so call sites can record telemetry unconditionally
/// without guarding each one.
class Observability {
  const Observability._();

  /// Whether a Firebase app has been initialised. When `false`, all
  /// telemetry calls below are skipped.
  static bool get isEnabled => Firebase.apps.isNotEmpty;

  /// Report a non-fatal [error] with its [stackTrace] to Crashlytics.
  ///
  /// [reason] is a short human-readable label describing the call site
  /// (e.g. `'SSE stream error'`).
  static Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!isEnabled) return;
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  /// Attach a custom key/value pair to subsequent crash reports so the
  /// failing request can be correlated (e.g. the active `sessionId`).
  static Future<void> setCustomKey(String key, Object value) async {
    if (!isEnabled) return;
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  }
}
