import 'dart:convert';

import 'package:http/http.dart' as http;

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
/// the app's SSO sign-in flow.  Until that flow is wired into the UI it
/// is read from secure storage, mirroring how the previous manual token
/// was persisted.
class OidcTokenExchangeAuthProvider implements AuthProvider {
  static const _exchangePath = '/chat/auth/mobile-token';
  static const _clockSkew = Duration(minutes: 1);

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

  @override
  Future<Map<String, String>> requestHeaders() async {
    final token = await _freshAccessToken();
    if (token == null || token.isEmpty) {
      return {};
    }
    return {'Authorization': 'Bearer $token'};
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
