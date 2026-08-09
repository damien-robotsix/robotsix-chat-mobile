import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// HTTP + SSE client for the robotsix-chat backend.
///
/// Provides [sendMessage] for request/response chat and [messageStream]
/// for real-time Server-Sent Events.  Authentication is handled via a
/// Bearer token passed to the constructor or loaded from persistent
/// storage through the static helpers ([saveToken], [getToken], …).
class ApiService {
  static const _baseUrlKey = 'api_base_url';
  static const _tokenKey = 'api_token';

  /// Base URL of the robotsix-chat backend (e.g. https://chat.example.com).
  final String baseUrl;

  /// Authentication token for the backend.
  final String? token;

  const ApiService({required this.baseUrl, this.token});

  // ------------------------------------------------------------------
  // Persistent config / token helpers
  // ------------------------------------------------------------------

  /// Persist the backend base URL so [fromStorage] can find it.
  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  /// Return the stored base URL, or `null` if none has been saved.
  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey);
  }

  /// Persist an API token for later use.
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Return the stored API token, or `null` if none has been saved.
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Remove the stored API token (log-out).
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Create an [ApiService] from previously-stored credentials.
  ///
  /// Throws [StateError] when no base URL has been saved.
  static Future<ApiService> fromStorage() async {
    final baseUrl = await getBaseUrl();
    if (baseUrl == null) {
      throw StateError('No base URL configured. Open Settings to configure.');
    }
    final token = await getToken();
    return ApiService(baseUrl: baseUrl, token: token);
  }

  // ------------------------------------------------------------------
  // Chat API
  // ------------------------------------------------------------------

  /// Send a chat message to the backend and return the agent's response.
  ///
  /// Posts JSON `{"message": "…"}` to `$baseUrl/api/chat`.  Includes a
  /// Bearer token header when [token] is non-null and non-empty.
  /// Throws [ApiException] when the server returns a non-200 status.
  Future<String> sendMessage(String message) async {
    final uri = Uri.parse('$baseUrl/api/chat');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'message': message}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['response'] as String?) ?? '';
    } else {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Connect to the SSE event stream for real-time agent messages.
  ///
  /// Opens a long-lived GET to `$baseUrl/api/chat/stream` with an
  /// `Accept: text/event-stream` header.  Each `data:` line whose
  /// payload is non-empty and not the sentinel `[DONE]` is yielded
  /// as a separate string event.
  ///
  /// Throws [ApiException] when the server returns a non-200 status
  /// on the initial handshake.
  Stream<String> messageStream() async* {
    final uri = Uri.parse('$baseUrl/api/chat/stream');
    final client = http.Client();

    try {
      final request = http.Request('GET', uri);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      if (token != null && token!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw ApiException(response.statusCode, body);
      }

      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n')) {
          final newlineIdx = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIdx).trim();
          buffer = buffer.substring(newlineIdx + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data.isNotEmpty && data != '[DONE]') {
              yield data;
            }
          }
        }
      }
    } finally {
      client.close();
    }
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
