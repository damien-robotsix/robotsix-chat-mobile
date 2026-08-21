import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';

/// Pluggable authentication provider for the robotsix-chat backend.
///
/// The chat backend is fronted by an SSO/OIDC gateway (tinyauth) in
/// production; the mobile app uses a pluggable [AuthProvider] so the
/// concrete token-acquisition flow can be swapped without touching
/// the API service.
abstract class AuthProvider {
  /// Return headers to attach to every outgoing HTTP request.
  ///
  /// Called before each request, so implementations can return
  /// fresh tokens (e.g. with a short-lived OAuth2 access token
  /// that is refreshed on-demand).
  Future<Map<String, String>> requestHeaders();
}

/// [AuthProvider] that exchanges a tinyauth SSO session for a
/// long-lived Bearer token.
///
/// On first launch (or after token expiry / 401), the user is sent
/// to the fleet SSO login in an external browser / Chrome Custom Tab.
/// After successful login the SSO provider redirects to the app's
/// custom scheme (`robotsixchat://callback?code=…`); the provider
/// listens for this deep link, calls `GET /auth/token` to exchange
/// the SSO session for the Bearer token, stores it in secure storage,
/// and attaches it as `Authorization: Bearer <token>` on every
/// outgoing request.
///
/// Traefik `mobile-token` ForwardAuth middleware validates every
/// request at `/auth/validate` (any method).  On a 401 the token is
/// cleared and the SSO flow re-runs.
class TokenExchangeAuthProvider implements AuthProvider {
  static const _tokenKey = 'api_token';

  final String baseUrl;
  final http.Client _httpClient;

  String? _cachedToken;
  final FlutterSecureStorage _secureStorage;
  StreamSubscription<Uri>? _deepLinkSub;

  /// Shared [AppLinks] instance for deep-link listening.
  @visibleForTesting
  static AppLinks? appLinksOverride;

  AppLinks get _appLinks => appLinksOverride ?? AppLinks();

  TokenExchangeAuthProvider({
    required this.baseUrl,
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  })  : _httpClient = httpClient ?? http.Client(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ------------------------------------------------------------------
  // AuthProvider interface
  // ------------------------------------------------------------------

  @override
  Future<Map<String, String>> requestHeaders() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
    return {};
  }

  // ------------------------------------------------------------------
  // Token lifecycle
  // ------------------------------------------------------------------

  /// Return the currently-valid Bearer token, or `null`.
  ///
  /// Reads from the in-memory cache first; falls back to secure
  /// storage.
  Future<String?> getToken() async {
    _cachedToken ??= await _secureStorage.read(key: _tokenKey);
    return _cachedToken;
  }

  /// Persist [token] to secure storage and the in-memory cache.
  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  /// Wipe the stored token (log-out / 401).
  Future<void> clearToken() async {
    _cachedToken = null;
    await _secureStorage.delete(key: _tokenKey);
  }

  /// `true` when the user has a stored (non-empty) token.
  Future<bool> get isLoggedIn async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ------------------------------------------------------------------
  // SSO login flow
  // ------------------------------------------------------------------

  /// Begin listening for deep-link callbacks and start the SSO flow
  /// if no token is present.
  ///
  /// Call once at app startup.  When no valid token exists the
  /// provider opens the SSO login URL in an external browser;
  /// after the user logs in the SSO gateway redirects to
  /// `robotsixchat://callback?code=…` which this provider
  /// intercepts and exchanges for a Bearer token.
  void initialize() {
    _deepLinkSub?.cancel();
    _deepLinkSub = _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  /// Dispose deep-link listener (call in app dispose / teardown).
  void dispose() {
    _deepLinkSub?.cancel();
    _deepLinkSub = null;
  }

  /// Open the SSO login URL for [baseUrl] in an external browser.
  ///
  /// The login URL includes a `redirect_uri` pointing back to the
  /// app's custom scheme so the provider can receive the callback.
  Future<bool> startLogin() async {
    final loginUri = Uri.parse('$baseUrl/auth/login').replace(
      queryParameters: {'redirect_uri': 'robotsixchat://callback'},
    );

    final launched = await launchUrl(
      loginUri,
      mode: LaunchMode.externalApplication,
    );
    return launched;
  }

  /// Handle a deep-link callback from the SSO provider.
  ///
  /// Expected URL shape: `robotsixchat://callback?code=<exchange_code>`
  /// The code is sent to `GET /auth/token` which returns the long-lived
  /// Bearer token.
  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'robotsixchat' || uri.host != 'callback') {
      return;
    }

    final code = uri.queryParameters['code'] ?? uri.queryParameters['token'];
    if (code == null || code.isEmpty) return;

    try {
      final token = await _exchangeCodeForToken(code);
      await saveToken(token);
    } on Exception {
      // Exchange failed — caller can inspect isLoggedIn and retry.
    }
  }

  /// Exchange an SSO auth code for a long-lived Bearer token.
  ///
  /// Calls `GET $baseUrl/auth/token?code=$code`.  The backend
  /// validates the code against the SSO session and returns a
  /// Fernet-signed Bearer token as `{token: "…"}`.
  @visibleForTesting
  Future<String> _exchangeCodeForToken(String code) async {
    final uri = Uri.parse('$baseUrl/auth/token').replace(
      queryParameters: {'code': code},
    );

    final response = await _httpClient.get(uri);

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }

    // The backend is expected to return JSON with a "token" field.
    final body = response.body;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final token = json['token'] as String?;
      if (token != null && token.isNotEmpty) return token;
    } on FormatException {
      // Not JSON — the body itself might be the token.
    }
    // Fallback: treat the entire response body as the token (trimmed).
    final trimmed = body.trim();
    if (trimmed.isNotEmpty) return trimmed;
    throw const FormatException('Empty token in exchange response');
  }
}