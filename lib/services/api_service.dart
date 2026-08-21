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

  /// The auth provider instance currently in use.
  ///
  /// Set by [fromStorage] and available for inspection (e.g. from the
  /// Settings screen).
  static AuthProvider? currentAuthProvider;

  /// Base URL of the robotsix-chat backend (e.g. https://chat.example.com).
  final String baseUrl;

  final AuthProvider _authProvider;

  ApiService({required this.baseUrl, required AuthProvider authProvider})
      : _authProvider = authProvider;

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

  /// Return (or create and persist) a stable per-install client id.
  ///
  /// This id is sent as `owner_id` with every chat request so the
  /// backend can associate sessions with this device.
  static Future<String> getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
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
    final provider = TokenExchangeAuthProvider(baseUrl: baseUrl);
    currentAuthProvider = provider;
    provider.initialize();
    return ApiService(
      baseUrl: baseUrl,
      authProvider: provider,
    );
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

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        final errorBody = await response.stream.bytesToString();
        throw ApiException(401, errorBody);
      }

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw ApiException(response.statusCode, errorBody);
      }

      yield* _parseSseStream(response.stream);
    } finally {
      client.close();
    }
  }

  /// Handle a 401 Unauthorized response by clearing the stored token
  /// and triggering the SSO re-login flow.
  Future<void> _handleUnauthorized() async {
    if (_authProvider is TokenExchangeAuthProvider) {
      final provider = _authProvider as TokenExchangeAuthProvider;
      await provider.clearToken();
      // Fire-and-forget — the user will see the auth error and can
      // re-login via Settings.
      provider.startLogin();
    }
  }

  /// Stream events for an existing session.
  ///
  /// Reattaches to `GET /events?session_id=…` as an SSE stream so the
  /// app can reload live history when switching sessions.
  Stream<ChatEvent> getEvents(String sessionId) async* {
    final uri = Uri.parse('$baseUrl/events').replace(
      queryParameters: {'session_id': sessionId},
    );
    final headers = <String, String>{
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...await _authProvider.requestHeaders(),
    };

    final request = http.Request('GET', uri);
    request.headers.addAll(headers);

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        final errorBody = await response.stream.bytesToString();
        throw ApiException(401, errorBody);
      }

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw ApiException(response.statusCode, errorBody);
      }

      yield* _parseSseStream(response.stream);
    } finally {
      client.close();
    }
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

    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 401) {
      await _handleUnauthorized();
      throw ApiException(response.statusCode, response.body);
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

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'owner_id': ownerId}),
    );
    if (response.statusCode == 401) {
      await _handleUnauthorized();
      throw ApiException(response.statusCode, response.body);
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

    final response = await http.delete(uri, headers: headers);
    if (response.statusCode == 401) {
      await _handleUnauthorized();
      throw ApiException(response.statusCode, response.body);
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

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'owner_id': ownerId}),
    );
    if (response.statusCode == 401) {
      await _handleUnauthorized();
      throw ApiException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Fetch chat history (transcript) for a session.
  Future<List<Map<String, dynamic>>> getHistory(String sessionId) async {
    final uri = Uri.parse('$baseUrl/history?session_id=$sessionId');
    final headers = await _authProvider.requestHeaders();

    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 401) {
      await _handleUnauthorized();
      throw ApiException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }
}

/// Exception raised when the backend returns a non-2xx HTTP status.
class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}
