import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'api_service.dart';

/// Pluggable authentication provider for the robotsix-chat backend.
///
/// The chat backend is fronted by an SSO/OIDC gateway in production.
/// Concrete providers acquire short-lived Bearer tokens and attach them
/// to outgoing HTTP requests via [requestHeaders].
abstract class AuthProvider {
  /// Return headers to attach to every outgoing HTTP request.
  ///
  /// Called before each request, so implementations can return
  /// fresh tokens (e.g. with a short-lived OAuth2 access token
  /// that is refreshed on-demand).
  Future<Map<String, String>> requestHeaders();
}

/// [AuthProvider] that exchanges an OIDC credential for a short-lived
/// Bearer token via the central-deploy mobile token-exchange endpoint
/// (`POST /chat/auth/mobile-token`).
///
/// The exchange result is cached in memory until the `expires_in`
/// window reported by the backend lapses (minus a one-minute clock-skew
/// margin), so [requestHeaders] can be called before every outgoing
/// request without performing an exchange on each call.
///
/// The OIDC credential ([subjectToken]) is expected to be supplied by
/// the app's SSO sign-in flow.  It is persisted in platform secure
/// storage via the static [saveSubjectToken] / [getSubjectToken] /
/// [clearSubjectToken] helpers so the credential survives app restarts.
class OidcTokenExchangeAuthProvider implements AuthProvider {
  static const _exchangePath = '/chat/auth/mobile-token';
  static const _clockSkew = Duration(minutes: 1);

  // ------------------------------------------------------------------
  // Static persistence (platform secure storage)
  // ------------------------------------------------------------------

  static const _subjectTokenKey = 'oidc_subject_token';
  static const _secureStorage = FlutterSecureStorage();

  /// Persist the OIDC subject token so it survives app restarts.
  static Future<void> saveSubjectToken(String token) async {
    await _secureStorage.write(key: _subjectTokenKey, value: token);
  }

  /// Return the persisted OIDC subject token, or `null` if none has
  /// been saved.
  static Future<String?> getSubjectToken() async {
    return await _secureStorage.read(key: _subjectTokenKey);
  }

  /// Remove the persisted OIDC subject token (log-out).
  static Future<void> clearSubjectToken() async {
    await _secureStorage.delete(key: _subjectTokenKey);
  }

  // ------------------------------------------------------------------
  // Instance
  // ------------------------------------------------------------------

  final String baseUrl;
  final String? subjectToken;
  final http.Client _client;
  final DateTime Function() _clock;

  String? _accessToken;
  DateTime? _expiresAt;

  OidcTokenExchangeAuthProvider({
    required this.baseUrl,
    this.subjectToken,
    http.Client? client,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// Whether the provider currently holds credentials that can be used
  /// to authenticate — either a cached access token that is still valid
  /// or a subject token available for exchange.
  bool get isLoggedIn {
    if (_accessToken != null &&
        _expiresAt != null &&
        _clock().isBefore(_expiresAt!)) {
      return true;
    }
    return subjectToken != null && subjectToken!.isNotEmpty;
  }

  /// Clear the in-memory access-token cache.
  ///
  /// Does **not** touch the persisted subject token.  The next call to
  /// [requestHeaders] will re-exchange the subject token (if one is
  /// available).
  @visibleForTesting
  void clearCache() {
    _accessToken = null;
    _expiresAt = null;
  }

  @override
  Future<Map<String, String>> requestHeaders() async {
    final token = await _freshAccessToken();
    if (token == null || token.isEmpty) {
      return {};
    }
    return {'Authorization': 'Bearer $token'};
  }

  /// Exchange [subjectToken] for a fresh access token via the
  /// mobile-token endpoint.
  ///
  /// Visible for testing so that exchange logic can be exercised
  /// directly without going through [requestHeaders].
  @visibleForTesting
  Future<String?> exchangeCodeForToken() async {
    return _freshAccessToken();
  }

  /// Return a still-valid cached access token, or exchange
  /// [subjectToken] for a fresh one when the cache is empty/expired.
  Future<String?> _freshAccessToken() async {
    final cached = _accessToken;
    final expiresAt = _expiresAt;
    if (cached != null && expiresAt != null && _clock().isBefore(expiresAt)) {
      return cached;
    }

    final subject = subjectToken;
    if (subject == null || subject.isEmpty) {
      return null;
    }

    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$base$_exchangePath');

    // Contract assumption: the endpoint accepts the OIDC credential as a
    // JSON `token` field and returns `{access_token, token_type, expires_in}`.
    final response = await _client.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'token': subject}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const FormatException(
        'Token-exchange response was not valid JSON',
      );
    } on TypeError {
      throw const FormatException(
        'Token-exchange response was not a JSON object',
      );
    }

    final accessToken =
        _stringField(payload, 'access_token') ?? _stringField(payload, 'token');
    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException(
        'Token-exchange response missing access_token',
      );
    }

    _accessToken = accessToken;
    final expiresIn = payload['expires_in'];
    if (expiresIn is num && expiresIn > 0) {
      _expiresAt = _clock()
          .add(Duration(seconds: expiresIn.toInt()))
          .subtract(_clockSkew);
    } else {
      _expiresAt = null;
    }

    return accessToken;
  }

  static String? _stringField(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }
}
