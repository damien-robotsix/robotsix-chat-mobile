import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/chat_session.dart';
import '../services/api_service.dart';

/// Maps a session-management failure to a user-facing message.
///
/// [ApiException] (including [AuthException]) exposes its own display
/// message; anything else falls back to its string form.
String describeSessionError(Object error) =>
    error is ApiException ? error.message : '$error';

/// Owns the session list shown in the chat drawer: the loaded
/// [sessions], their [loading] / [error] state, and the create / delete /
/// close operations.
///
/// The [ApiService] is supplied lazily through [apiProvider] because the
/// chat screen re-creates its client after login. Every operation is a
/// no-op while the provider returns `null`.
class ChatSessionController extends ChangeNotifier {
  ChatSessionController({required this.apiProvider, this.onAuthExpired});

  /// Returns the current API client, or `null` when none is configured.
  final ApiService? Function() apiProvider;

  /// Invoked when listing sessions fails because credentials expired.
  final VoidCallback? onAuthExpired;

  List<ChatSession> _sessions = const [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  List<ChatSession> get sessions => _sessions;
  bool get loading => _loading;
  String? get error => _error;

  /// Reload the session list. Failures are captured in [error] rather
  /// than thrown; an [AuthException] also triggers [onAuthExpired].
  Future<void> loadSessions() async {
    final api = apiProvider();
    if (api == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await api.listSessions();
    } catch (e) {
      _error = describeSessionError(e);
      if (e is AuthException && !_disposed) onAuthExpired?.call();
    }
    _loading = false;
    notifyListeners();
  }

  /// Create a new session and refresh the list. Returns `null` when no
  /// API client is configured. API failures are rethrown to the caller.
  Future<ChatSession?> createSession() async {
    final api = apiProvider();
    if (api == null) return null;
    final session = await api.createSession();
    unawaited(loadSessions());
    return session;
  }

  /// Delete [sessionId] and refresh the list. Returns `false` when no API
  /// client is configured. API failures are rethrown to the caller.
  Future<bool> deleteSession(String sessionId) async {
    final api = apiProvider();
    if (api == null) return false;
    await api.deleteSession(sessionId);
    unawaited(loadSessions());
    return true;
  }

  /// Close [sessionId] and refresh the list. API failures are rethrown.
  Future<void> closeSession(String sessionId) async {
    final api = apiProvider();
    if (api == null) return;
    await api.closeSession(sessionId);
    unawaited(loadSessions());
  }

  /// Title of [sessionId] if it is known and non-empty, else `null`.
  String? titleOf(String? sessionId) {
    if (sessionId == null) return null;
    for (final s in _sessions) {
      if (s.sessionId == sessionId && s.title != null && s.title!.isNotEmpty) {
        return s.title!;
      }
    }
    return null;
  }

  @override
  void notifyListeners() {
    // Async operations may complete after the screen is gone.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
