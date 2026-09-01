import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// SSE events from the POST /chat stream
// ---------------------------------------------------------------------------

/// Events emitted by the chat backend's SSE response stream.
sealed class ChatEvent {
  const ChatEvent();
}

/// A content token to append to the agent's reply in order.
class TokenEvent extends ChatEvent {
  final String content;
  const TokenEvent(this.content);
}

/// Terminal — the reply is complete.  Adopt [sessionId] for subsequent
/// messages (it may differ from the one you sent).
class DoneEvent extends ChatEvent {
  final String sessionId;
  final double timestamp;
  const DoneEvent({required this.sessionId, required this.timestamp});
}

/// Terminal — the backend rejected the request.
class ErrorEvent extends ChatEvent {
  final String message;
  final String code;
  final String? correlationId;
  const ErrorEvent({
    required this.message,
    required this.code,
    this.correlationId,
  });
}

// ---------------------------------------------------------------------------
// Session model (lightweight, parsed from JSON)
// ---------------------------------------------------------------------------

/// A chat session returned by GET /sessions.
class ChatSession {
  final String sessionId;
  final String? title;
  final int? turnCount;

  const ChatSession({
    required this.sessionId,
    this.title,
    this.turnCount,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      sessionId: json['session_id'] as String,
      title: json['title'] as String?,
      turnCount: json['turn_count'] as int?,
    );
  }
}

// ---------------------------------------------------------------------------
// API service
// ---------------------------------------------------------------------------

/// HTTP + SSE client for the robotsix-chat backend.
///
/// Talks to the real chat backend endpoints:
/// - `POST /chat` — send a message, receive an SSE reply stream
/// - `GET /sessions` — list sessions for the current owner
/// - `POST /sessions` — create a session
/// - `DELETE /sessions/{id}` — delete a session
/// - `POST /sessions/{id}/close` — close a session
/// - `GET /history` — fetch transcript for a session
///
/// Authentication is delegated to a pluggable [AuthProvider] so the
/// concrete token-exchange flow can be swapped in later.
class ApiService {
  static const _baseUrlKey = 'api_base_url';
  static const _ownerIdKey = 'owner_id';

  /// Base URL of the robotsix-chat backend (e.g. https://chat.example.com).
  final String baseUrl;

  final AuthProvider _authProvider;
  final http.Client _client;

  ApiService({
    required this.baseUrl,
    required AuthProvider authProvider,
    http.Client? client,
  })  : _authProvider = authProvider,
        _client = client ?? http.Client();

  // ------------------------------------------------------------------
  // Persistent config helpers
  // ------------------------------------------------------------------

  /// Persist the backend base URL to local storage under the key
  /// `api_base_url` so [fromStorage] can find it.
  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  /// Return the stored base URL from the `api_base_url` key, or `null`
  /// if none has been saved.
  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey);
  }

  /// Return the `owner_id` used to associate conversations with the
  /// current user.
  ///
  /// When the user is authenticated via SSO, the id is derived from the
  /// authenticated subject (the `sub` claim of the signed OIDC token)
  /// so that conversations are attributable to the user across devices
  /// and match the set the web backend associates with the same
  /// subject.  The derived subject is persisted under `owner_id`,
  /// migrating/replacing any previously-generated random per-install id.
  ///
  /// When no SSO identity is available (e.g. before login), a stable
  /// per-install id is generated and reused as a fallback.
  static Future<String> getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();

    final subjectToken =
        await OidcTokenExchangeAuthProvider.getSubjectToken();
    final subject =
        OidcTokenExchangeAuthProvider.subjectFromToken(subjectToken);
    if (subject != null) {
      // Migrate/replace any locally-generated random id with the
      // authenticated SSO subject.
      if (prefs.getString(_ownerIdKey) != subject) {
        await prefs.setString(_ownerIdKey, subject);
      }
      return subject;
    }

    final existing = prefs.getString(_ownerIdKey);
    if (existing != null) return existing;
    final id = _generateId(16);
    await prefs.setString(_ownerIdKey, id);
    return id;
  }

  static String _generateId(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  /// Create an [ApiService] from previously-stored credentials.
  ///
  /// Throws [StateError] when no base URL has been saved.
  static Future<ApiService> fromStorage() async {
    final baseUrl = await getBaseUrl();
    if (baseUrl == null) {
      throw StateError('No base URL configured. Open Settings to configure.');
    }
    final token = await OidcTokenExchangeAuthProvider.getSubjectToken();
    return ApiService(
      baseUrl: baseUrl,
      authProvider: OidcTokenExchangeAuthProvider(
        baseUrl: baseUrl,
        subjectToken: token,
      ),
    );
  }

  /// Clear the persisted subject token after a 401/403 — but only when
  /// this client actually holds credentials.
  ///
  /// A stale client that was initialised before login has no token to
  /// exchange, so a 401 from it must not wipe a credential that a newer
  /// auth flow saved to storage.
  Future<void> _clearSubjectTokenIfAuthenticated() async {
    final provider = _authProvider;
    if (provider is OidcTokenExchangeAuthProvider && provider.isLoggedIn) {
      await OidcTokenExchangeAuthProvider.clearSubjectToken();
    }
  }

  // ------------------------------------------------------------------
  // Chat — POST /chat returns an SSE stream
  // ------------------------------------------------------------------

  /// Send a chat message and stream the agent's reply via SSE.
  ///
  /// POSTs to `$baseUrl/chat` with `{message, session_id, owner_id,
  /// message_id}`.  The response body is `text/event-stream`; each
  /// SSE frame is parsed and yielded as a [ChatEvent].
  ///
  /// Omit [sessionId] on the very first message of a conversation —
  /// the backend creates one and returns it in the [DoneEvent].
  /// Pass it on every subsequent message.
  Stream<ChatEvent> sendMessage({
    required String message,
    String? sessionId,
    String? messageId,
  }) async* {
    final uri = Uri.parse('$baseUrl/chat');
    final ownerId = await getOwnerId();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...await _authProvider.requestHeaders(),
    };

    final body = <String, dynamic>{
      'message': message,
      'owner_id': ownerId,
    };
    if (sessionId != null) body['session_id'] = sessionId;
    if (messageId != null) body['message_id'] = messageId;

    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);

    final response = await _client.send(request);

    if (response.statusCode == 401 || response.statusCode == 403) {
      final errorBody = await response.stream.bytesToString();
      await _clearSubjectTokenIfAuthenticated();
      throw AuthException(response.statusCode, errorBody);
    }
    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw ApiException(response.statusCode, errorBody);
    }

    yield* _parseSseStream(response.stream);
  }

  /// Parse an SSE byte-stream into [ChatEvent]s.
  Stream<ChatEvent> _parseSseStream(http.ByteStream stream) async* {
    String buffer = '';
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (buffer.contains('\n')) {
        final newlineIdx = buffer.indexOf('\n');
        final line = buffer.substring(0, newlineIdx);
        buffer = buffer.substring(newlineIdx + 1);

        final trimmed = line.trim();
        // SSE comments (heartbeats like ": keepalive") — skip.
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;

        if (trimmed.startsWith('data: ')) {
          final data = trimmed.substring(6).trim();
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = json['type'] as String?;
            switch (type) {
              case 'token':
                yield TokenEvent((json['content'] as String?) ?? '');
              case 'done':
                yield DoneEvent(
                  sessionId: (json['session_id'] as String?) ?? '',
                  timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
                );
              case 'error':
                yield ErrorEvent(
                  message: (json['message'] as String?) ?? 'Unknown error',
                  code: (json['code'] as String?) ?? 'unknown',
                  correlationId: json['correlation_id'] as String?,
                );
            }
          } on FormatException {
            // Malformed JSON frame — skip silently.
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------
  // Sessions
  // ------------------------------------------------------------------

  /// List sessions for the current owner.
  Future<List<ChatSession>> listSessions() async {
    final ownerId = await getOwnerId();
    final uri = Uri.parse('$baseUrl/sessions?owner_id=$ownerId');
    final headers = await _authProvider.requestHeaders();

    final response = await _client.get(uri, headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _clearSubjectTokenIfAuthenticated();
      throw AuthException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a new session.
  Future<ChatSession> createSession() async {
    final ownerId = await getOwnerId();
    final uri = Uri.parse('$baseUrl/sessions');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...await _authProvider.requestHeaders(),
    };

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode({'owner_id': ownerId}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _clearSubjectTokenIfAuthenticated();
      throw AuthException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }

    return ChatSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Delete a session.
  Future<void> deleteSession(String sessionId) async {
    final ownerId = await getOwnerId();
    final uri = Uri.parse('$baseUrl/sessions/$sessionId?owner_id=$ownerId');
    final headers = await _authProvider.requestHeaders();

    final response = await _client.delete(uri, headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _clearSubjectTokenIfAuthenticated();
      throw AuthException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Close a session.
  Future<void> closeSession(String sessionId) async {
    final ownerId = await getOwnerId();
    final uri = Uri.parse('$baseUrl/sessions/$sessionId/close');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...await _authProvider.requestHeaders(),
    };

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode({'owner_id': ownerId}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _clearSubjectTokenIfAuthenticated();
      throw AuthException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Fetch chat history (transcript) for a session.
  ///
  /// The backend returns an object of the form `{"turns": [...]}`; the
  /// transcript turns are read from the `turns` field.
  Future<List<Map<String, dynamic>>> getHistory(String sessionId) async {
    final uri = Uri.parse('$baseUrl/history?session_id=$sessionId');
    final headers = await _authProvider.requestHeaders();

    final response = await _client.get(uri, headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _clearSubjectTokenIfAuthenticated();
      throw AuthException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final turns = decoded['turns'] as List<dynamic>? ?? const <dynamic>[];
    return turns.cast<Map<String, dynamic>>();
  }
}

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
